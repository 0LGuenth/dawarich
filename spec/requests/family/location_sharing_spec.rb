# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family::LocationSharing', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let!(:user_membership) { create(:family_membership, user: user, family: family, role: :owner) }

  before { sign_in user }

  describe 'PATCH /families/:family_id/location_sharing' do
    context 'when enabling location sharing' do
      around do |example|
        travel_to(Time.zone.local(2024, 1, 1, 12, 0, 0)) { example.run }
      end

      it 'enables location sharing with duration' do
        patch family_location_sharing_path(family),
              params: { enabled: true, duration: '1h' },
              as: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['enabled']).to be true
        expect(json_response['duration']).to eq('1h')
        expect(json_response['message']).to eq('Location sharing enabled for 1 hour')
        expect(json_response['expires_at']).to eq(1.hour.from_now.utc.iso8601)
      end

      it 'enables location sharing permanently' do
        patch family_location_sharing_path(family),
              params: { enabled: true, duration: 'permanent' },
              as: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['enabled']).to be true
        expect(json_response['duration']).to eq('permanent')
        expect(json_response).not_to have_key('expires_at')
      end
    end

    context 'when enabling with share_history and history_window' do
      it 'persists share_history and history_window' do
        patch family_location_sharing_path(family),
              params: { enabled: true, duration: 'permanent', share_history: true, history_window: '7d' },
              as: :json

        expect(response).to have_http_status(:ok)
        user_membership.reload
        expect(user_membership.share_history?).to be true
        expect(user_membership.history_window).to eq('7d')
      end

      it 'rejects invalid history_window values' do
        patch family_location_sharing_path(family),
              params: { enabled: true, duration: 'permanent', history_window: '<script>alert(1)</script>' },
              as: :json

        expect(response).to have_http_status(:ok)
        user_membership.reload
        expect(user_membership.history_window).to eq(UserFamily::DEFAULT_HISTORY_WINDOW)
      end
    end

    context 'when disabling location sharing' do
      before do
        user_membership.update_sharing!(true, duration: '1h')
      end

      it 'disables location sharing' do
        patch family_location_sharing_path(family),
              params: { enabled: false },
              as: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['enabled']).to be false
        expect(json_response['message']).to eq('Location sharing disabled')
      end
    end

    context 'when the target family belongs to a different membership' do
      it 'enables sharing only for the membership in the target family' do
        user = create(:user)
        fam_a = create(:family)
        fam_b = create(:family)
        m_a = create(:family_membership, user: user, family: fam_a)
        m_b = create(:family_membership, user: user, family: fam_b)
        sign_in user

        patch family_location_sharing_path(fam_a), params: { enabled: 'true', duration: 'permanent' }

        expect(m_a.reload.sharing_active?).to be(true)
        expect(m_b.reload.sharing_active?).to be(false)
      end
    end

    context 'when user is not in a family' do
      let(:solo_user) { create(:user) }

      before do
        sign_out user
        sign_in solo_user
      end

      it 'returns not_found' do
        patch family_location_sharing_path(family),
              params: { enabled: true, duration: '1h' },
              as: :json

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('User is not part of this family')
      end
    end

    context 'when update fails' do
      before do
        allow_any_instance_of(Family::Membership).to receive(:update_sharing!)
          .and_raise(StandardError, 'Database error')
      end

      it 'returns internal server error' do
        patch family_location_sharing_path(family),
              params: { enabled: true, duration: '1h' },
              as: :json

        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['message']).to eq('An error occurred while updating location sharing')
      end
    end

    context 'without authentication' do
      before { sign_out user }

      it 'returns unauthorized' do
        patch family_location_sharing_path(family),
              params: { enabled: true, duration: '1h' },
              as: :json

        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('You need to sign in or sign up before continuing.')
      end
    end

    context 'when enabling sharing' do
      it 'enables sharing with duration and updates the membership' do
        patch family_location_sharing_path(family),
              params: { enabled: true, duration: '1h' },
              as: :json

        expect(response).to have_http_status(:ok)
        expect(user_membership.reload.sharing_active?).to be(true)
      end

      it 'enables sharing permanently and updates the membership' do
        patch family_location_sharing_path(family),
              params: { enabled: true, duration: 'permanent' },
              as: :json

        expect(response).to have_http_status(:ok)
        expect(user_membership.reload.sharing_active?).to be(true)
      end

      it 'disables sharing and updates the membership' do
        user_membership.update_sharing!(true, duration: '1h')

        patch family_location_sharing_path(family),
              params: { enabled: false },
              as: :json

        expect(response).to have_http_status(:ok)
        expect(user_membership.reload.sharing_active?).to be(false)
      end
    end

    context 'when the user is not part of the family (turbo_stream)' do
      it 'returns turbo_stream flash error' do
        solo_user = create(:user)
        sign_out user
        sign_in solo_user

        patch family_location_sharing_path(family),
              params: { enabled: true, duration: '1h' },
              as: :turbo_stream

        expect(response).to have_http_status(:not_found)
        expect_turbo_stream_response
        expect_flash_stream('User is not part of this family')
      end
    end
  end
end
