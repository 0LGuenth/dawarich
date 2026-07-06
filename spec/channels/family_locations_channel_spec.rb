# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamilyLocationsChannel, type: :channel do
  let(:user) { create(:user) }

  before do
    allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(true)
    stub_connection current_user: user
  end

  it 'streams for every family the user belongs to' do
    fam_a = create(:family)
    fam_b = create(:family)
    create(:family_membership, user: user, family: fam_a)
    create(:family_membership, user: user, family: fam_b)

    subscribe

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(fam_a)
    expect(subscription).to have_stream_for(fam_b)
  end

  it 'rejects a user in no families' do
    subscribe
    expect(subscription).to be_rejected
  end
end
