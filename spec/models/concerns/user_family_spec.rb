# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserFamily, type: :model do
  let(:user) { create(:user) }

  describe '#families' do
    it 'returns all families the user belongs to' do
      fam_a = create(:family)
      fam_b = create(:family)
      create(:family_membership, user: user, family: fam_a)
      create(:family_membership, user: user, family: fam_b)

      expect(user.families).to contain_exactly(fam_a, fam_b)
    end
  end

  describe '#member_of? / #owner_of?' do
    it 'is true only for families the user belongs to / owns' do
      owned = create(:family)
      joined = create(:family)
      other = create(:family)
      create(:family_membership, :owner, user: user, family: owned)
      create(:family_membership, user: user, family: joined)

      expect(user.member_of?(owned)).to be(true)
      expect(user.member_of?(joined)).to be(true)
      expect(user.member_of?(other)).to be(false)
      expect(user.owner_of?(owned)).to be(true)
      expect(user.owner_of?(joined)).to be(false)
    end
  end

  describe '#can_delete_account?' do
    it 'is false when the user owns a family with other members' do
      fam = create(:family)
      create(:family_membership, :owner, user: user, family: fam)
      create(:family_membership, user: create(:user), family: fam)

      expect(user.can_delete_account?).to be(false)
    end

    it 'is true when the user only owns solo families' do
      fam = create(:family)
      create(:family_membership, :owner, user: user, family: fam)

      expect(user.can_delete_account?).to be(true)
    end
  end

  describe '#can_create_more_families?' do
    it 'is false once total memberships reach MAX_FAMILIES' do
      stub_const('UserFamily::MAX_FAMILIES', 2)
      create(:family_membership, user: user, family: create(:family))
      create(:family_membership, user: user, family: create(:family))

      expect(user.can_create_more_families?).to be(false)
    end

    it 'is true below the cap' do
      stub_const('UserFamily::MAX_FAMILIES', 2)
      create(:family_membership, user: user, family: create(:family))

      expect(user.can_create_more_families?).to be(true)
    end
  end

  describe '#latest_location_for_family' do
    let(:family) { create(:family) }
    let!(:membership) { create(:family_membership, user: user, family: family, role: :owner) }

    before { membership.update_sharing!(true, duration: 'permanent') }

    it 'includes the display name with emoji for standalone family map labels' do
      user.update!(first_name: '🧑 Ada', last_name: 'Example')
      create(:point, user: user)

      expect(user.latest_location_for_family[:name]).to eq('🧑 Ada Example')
    end
  end
end
