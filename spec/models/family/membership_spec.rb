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
