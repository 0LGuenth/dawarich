# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Families::Locations', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before { allow(DawarichSettings).to receive(:family_feature_available_for?).and_return(true) }

  describe 'GET /api/v1/families/locations' do
    it 'returns deduped flat locations and grouped families' do
      user = create(:user)
      fam_a = create(:family)
      fam_b = create(:family)
      create(:family_membership, user: user, family: fam_a)
      create(:family_membership, user: user, family: fam_b)

      sharer = create(:user)
      m_a = create(:family_membership, user: sharer, family: fam_a)
      m_b = create(:family_membership, user: sharer, family: fam_b)
      m_a.update_sharing!(true, duration: 'permanent')
      m_b.update_sharing!(true, duration: 'permanent')
      create(:point, user: sharer, timestamp: 1.hour.ago.to_i)

      get '/api/v1/families/locations', headers: { 'Authorization' => "Bearer #{user.api_key}" }

      body = response.parsed_body
      # sharer is in BOTH of user's families → appears once in flat list, twice across groups
      expect(body['locations'].map { |l| l['user_id'] }).to contain_exactly(sharer.id)
      expect(body['groups'].size).to eq(2)
      expect(body['groups'].flat_map { |g| g['members'].map { |m| m['user_id'] } }).to eq([sharer.id, sharer.id])
    end

    it 'includes sharing status' do
      user = create(:user)
      family = create(:family)
      membership = create(:family_membership, user: user, family: family)
      membership.update_sharing!(true, duration: 'permanent')

      get '/api/v1/families/locations', headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['sharing_enabled']).to be true
    end

    context 'without API key' do
      it 'returns unauthorized' do
        get '/api/v1/families/locations'

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with invalid API key' do
      it 'returns unauthorized' do
        get '/api/v1/families/locations', params: { api_key: 'invalid' }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is not in a family' do
      it 'returns not_found' do
        solo_user = create(:user)

        get '/api/v1/families/locations', params: { api_key: solo_user.api_key }

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error']).to eq('User is not part of a family')
      end
    end
  end

  describe 'GET /api/v1/families/locations/history' do
    it 'returns a flat members list with real coordinates' do
      user = create(:user)
      fam = create(:family)
      create(:family_membership, user: user, family: fam)
      sharer = create(:user)
      m = create(:family_membership, user: sharer, family: fam)
      m.update_sharing!(true, duration: 'permanent', share_history: true, history_window: 'all')
      # Backdate the sharing start so the 1.hour.ago point falls within the window
      # (update_sharing! defaults sharing_started_at to Time.current).
      m.update!(sharing_started_at: 3.hours.ago)
      create(:point, user: sharer, lonlat: 'POINT(13.4 52.5)', timestamp: 1.hour.ago.to_i)

      get '/api/v1/families/locations/history',
          params: { start_at: 2.hours.ago.iso8601, end_at: Time.current.iso8601 },
          headers: { 'Authorization' => "Bearer #{user.api_key}" }

      body = response.parsed_body
      expect(body['members'].size).to eq(1)
      lat, lon, = body['members'].first['points'].first
      expect(lat.to_f).to be_within(0.0001).of(52.5)
      expect(lon.to_f).to be_within(0.0001).of(13.4)
    end

    context 'without start_at or end_at' do
      it 'returns bad request' do
        user = create(:user)
        family = create(:family)
        create(:family_membership, user: user, family: family)

        get '/api/v1/families/locations/history',
            params: { api_key: user.api_key }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'without API key' do
      it 'returns unauthorized' do
        get '/api/v1/families/locations/history',
            params: { start_at: 1.day.ago.iso8601, end_at: Time.current.iso8601 }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when no members are sharing' do
      it 'returns empty members array' do
        user = create(:user)
        family = create(:family)
        create(:family_membership, user: user, family: family)
        create(:family_membership, user: create(:user), family: family)

        get '/api/v1/families/locations/history',
            params: { api_key: user.api_key, start_at: 1.day.ago.iso8601, end_at: Time.current.iso8601 }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['members']).to eq([])
      end
    end
  end
end
