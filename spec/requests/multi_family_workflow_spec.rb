# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Multi-family workflow', type: :request do
  before { allow(DawarichSettings).to receive(:family_feature_available_for?).and_return(true) }

  it 'lets a user create two families and share independently' do
    user = create(:user)
    sign_in user

    # Create first family
    expect do
      post families_path, params: { family: { name: 'Ski Group' } }
    end.to change { user.families.count }.by(1)

    # Create second family while already in one
    expect do
      post families_path, params: { family: { name: 'Poker Group' } }
    end.to change { user.families.count }.by(1)

    ski = user.families.find_by(name: 'Ski Group')
    poker = user.families.find_by(name: 'Poker Group')

    # Share in ski only
    patch family_location_sharing_path(ski), params: { enabled: 'true', duration: 'permanent' }

    expect(user.membership_for(ski).sharing_active?).to be(true)
    expect(user.membership_for(poker).sharing_active?).to be(false)
  end

  it 'lets a user in a family accept an invitation to a second' do
    user = create(:user)
    create(:family_membership, user: user, family: create(:family))
    other = create(:family)
    invitation = create(:family_invitation, email: user.email, family: other)
    sign_in user

    expect do
      post accept_family_invitation_path(token: invitation.token)
    end.to change { user.families.count }.by(1)
  end
end
