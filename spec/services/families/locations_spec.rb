# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::Locations do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  before { allow(DawarichSettings).to receive(:family_feature_available_for?).and_return(true) }

  # update_sharing! stamps sharing_started_at at "now"; back-date it so points
  # created in the past fall inside the history window.
  def enable_sharing(membership, **opts)
    membership.update!(sharing_started_at: 1.week.ago)
    membership.update_sharing!(true, duration: 'permanent', **opts)
    membership
  end

  describe '#call' do
    it 'returns groups per family with only sharing members' do
      fam_a = create(:family)
      create(:family_membership, user: user, family: fam_a)
      sharer = create(:user)
      enable_sharing(create(:family_membership, user: sharer, family: fam_a))
      create(:point, user: sharer, timestamp: 1.hour.ago.to_i)
      # A non-sharing member is excluded
      create(:family_membership, user: create(:user), family: fam_a)

      groups = described_class.new(user).call
      expect(groups.size).to eq(1)
      expect(groups.first[:family_id]).to eq(fam_a.id)
      expect(groups.first[:family_name]).to eq(fam_a.name)
      expect(groups.first[:members].map { |x| x[:user_id] }).to contain_exactly(sharer.id)
    end

    it 'returns a group per family the user belongs to' do
      fam_a = create(:family)
      fam_b = create(:family)
      create(:family_membership, user: user, family: fam_a)
      create(:family_membership, user: user, family: fam_b)

      sharer_a = create(:user)
      sharer_b = create(:user)
      enable_sharing(create(:family_membership, user: sharer_a, family: fam_a))
      enable_sharing(create(:family_membership, user: sharer_b, family: fam_b))
      create(:point, user: sharer_a, timestamp: 1.hour.ago.to_i)
      create(:point, user: sharer_b, timestamp: 1.hour.ago.to_i)

      groups = described_class.new(user).call
      expect(groups.map { |g| g[:family_id] }).to contain_exactly(fam_a.id, fam_b.id)
    end

    it 'excludes families with no sharing members' do
      fam = create(:family)
      create(:family_membership, user: user, family: fam)
      create(:family_membership, user: create(:user), family: fam)

      expect(described_class.new(user).call).to eq([])
    end

    it 'returns empty array when user is in no families' do
      expect(described_class.new(user).call).to eq([])
    end

    it 'returns empty array when the family feature is unavailable' do
      allow(DawarichSettings).to receive(:family_feature_available_for?).and_return(false)
      fam = create(:family)
      create(:family_membership, user: user, family: fam)

      expect(described_class.new(user).call).to eq([])
    end

    context 'when the caller is a cloud user without the family plan' do
      before { allow(DawarichSettings).to receive(:family_feature_available_for?).and_return(false) }

      it 'returns an empty array even when members share' do
        fam = create(:family)
        create(:family_membership, user: user, family: fam)
        sharer = create(:user)
        enable_sharing(create(:family_membership, user: sharer, family: fam))
        create(:point, user: sharer, timestamp: 1.hour.ago.to_i)

        expect(described_class.new(user).call).to eq([])
      end
    end
  end

  describe '#history' do
    it 'returns empty array when user is in no families' do
      result = described_class.new(user).history(start_at: 1.day.ago, end_at: Time.current)
      expect(result).to eq([])
    end

    context 'when feature is disabled' do
      before { allow(DawarichSettings).to receive(:family_feature_available_for?).and_return(false) }

      it 'returns empty array' do
        fam = create(:family)
        create(:family_membership, user: user, family: fam)
        result = described_class.new(user).history(start_at: 1.day.ago, end_at: Time.current)
        expect(result).to eq([])
      end
    end

    it 'returns grouped history points for sharing members' do
      fam = create(:family)
      create(:family_membership, user: user, family: fam)
      sharer = create(:user)
      enable_sharing(create(:family_membership, user: sharer, family: fam), share_history: true, history_window: 'all')
      create(:point, user: sharer, timestamp: 3.hours.ago.to_i)
      create(:point, user: sharer, timestamp: 1.hour.ago.to_i)

      groups = described_class.new(user).history(start_at: 1.day.ago, end_at: Time.current)
      expect(groups.size).to eq(1)
      member = groups.first[:members].first
      expect(member[:user_id]).to eq(sharer.id)
      expect(member[:email]).to eq(sharer.email)
      expect(member[:email_initial]).to eq(sharer.email.first.upcase)
      expect(member[:sharing_since]).to be_present
      expect(member[:points].length).to eq(2)
    end

    it 'excludes members whose sharing is disabled' do
      fam = create(:family)
      create(:family_membership, user: user, family: fam)
      sharer = create(:user)
      create(:family_membership, user: sharer, family: fam) # sharing off
      create(:point, user: sharer, timestamp: 1.hour.ago.to_i)

      expect(described_class.new(user).history(start_at: 1.day.ago, end_at: Time.current)).to eq([])
    end

    # History must return real coordinates from lonlat,
    # not the legacy nil latitude/longitude columns (which yield [nil, nil, ts]).
    it 'returns real coordinates in history points' do
      fam = create(:family)
      create(:family_membership, user: user, family: fam)
      sharer = create(:user)
      enable_sharing(create(:family_membership, user: sharer, family: fam), share_history: true, history_window: 'all')
      create(:point, user: sharer, lonlat: 'POINT(13.4 52.5)', timestamp: 1.hour.ago.to_i)

      groups = described_class.new(user).history(start_at: 2.hours.ago, end_at: Time.current)
      pts = groups.first[:members].first[:points]
      lat, lon, = pts.first
      expect(lat.to_f).to be_within(0.0001).of(52.5)
      expect(lon.to_f).to be_within(0.0001).of(13.4)
    end

    it 'caps points at 5000 per member' do
      fam = create(:family)
      create(:family_membership, user: user, family: fam)
      sharer = create(:user)
      enable_sharing(create(:family_membership, user: sharer, family: fam), share_history: true, history_window: 'all')

      timestamps = (1..5500).map { |i| i.minutes.ago.to_i }
      points_data = timestamps.map do |ts|
        { user_id: sharer.id, timestamp: ts, lonlat: 'POINT(0 0)', raw_data: '{}' }
      end
      Point.insert_all(points_data)

      groups = described_class.new(user).history(start_at: 5.days.ago, end_at: Time.current)
      expect(groups.first[:members].first[:points].length).to be <= 5000
    end
  end
end
