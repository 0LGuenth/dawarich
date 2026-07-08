# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family', type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let!(:membership) { create(:family_membership, user: user, family: family, role: :owner) }

  before do
    sign_in user
  end

  describe 'GET /families/:id' do
    it 'shows the family page' do
      get family_path(family)
      expect(response).to have_http_status(:ok)
    end

    context 'when user is not in the family' do
      let(:outsider) { create(:user) }

      before { sign_in outsider }

      it 'returns not found' do
        get family_path(family)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /families/new' do
    context 'when user is not in a family' do
      let(:user_without_family) { create(:user) }

      before { sign_in user_without_family }

      it 'renders the new family form' do
        get new_family_path
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when user is already in a family' do
      it 'still renders the new family form (multi-family allowed)' do
        get new_family_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'POST /families' do
    let(:user_without_family) { create(:user) }

    before { sign_in user_without_family }

    context 'with valid attributes' do
      let(:valid_attributes) { { family: { name: 'Test Family' } } }

      it 'creates a new family' do
        expect do
          post families_path, params: valid_attributes
        end.to change(Family, :count).by(1)
      end

      it 'creates a family membership for the user' do
        expect do
          post families_path, params: valid_attributes
        end.to change(Family::Membership, :count).by(1)
      end

      it 'redirects to the new family with success message' do
        post families_path, params: valid_attributes

        expect(response).to have_http_status(:found)
        created_family = Family.find_by(name: 'Test Family')
        expect(response.location).to eq family_url(created_family)
        follow_redirect!
        expect(response.body).to include('Family created successfully!')
      end
    end

    context 'with invalid attributes' do
      let(:invalid_attributes) { { family: { name: '' } } }

      it 'does not create a family' do
        expect do
          post families_path, params: invalid_attributes
        end.not_to change(Family, :count)
      end

      it 'renders the new template with errors' do
        post families_path, params: invalid_attributes
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when the user is already at the family cap' do
      before do
        stub_const('UserFamily::MAX_FAMILIES', 1)
        create(:family_membership, :owner, user: user_without_family, family: create(:family))
      end

      it 'does not create a family' do
        expect do
          post families_path, params: { family: { name: 'Over Limit' } }
        end.not_to change(Family, :count)
      end

      it 'shows the family-limit message rather than an authorization error' do
        post families_path, params: { family: { name: 'Over Limit' } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(flash[:alert]).to match(/maximum number of families/i)
        expect(flash[:alert]).not_to include('not authorized')
      end
    end
  end

  describe 'GET /families/:id/edit' do
    it 'shows the edit form' do
      get edit_family_path(family)
      expect(response).to have_http_status(:ok)
    end

    context 'when user is not the owner' do
      before { membership.update!(role: :member) }

      it 'redirects due to authorization failure' do
        get edit_family_path(family)
        expect(response).to have_http_status(:see_other)
        expect(flash[:alert]).to include('not authorized')
      end
    end
  end

  describe 'PATCH /families/:id' do
    let(:new_attributes) { { family: { name: 'Updated Family Name' } } }

    context 'with valid attributes' do
      it 'updates the family' do
        patch family_path(family), params: new_attributes
        family.reload
        expect(family.name).to eq('Updated Family Name')
        expect(response).to redirect_to(family_path(family))
      end
    end

    context 'with invalid attributes' do
      let(:invalid_attributes) { { family: { name: '' } } }

      it 'does not update the family' do
        original_name = family.name
        patch family_path(family), params: invalid_attributes
        family.reload
        expect(family.name).to eq(original_name)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when user is not the owner' do
      before { membership.update!(role: :member) }

      it 'redirects due to authorization failure' do
        patch family_path(family), params: new_attributes
        expect(response).to have_http_status(:see_other)
        expect(flash[:alert]).to include('not authorized')
      end
    end
  end

  describe 'DELETE /families/:id' do
    context 'when family has only one member' do
      it 'deletes the family' do
        expect { delete family_path(family) }.to change(Family, :count).by(-1)
        expect(response).to redirect_to(families_path)
      end
    end

    context 'when family has multiple members' do
      before do
        create(:family_membership, user: other_user, family: family, role: :member)
      end

      it 'does not delete the family' do
        expect { delete family_path(family) }.not_to change(Family, :count)
        expect(response).to redirect_to(family_path(family))
        follow_redirect!
        expect(response.body).to include('Cannot delete family with members')
      end
    end

    context 'when user is not the owner' do
      before { membership.update!(role: :member) }

      it 'redirects due to authorization failure' do
        delete family_path(family)
        expect(response).to have_http_status(:see_other)
        expect(flash[:alert]).to include('not authorized')
      end
    end
  end

  describe 'authorization for outsiders' do
    let(:outsider) { create(:user) }

    before { sign_in outsider }

    it 'denies access to show when user is not in family' do
      get family_path(family)
      expect(response).to have_http_status(:not_found)
    end

    it 'denies access to edit when user is not in family' do
      get edit_family_path(family)
      expect(response).to have_http_status(:not_found)
    end

    it 'denies access to update when user is not in family' do
      patch family_path(family), params: { family: { name: 'Hacked' } }
      expect(response).to have_http_status(:not_found)
    end

    it 'denies access to destroy when user is not in family' do
      delete family_path(family)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'authentication required' do
    before { sign_out user }

    it 'redirects to login for index' do
      get families_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirects to login for show' do
      get family_path(family)
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirects to login for new' do
      get new_family_path

      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirects to login for create' do
      post families_path, params: { family: { name: 'Test' } }
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirects to login for edit' do
      get edit_family_path(family)
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirects to login for update' do
      patch family_path(family), params: { family: { name: 'Test' } }
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'redirects to login for destroy' do
      delete family_path(family)
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe 'GET /families (index)' do
    it 'lists all families the user belongs to' do
      user = create(:user)
      fam_a = create(:family, name: 'Ski Group')
      fam_b = create(:family, name: 'Poker Group')
      create(:family_membership, user: user, family: fam_a)
      create(:family_membership, user: user, family: fam_b)
      sign_in user

      get families_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Ski Group').and include('Poker Group')
    end
  end

  describe 'GET /families/:id (show)' do
    it 'returns 404 for a family the user is not in' do
      user = create(:user)
      other = create(:family)
      sign_in user

      get family_path(other)

      expect(response).to have_http_status(:not_found)
    end
  end
end
