# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, 'family methods', type: :model do
  let(:user) { create(:user) }

  describe 'family associations' do
    it { is_expected.to have_many(:family_memberships).dependent(:destroy).class_name('Family::Membership') }
    it { is_expected.to have_many(:families).through(:family_memberships) }
    it {
      is_expected.to have_many(:created_families).class_name('Family')
                                                 .with_foreign_key('creator_id').dependent(:destroy)
    }
    it {
      is_expected.to have_many(:sent_family_invitations).class_name('Family::Invitation').with_foreign_key('invited_by_id').dependent(:destroy)
    }
  end

  describe '#in_family?' do
    context 'when user has no family membership' do
      it 'returns false' do
        expect(user.in_family?).to be false
      end
    end

    context 'when user has family membership' do
      let(:family) { create(:family, creator: user) }

      before do
        create(:family_membership, user: user, family: family)
      end

      it 'returns true' do
        expect(user.in_family?).to be true
      end
    end
  end

  describe '#owner_of?' do
    let(:family) { create(:family, creator: user) }

    context 'when user is family owner' do
      before do
        create(:family_membership, user: user, family: family, role: :owner)
      end

      it 'returns true' do
        expect(user.owner_of?(family)).to be true
      end
    end

    context 'when user is family member' do
      before do
        create(:family_membership, user: user, family: family, role: :member)
      end

      it 'returns false' do
        expect(user.owner_of?(family)).to be false
      end
    end

    context 'when user has no family membership' do
      it 'returns false' do
        expect(user.owner_of?(family)).to be false
      end
    end
  end

  describe 'dependent destroy behavior' do
    let(:family) { create(:family, creator: user) }

    context 'when user has sent invitations' do
      before do
        create(:family_invitation, family: family, invited_by: user)
      end

      it 'soft-deletes user but keeps invitations' do
        expect { user.destroy }.not_to change(Family::Invitation, :count)
        expect(user.deleted?).to be true
      end
    end

    context 'when user has family membership' do
      before do
        create(:family_membership, user: user, family: family)
      end

      it 'soft-deletes user but keeps membership' do
        expect { user.destroy }.not_to change(Family::Membership, :count)
        expect(user.deleted?).to be true
      end
    end
  end
end
