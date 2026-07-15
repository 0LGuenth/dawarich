# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::Create do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user: user, name: 'Test Family') }

  describe '#call' do
    context 'when user is not in a family' do
      it 'creates a family successfully' do
        expect { service.call }.to change(Family, :count).by(1)
        expect(service.family.name).to eq('Test Family')
        expect(service.family.creator).to eq(user)
      end

      it 'creates owner membership' do
        service.call
        membership = user.reload.family_memberships.first
        expect(membership.role).to eq('owner')
        expect(membership.family).to eq(service.family)
      end

      it 'returns true on success' do
        expect(service.call).to be true
      end
    end
  end

  describe 'multi-family' do
    let(:user) { create(:user) }

    it 'creates a second family when the user already belongs to one' do
      create(:family_membership, :owner, user: user, family: create(:family))

      service = described_class.new(user: user, name: 'Second Family')
      expect(service.call).to be(true)
      expect(user.reload.families.count).to eq(2)
    end

    it 'rejects creation at the MAX_FAMILIES cap' do
      stub_const('UserFamily::MAX_FAMILIES', 1)
      create(:family_membership, :owner, user: user, family: create(:family))

      service = described_class.new(user: user, name: 'Over Limit')
      expect(service.call).to be(false)
      expect(service.error_message).to match(/maximum number of families/i)
    end

    context 'when cloud and the user is not on the family plan' do
      let(:user) { create(:user, plan: :pro, skip_auto_trial: true) }

      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'returns false and does not create a family' do
        expect(service.call).to be false
        expect { service.call }.not_to change(Family, :count)
        expect(service.error_message).to eq('Family feature requires an active subscription')
      end
    end

    context 'when cloud and the user is on the family plan' do
      let(:user) { create(:user, plan: :family, skip_auto_trial: true) }

      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'creates a family' do
        expect { service.call }.to change(Family, :count).by(1)
      end
    end
  end
end
