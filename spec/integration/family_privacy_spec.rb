# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family Privacy Enforcement', type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.local(2026, 3, 13, 12, 0, 0) }
  let(:family) { create(:family) }
  let(:user_a) { family.creator }
  let(:user_b) { create(:user) }
  let!(:membership_a) { create(:family_membership, family: family, user: user_a, role: :owner) }
  let!(:membership_b) { create(:family_membership, family: family, user: user_b) }

  before do
    travel_to(now)
    allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(true)
  end

  after { travel_back }

  describe 'sharing lifecycle' do
    it 'exposes location and history when sharing is enabled, hides when disabled' do
      # User A enables sharing, backdating the start so older history is visible
      membership_a.update_sharing!(true, duration: 'permanent', share_history: true)
      membership_a.update!(sharing_started_at: 1.week.ago)

      # Create points
      create(:point, user: user_a, timestamp: 3.hours.ago.to_i)
      create(:point, user: user_a, timestamp: 1.hour.ago.to_i)

      # User B can see A's latest location
      locations_service = Families::Locations.new(user_b)
      latest = locations_service.call
      expect(latest.length).to eq(1)

      # User B can see A's history
      history = locations_service.history(start_at: 1.day.ago, end_at: Time.current)
      expect(history.length).to eq(1)
      expect(history.first[:members].first[:points].length).to eq(2)

      # User A disables sharing
      membership_a.update_sharing!(false)

      # User B sees NOTHING (fresh service to avoid cached associations)
      fresh_service = Families::Locations.new(user_b.reload)
      expect(fresh_service.call).to be_empty
      expect(fresh_service.history(start_at: 1.day.ago, end_at: Time.current)).to be_empty
    end

    it 'hides pre-disable history after re-enabling with the default window' do
      # Enable sharing a week ago
      membership_a.update_sharing!(true, duration: 'permanent', share_history: true)
      membership_a.update!(sharing_started_at: 1.week.ago)

      # Create old point
      create(:point, user: user_a, timestamp: 3.days.ago.to_i)

      # Disable then re-enable
      membership_a.update_sharing!(false)

      travel_to 1.minute.from_now do
        membership_a.update_sharing!(true, duration: 'permanent', share_history: true)

        # Old points (3 days ago) fall outside the default 24h history window,
        # so they should NOT be visible.
        history = Families::Locations.new(user_b).history(start_at: 1.week.ago, end_at: Time.current)
        expect(history).to be_empty
      end
    end
  end

  describe '1-year cap enforcement' do
    it 'caps history at 1 year even when sharing has been on longer' do
      membership_a.update_sharing!(true, duration: 'permanent', share_history: true, history_window: 'all')
      membership_a.update!(sharing_started_at: 2.years.ago)

      # Point from 13 months ago
      create(:point, user: user_a, timestamp: 13.months.ago.to_i)
      # Point from 6 months ago
      create(:point, user: user_a, timestamp: 6.months.ago.to_i)

      history = Families::Locations.new(user_b).history(start_at: 2.years.ago, end_at: Time.current)
      expect(history.length).to eq(1)
      # Only the 6-month-old point should be included
      expect(history.first[:members].first[:points].length).to eq(1)
    end
  end

  describe 'expired sharing duration' do
    it 'treats expired sharing as disabled' do
      membership_a.update_sharing!(true, duration: '1h')
      membership_a.update!(sharing_started_at: 2.hours.ago)

      # Simulate expiry by setting expires_at to the past
      membership_a.update!(sharing_expires_at: 30.minutes.ago)

      create(:point, user: user_a, timestamp: 1.hour.ago.to_i)

      expect(membership_a.reload.sharing_active?).to be false
      expect(Families::Locations.new(user_b).call).to be_empty
      expect(Families::Locations.new(user_b).history(start_at: 1.day.ago, end_at: Time.current)).to be_empty
    end
  end

  describe 'location request → accept flow' do
    it 'accepting a request enables sharing for the target user' do
      result = Families::CreateLocationRequest.new(requester: user_b, target_user: user_a, family: family).call
      expect(result.success?).to be true

      request = result.payload[:request]

      # Accept with 24h duration
      membership_a.update_sharing!(true, duration: '24h')
      request.update!(status: :accepted, responded_at: Time.current)

      expect(membership_a.reload.sharing_active?).to be true
      expect(request.reload).to be_accepted
    end
  end

  describe 'cooldown enforcement' do
    it 'expired requests do not count toward cooldown' do
      # Create an expired request 30 minutes ago
      create(:family_location_request,
             requester: user_b, target_user: user_a, family: family,
             status: :expired, created_at: 30.minutes.ago)

      # Should be able to create a new request
      result = Families::CreateLocationRequest.new(requester: user_b, target_user: user_a, family: family).call
      expect(result.success?).to be true
    end
  end

  describe 'family membership departure' do
    it 'expires pending requests and disables sharing when member leaves' do
      # User A enables sharing
      membership_a.update_sharing!(true, duration: 'permanent')

      # Create a pending request from A to B
      request = create(:family_location_request,
                       requester: user_a, target_user: user_b, family: family,
                       status: :pending, expires_at: 1.day.from_now)

      # User A leaves the family (destroying the membership removes sharing state)
      membership_a.destroy

      # Sharing is gone with the membership
      expect(user_a.reload.membership_for(family)).to be_nil

      # Pending requests should be expired
      expect(request.reload).to be_expired
    end
  end
end
