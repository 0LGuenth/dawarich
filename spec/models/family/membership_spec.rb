# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family::Membership, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:family) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validations' do
    subject { build(:family_membership) }

    it { is_expected.to validate_presence_of(:user_id) }
    it {
      is_expected.to validate_uniqueness_of(:user_id).scoped_to(:family_id)
                                                     .with_message('is already a member of this family')
    }
    it { is_expected.to validate_presence_of(:role) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:role).with_values(owner: 0, member: 1) }
  end

  describe 'one family per user constraint' do
    let(:user) { create(:user) }
    let(:family1) { create(:family) }
    let(:family2) { create(:family) }

    it 'allows a user to be in one family' do
      membership1 = build(:family_membership, family: family1, user: user)
      expect(membership1).to be_valid
    end

    it 'prevents a user from joining the same family twice' do
      create(:family_membership, family: family1, user: user)
      membership2 = build(:family_membership, family: family1, user: user)

      expect(membership2).not_to be_valid
      expect(membership2.errors[:user_id]).to include('is already a member of this family')
    end
  end

  describe 'multiple memberships per user' do
    it 'allows one user to belong to two families' do
      user = create(:user)
      fam_a = create(:family)
      fam_b = create(:family)

      create(:family_membership, user: user, family: fam_a)
      second = build(:family_membership, user: user, family: fam_b)

      expect(second).to be_valid
      expect { second.save! }.not_to raise_error
    end
  end

  describe 'cap enforcement at the model level (defense-in-depth)' do
    describe 'per-user MAX_FAMILIES cap' do
      let(:user) { create(:user) }

      it 'blocks a direct create once the user is at MAX_FAMILIES' do
        stub_const('UserFamily::MAX_FAMILIES', 2)
        create_list(:family_membership, 2, user: user)

        over_limit = build(:family_membership, user: user, family: create(:family))

        expect(over_limit).not_to be_valid
        expect(over_limit.errors[:base].join).to match(/maximum number of families/i)
      end

      it 'allows a create below the cap' do
        stub_const('UserFamily::MAX_FAMILIES', 2)
        create(:family_membership, user: user)

        expect(build(:family_membership, user: user, family: create(:family))).to be_valid
      end

      it 'enforces the cap even in self-hosted mode' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
        stub_const('UserFamily::MAX_FAMILIES', 1)
        create(:family_membership, user: user)

        expect(build(:family_membership, user: user, family: create(:family))).not_to be_valid
      end
    end

    describe 'per-family MAX_MEMBERS cap' do
      let(:family) { create(:family) }

      context 'when not self-hosted' do
        before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

        it 'blocks a direct create once the family is at MAX_MEMBERS' do
          create_list(:family_membership, Family::MAX_MEMBERS, family: family, role: :member)

          over_limit = build(:family_membership, family: family, user: create(:user))

          expect(over_limit).not_to be_valid
          expect(over_limit.errors[:base].join).to match(/maximum number of members/i)
        end

        it 'allows a create below the cap' do
          create_list(:family_membership, Family::MAX_MEMBERS - 1, family: family, role: :member)

          expect(build(:family_membership, family: family, user: create(:user))).to be_valid
        end
      end

      it 'does not enforce the member cap in self-hosted mode' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
        create_list(:family_membership, Family::MAX_MEMBERS, family: family, role: :member)

        expect(build(:family_membership, family: family, user: create(:user))).to be_valid
      end
    end

    it 'still allows an owner to create the first membership of a new family' do
      owner = create(:user)
      new_family = create(:family, creator: owner)

      expect(build(:family_membership, :owner, family: new_family, user: owner)).to be_valid
    end
  end

  describe 'per-membership sharing' do
    let(:user) { create(:user) }
    let(:membership) { create(:family_membership, user: user) }

    it 'is inactive by default' do
      expect(membership.sharing_active?).to be(false)
    end

    it 'activates sharing with a duration and sets started_at' do
      membership.update_sharing!(true, duration: '1h')
      expect(membership.sharing_active?).to be(true)
      expect(membership.sharing_started_at).to be_present
      expect(membership.sharing_expires_at).to be_within(2.minutes).of(1.hour.from_now)
    end

    it 'expires: enabled but past expiry is not active' do
      membership.update!(sharing_enabled: true, sharing_expires_at: 1.hour.ago)
      expect(membership.sharing_active?).to be(false)
    end

    it 'permanent duration leaves expiry nil and stays active' do
      membership.update_sharing!(true, duration: 'permanent')
      expect(membership.sharing_expires_at).to be_nil
      expect(membership.sharing_active?).to be(true)
    end

    it 'disabling clears active state' do
      membership.update_sharing!(true, duration: 'permanent')
      membership.update_sharing!(false)
      expect(membership.sharing_active?).to be(false)
    end

    it 'sharing is independent per family' do
      other = create(:family_membership, user: user)
      membership.update_sharing!(true, duration: 'permanent')
      expect(membership.sharing_active?).to be(true)
      expect(other.sharing_active?).to be(false)
    end

    it 'validates history_window, falling back to 24h' do
      membership.update_sharing!(true, duration: 'permanent', history_window: 'bogus')
      expect(membership.history_window).to eq('24h')
    end
  end

  describe '#latest_location' do
    let(:user) { create(:user) }
    let(:membership) { create(:family_membership, user: user) }

    it 'returns nil when sharing is not active' do
      create(:point, user: user, lonlat: 'POINT(13.4 52.5)', timestamp: 1.hour.ago.to_i)

      expect(membership.latest_location).to be_nil
    end

    it "returns a hash with the newest point's coordinates when active" do
      create(:point, user: user, lonlat: 'POINT(1 1)', timestamp: 2.days.ago.to_i)
      create(:point, user: user, lonlat: 'POINT(13.4 52.5)', timestamp: 1.hour.ago.to_i)

      membership.update_sharing!(true, duration: 'permanent')

      result = membership.latest_location

      expect(result[:latitude]).to be_within(0.01).of(52.5)
      expect(result[:longitude]).to be_within(0.01).of(13.4)
      expect(result[:user_id]).to eq(user.id)
      expect(result[:email]).to eq(user.email)
    end
  end

  describe '#history_points' do
    let(:user) { create(:user) }
    let(:membership) { create(:family_membership, user: user) }

    it 'returns Point.none when sharing is not active' do
      expect(membership.history_points(start_at: 2.days.ago, end_at: Time.current)).to eq(Point.none)
    end

    it 'returns Point.none when sharing is active but share_history is false' do
      membership.update_sharing!(true, duration: 'permanent', share_history: false)

      expect(membership.history_points(start_at: 2.days.ago, end_at: Time.current)).to eq(Point.none)
    end

    it 'returns Point.none when sharing_started_at is nil' do
      membership.update_columns(sharing_enabled: true, share_history: true, sharing_started_at: nil)

      expect(membership.history_points(start_at: 2.days.ago, end_at: Time.current)).to eq(Point.none)
    end

    it "returns the user's points within the window, ordered by timestamp asc" do
      membership.update_sharing!(true, duration: 'permanent', share_history: true, history_window: 'all')
      membership.update_columns(sharing_started_at: 3.days.ago)

      newest = create(:point, user: user, lonlat: 'POINT(1 1)', timestamp: 1.hour.ago.to_i)
      middle = create(:point, user: user, lonlat: 'POINT(2 2)', timestamp: 12.hours.ago.to_i)
      oldest = create(:point, user: user, lonlat: 'POINT(3 3)', timestamp: 1.day.ago.to_i)

      result = membership.history_points(start_at: 2.days.ago, end_at: Time.current)

      expect(result.to_a).to eq([oldest, middle, newest])
    end

    it 'exposes real coordinates from lonlat (regression #2977)' do
      membership.update_sharing!(true, duration: 'permanent', share_history: true, history_window: 'all')
      membership.update_columns(sharing_started_at: 3.days.ago)

      create(:point, user: user, lonlat: 'POINT(13.4 52.5)', timestamp: 1.hour.ago.to_i)

      point = membership.history_points(start_at: 2.days.ago, end_at: Time.current).first

      expect(point.lat).to be_within(0.01).of(52.5)
      expect(point.lon).to be_within(0.01).of(13.4)
    end

    it 'returns Point.none when effective_start is at or after end_at' do
      membership.update_sharing!(true, duration: 'permanent', share_history: true, history_window: 'all')

      # sharing_started_at defaults to Time.current, so an end_at in the past
      # makes effective_start >= end_at.
      expect(membership.history_points(start_at: 2.days.ago, end_at: 1.hour.ago)).to eq(Point.none)
    end

    it "clamps to the history_window: '24h' excludes points older than 24 hours" do
      membership.update_sharing!(true, duration: 'permanent', share_history: true, history_window: '24h')
      membership.update_columns(sharing_started_at: 10.days.ago)

      old_point = create(:point, user: user, lonlat: 'POINT(4 4)', timestamp: 5.days.ago.to_i)
      recent_point = create(:point, user: user, lonlat: 'POINT(5 5)', timestamp: 1.hour.ago.to_i)

      result = membership.history_points(start_at: 30.days.ago, end_at: Time.current)

      expect(result.to_a).to include(recent_point)
      expect(result.to_a).not_to include(old_point)
    end
  end

  describe 'cleanup_on_departure (after_destroy)' do
    let(:user) { create(:user) }
    let(:family) { create(:family) }
    let(:membership) { create(:family_membership, user: user, family: family) }

    it "expires this family's pending requests involving the user" do
      as_requester = create(:family_location_request, family: family, requester: user, status: :pending)
      as_target = create(:family_location_request, family: family, target_user: user, status: :pending)

      membership.destroy

      expect(as_requester.reload.status).to eq('expired')
      expect(as_target.reload.status).to eq('expired')
    end

    it 'does not expire pending requests in a different family' do
      other_family = create(:family)
      create(:family_membership, user: user, family: other_family)
      other_request = create(:family_location_request, family: other_family, requester: user, status: :pending)

      membership.destroy

      expect(other_request.reload.status).to eq('pending')
    end
  end

  describe 'role assignment' do
    let(:family) { create(:family) }

    context 'when created as owner' do
      let(:membership) { create(:family_membership, :owner, family: family) }

      it 'can be created' do
        expect(membership.role).to eq('owner')
        expect(membership.owner?).to be true
      end
    end

    context 'when created as member' do
      let(:membership) { create(:family_membership, family: family, role: :member) }

      it 'can be created' do
        expect(membership.role).to eq('member')
        expect(membership.member?).to be true
      end
    end

    it 'defaults to member role' do
      membership = create(:family_membership, family: family)
      expect(membership.role).to eq('member')
    end
  end
end
