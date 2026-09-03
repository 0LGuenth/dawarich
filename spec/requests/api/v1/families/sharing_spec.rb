# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Families::Sharing', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let!(:membership) { create(:family_membership, user: user, family: family, role: :owner) }

  describe 'PATCH /api/v1/families/sharing' do
    it 'enables sharing with duration and history settings' do
      patch '/api/v1/families/sharing',
            params: { enabled: true, duration: '24h', share_history: true, history_window: '30d' },
            headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['enabled']).to be true
      expect(json['expires_at']).to be_present
      expect(membership.reload.sharing_active?).to be true
      expect(membership.share_history?).to be true
      expect(membership.history_window).to eq('30d')
    end

    it 'disables sharing' do
      membership.update_sharing!(true, duration: 'permanent')

      patch '/api/v1/families/sharing',
            params: { enabled: false },
            headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(response).to have_http_status(:ok)
      expect(membership.reload.sharing_active?).to be false
    end

    it 'updates all memberships when the user belongs to multiple families' do
      other_family = create(:family, creator: user)
      other_membership = create(:family_membership, user: user, family: other_family, role: :owner)

      patch '/api/v1/families/sharing',
            params: { enabled: true, duration: 'permanent' },
            headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(response).to have_http_status(:ok)
      expect(membership.reload.sharing_active?).to be true
      expect(other_membership.reload.sharing_active?).to be true
    end

    it 'allows a lite-plan family member to update sharing under cloud entitlements' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      owner = create(:user, plan: :family, skip_auto_trial: true)
      cloud_family = create(:family, creator: owner)
      create(:family_membership, :owner, family: cloud_family, user: owner)
      lite_member = create(:user, plan: :lite, skip_auto_trial: true)
      create(:family_membership, family: cloud_family, user: lite_member)

      patch '/api/v1/families/sharing',
            params: { enabled: true, duration: 'permanent' },
            headers: { 'Authorization' => "Bearer #{lite_member.api_key}" }

      expect(response).to have_http_status(:ok)
      expect(lite_member.reload.membership_for(cloud_family).sharing_active?).to be true
    end

    it 'returns 404 for a user without a family' do
      solo = create(:user)

      patch '/api/v1/families/sharing',
            params: { enabled: true },
            headers: { 'Authorization' => "Bearer #{solo.api_key}" }

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 400 when enabled is missing' do
      membership.update_sharing!(true, duration: 'permanent')

      patch '/api/v1/families/sharing',
            params: { share_history: true },
            headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(response).to have_http_status(:bad_request)
      expect(membership.reload.sharing_active?).to be true
    end

    it 're-arms an expired timed share and reports the new expiry' do
      membership.update_sharing!(true, duration: '1h')

      travel 2.hours do
        patch '/api/v1/families/sharing',
              params: { enabled: true, share_history: true },
              headers: { 'Authorization' => "Bearer #{user.api_key}" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['enabled']).to be true
        expect(Time.zone.parse(json['expires_at'])).to be_future
        expect(membership.reload.sharing_active?).to be true
      end
    end
  end
end
