# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family::MembershipPolicy, type: :policy do
  let(:family) { create(:family) }
  let(:owner) { family.creator }
  let(:member) { create(:user) }
  let(:another_member) { create(:user) }
  let(:other_user) { create(:user) }

  let(:owner_membership) { create(:family_membership, :owner, family: family, user: owner) }
  let(:member_membership) { create(:family_membership, family: family, user: member) }
  let(:another_member_membership) { create(:family_membership, family: family, user: another_member) }

  describe '#create?' do
    let(:valid_invitation) { create(:family_invitation, family: family, email: member.email) }
    let(:expired_invitation) { create(:family_invitation, family: family, email: member.email, expires_at: 1.day.ago) }
    let(:accepted_invitation) { create(:family_invitation, :accepted, family: family, email: member.email) }
    let(:wrong_email_invitation) { create(:family_invitation, family: family, email: 'wrong@example.com') }

    context 'when user has valid invitation' do
      it 'allows user to create membership with valid pending invitation for their email' do
        policy = described_class.new(member, valid_invitation)

        expect(policy).to permit(:create)
      end
    end

    context 'when invitation is expired' do
      it 'denies user from creating membership with expired invitation' do
        policy = described_class.new(member, expired_invitation)

        expect(policy).not_to permit(:create)
      end
    end

    context 'when invitation is already accepted' do
      it 'denies user from creating membership with already accepted invitation' do
        policy = described_class.new(member, accepted_invitation)

        expect(policy).not_to permit(:create)
      end
    end

    context 'when invitation is for different email' do
      it 'denies user from creating membership with invitation for different email' do
        policy = described_class.new(member, wrong_email_invitation)

        expect(policy).not_to permit(:create)
      end
    end

    context 'with unauthenticated user' do
      it 'denies unauthenticated user from creating membership' do
        policy = described_class.new(nil, valid_invitation)

        expect(policy).not_to permit(:create)
      end
    end
  end

  describe '#destroy?' do
    context 'when user is removing themselves' do
      it 'allows user to remove their own membership (leave family)' do
        policy = described_class.new(member, member_membership)

        expect(policy).to permit(:destroy)
      end

      it 'allows owner to remove their own membership' do
        policy = described_class.new(owner, owner_membership)

        expect(policy).to permit(:destroy)
      end
    end

    context 'when user is family owner' do
      before do
        owner_membership
      end

      it 'allows family owner to remove other members' do
        policy = described_class.new(owner, member_membership)

        expect(policy).to permit(:destroy)
      end

      it 'allows family owner to remove multiple members' do
        policy1 = described_class.new(owner, member_membership)
        policy2 = described_class.new(owner, another_member_membership)

        expect(policy1).to permit(:destroy)
        expect(policy2).to permit(:destroy)
      end
    end

    context 'when user is regular family member' do
      before do
        member_membership
      end

      it 'denies regular member from removing other members' do
        policy = described_class.new(member, another_member_membership)

        expect(policy).not_to permit(:destroy)
      end

      it 'denies regular member from removing owner' do
        policy = described_class.new(member, owner_membership)

        expect(policy).not_to permit(:destroy)
      end
    end

    context 'when user is not in the family' do
      it 'denies user from removing membership of different family' do
        policy = described_class.new(other_user, member_membership)

        expect(policy).not_to permit(:destroy)
      end
    end

    context 'with unauthenticated user' do
      it 'denies unauthenticated user from removing membership' do
        policy = described_class.new(nil, member_membership)

        expect(policy).not_to permit(:destroy)
      end
    end
  end

  describe 'edge cases' do
    context 'when membership belongs to different family' do
      let(:other_family) { create(:family) }
      let(:other_family_owner) { other_family.creator }
      let(:other_family_membership) do
        create(:family_membership, :owner, family: other_family, user: other_family_owner)
      end

      before do
        owner_membership
      end

      it 'denies owner from destroying membership of different family' do
        policy = described_class.new(owner, other_family_membership)

        expect(policy).not_to permit(:destroy)
      end
    end

    context 'when owner tries to modify another owners membership' do
      let(:co_owner) { create(:user) }
      let(:co_owner_membership) { create(:family_membership, :owner, family: family, user: co_owner) }

      before do
        owner_membership
      end

      it 'allows owner to remove another owner (family owner has full control)' do
        policy = described_class.new(owner, co_owner_membership)

        expect(policy).to permit(:destroy)
      end
    end
  end

  describe 'authorization consistency' do
    it 'ensures owner can destroy all memberships in their family' do
      owner_membership

      policy = described_class.new(owner, member_membership)

      expect(policy).to permit(:destroy)
    end

    it 'ensures regular members can only remove their own membership' do
      member_membership

      own_policy = described_class.new(member, member_membership)
      other_policy = described_class.new(member, another_member_membership)

      # Can remove own membership
      expect(own_policy).to permit(:destroy)

      # Cannot remove others
      expect(other_policy).not_to permit(:destroy)
    end

    it 'ensures users can always leave the family (remove own membership)' do
      policy = described_class.new(member, member_membership)

      expect(policy).to permit(:destroy)
    end
  end

  describe '#destroy? multi-family' do
    it 'allows the owner of the record\'s family to remove a member' do
      family = create(:family)
      owner = create(:user)
      member = create(:user)
      create(:family_membership, :owner, user: owner, family: family)
      membership = create(:family_membership, user: member, family: family)

      expect(described_class.new(owner, membership).destroy?).to be(true)
    end

    it 'denies an owner of a DIFFERENT family' do
      family = create(:family)
      other_family = create(:family)
      outsider = create(:user)
      create(:family_membership, :owner, user: outsider, family: other_family)
      membership = create(:family_membership, user: create(:user), family: family)

      expect(described_class.new(outsider, membership).destroy?).to be(false)
    end
  end
end
