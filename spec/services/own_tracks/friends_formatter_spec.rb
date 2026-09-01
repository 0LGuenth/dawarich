# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OwnTracks::FriendsFormatter do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.local(2026, 3, 13, 12, 0, 0) }
  let(:user) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let(:other_user) { create(:user, email: 'jane@example.com') }
  let(:user_membership) { create(:family_membership, family: family, user: user, role: :owner) }
  let(:other_membership) { create(:family_membership, family: family, user: other_user) }

  before do
    travel_to(now)
    user_membership
    other_membership
  end

  after { travel_back }

  describe '#call' do
    subject(:payload) { described_class.new(user).call }

    context 'when a family member shares their location' do
      let!(:point) do
        create(:point, user: other_user, timestamp: 1.hour.ago.to_i, battery: 87, battery_status: :charging)
      end

      before { other_membership.update_sharing!(true, duration: 'permanent') }

      it 'returns a card followed by a location message' do
        expect(payload.map { _1[:_type] }).to eq(%w[card location])
      end

      it 'identifies the member by a short tracker id rather than their email' do
        tracker_ids = payload.map { _1[:tid] }

        expect(tracker_ids.uniq).to eq([other_user.id.to_s(36).upcase])
        expect(tracker_ids.first).not_to include('@')
      end

      it 'names the member on the card' do
        expect(payload.first).to include(_type: 'card', name: 'jane@example.com')
      end

      it 'reports the position of the latest point' do
        expect(payload.last).to include(
          _type: 'location',
          lat: point.lat,
          lon: point.lon,
          tst: point.timestamp,
          batt: 87,
          bs: 2
        )
      end

      it 'omits keys it has no value for instead of emitting nulls' do
        point.update!(battery: nil, battery_status: nil)

        expect(payload.last).not_to have_key(:batt)
        expect(payload.flat_map(&:values)).to all(be_present)
      end

      it 'excludes the requesting user even when they share too' do
        user_membership.update_sharing!(true, duration: 'permanent')
        create(:point, user: user, timestamp: 1.minute.ago.to_i)

        expect(payload.map { _1[:tid] }.uniq).to eq([other_user.id.to_s(36).upcase])
      end
    end

    describe 'battery status mapping' do
      before { other_membership.update_sharing!(true, duration: 'permanent') }

      {
        unknown: 0,
        unplugged: 1,
        discharging: 1,
        charging: 2,
        connected_not_charging: 0,
        full: 3
      }.each do |status, expected_code|
        it "maps #{status} to OwnTracks bs #{expected_code}" do
          create(:point, user: other_user, timestamp: 1.hour.ago.to_i, battery_status: status)

          expect(payload.last[:bs]).to eq(expected_code)
        end
      end
    end

    context 'when several members share' do
      let(:third_user) { create(:user) }
      let(:third_membership) { create(:family_membership, family: family, user: third_user) }

      before do
        third_membership
        [other_membership, third_membership].each do |membership|
          membership.update_sharing!(true, duration: 'permanent')
          create(:point, user: membership.user, timestamp: 1.hour.ago.to_i)
        end
      end

      it 'returns a card and a location for each of them' do
        expect(payload.count { _1[:_type] == 'card' }).to eq(2)
        expect(payload.count { _1[:_type] == 'location' }).to eq(2)
        expect(payload.map { _1[:tid] }.uniq.length).to eq(2)
      end
    end

    context 'when no member shares their location' do
      before { create(:point, user: other_user, timestamp: 1.hour.ago.to_i) }

      it 'returns an empty array' do
        expect(payload).to eq([])
      end
    end

    context 'when the family feature is unavailable to the caller' do
      before do
        allow(DawarichSettings).to receive(:family_feature_available_for?).and_return(false)
        other_membership.update_sharing!(true, duration: 'permanent')
        create(:point, user: other_user, timestamp: 1.hour.ago.to_i)
      end

      it 'returns an empty array' do
        expect(payload).to eq([])
      end
    end

    context 'when the user is not in a family' do
      let(:solo_user) { create(:user) }

      it 'returns an empty array' do
        expect(described_class.new(solo_user).call).to eq([])
      end
    end
  end
end
