# frozen_string_literal: true

require 'rails_helper'

# Regression: the family feature was gated on `self_hosted?`, so cloud users who
# paid for the Family plan received 403s (and 404s on routes) on every family
# path, while the upgrade CTA they were sent to was itself unreachable.
# Access must follow the subscription plan, not the hosting mode.
#
# Multi-family: `family` is a plural resource, so every family path takes the
# family as an argument. "Lapsed" is per-family (derived from that family's
# owner's plan) and the lapsed panel renders in place from FamiliesController#show
# — #show/#index are membership-scoped, not plan-gated, so a member of a
# lapsed-only family can still reach it. Mutation-success redirects land on
# the families index (family_home_path -> families_path); only the plan gate
# bounces to new_family_path.
RSpec.describe 'Family access on cloud', type: :request do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  describe 'a subscriber on the family plan' do
    let(:subscriber) { create(:user, plan: :family, skip_auto_trial: true) }

    it 'reaches the family creation form' do
      sign_in subscriber

      get new_family_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="family[name]"')
    end

    it 'creates a family' do
      sign_in subscriber

      expect { post families_path, params: { family: { name: 'The Burmakins' } } }
        .to change(Family, :count).by(1)

      expect(response).to redirect_to(family_path(Family.last))
    end

    it 'reaches the family page' do
      family = create(:family, creator: subscriber)
      create(:family_membership, user: subscriber, family: family, role: :owner)
      sign_in subscriber

      get family_path(family)

      expect(response).to have_http_status(:ok)
    end

    it 'reaches the family locations API' do
      family = create(:family, creator: subscriber)
      create(:family_membership, user: subscriber, family: family, role: :owner)

      get '/api/v1/families/locations', params: { api_key: subscriber.api_key }

      expect(response).to have_http_status(:ok)
    end

    it 'can delete the family after the plan lapses' do
      family = create(:family, creator: subscriber)
      create(:family_membership, user: subscriber, family: family, role: :owner)
      subscriber.update!(plan: :pro)
      sign_in subscriber

      expect { delete family_path(family) }.to change(Family, :count).by(-1)

      expect(response).to redirect_to(families_path)
    end
  end

  describe 'a user without the family plan' do
    let(:non_subscriber) { create(:user, plan: :pro, skip_auto_trial: true) }

    before { stub_const('MANAGER_URL', 'https://manager.example.com') }

    it 'is offered the upgrade instead of a 403' do
      sign_in non_subscriber

      get new_family_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Upgrade to Family')
      expect(response.body).not_to include('name="family[name]"')
    end

    it 'cannot create a family' do
      sign_in non_subscriber

      expect { post families_path, params: { family: { name: 'Freeloaders' } } }
        .not_to change(Family, :count)

      expect(response).to redirect_to(new_family_path)
    end

    it 'is refused by the family locations API' do
      get '/api/v1/families/locations', params: { api_key: non_subscriber.api_key }

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('family_plan_required')
    end

    it 'is not shown the family link in the navbar' do
      sign_in non_subscriber

      get stats_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(new_family_path)
    end
  end

  # The owner buys the plan; the people they invite do not. Requiring the plan
  # from members would make the plan itself useless.
  describe 'a member of someone else\'s family' do
    let(:owner) { create(:user, plan: :family, skip_auto_trial: true) }
    let(:family) { create(:family, creator: owner) }
    let(:member) { create(:user, plan: :pro, skip_auto_trial: true) }

    before do
      create(:family_membership, user: owner, family: family, role: :owner)
      stub_const('MANAGER_URL', 'https://manager.example.com')
    end

    it 'can accept an invitation without holding the plan' do
      invitation = create(:family_invitation, family: family, invited_by: owner, email: member.email)
      sign_in member

      expect { post accept_family_invitation_path(token: invitation.token) }
        .to change { member.reload.family_memberships.count }.by(1)

      expect(member.reload.families).to include(family)
    end

    it 'reaches the family page' do
      create(:family_membership, user: member, family: family)
      sign_in member

      get family_path(family)

      expect(response).to have_http_status(:ok)
    end

    it 'reaches the family locations API' do
      create(:family_membership, user: member, family: family)

      get '/api/v1/families/locations', params: { api_key: member.api_key }

      expect(response).to have_http_status(:ok)
    end

    it "revokes member access when the owner's paid period has expired" do
      membership = create(:family_membership, user: member, family: family)
      # A real lapse flips the plan column (see Api::V1::SubscriptionsController):
      # Family#lapsed? derives from the owner's plan, not their active_until.
      owner.update!(plan: :pro, active_until: 1.day.ago)
      sign_in member

      get family_path(family)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('no longer active')
      expect(response.body).to include(family_member_path(family, membership))
    end

    it "keeps member access while the owner's paid period still runs" do
      create(:family_membership, user: member, family: family)
      owner.update!(active_until: 2.weeks.from_now)
      sign_in member

      get family_path(family)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('no longer active')
    end

    it 'loses access when the owner stops paying' do
      membership = create(:family_membership, user: member, family: family)
      owner.update!(plan: :pro)
      sign_in member

      get family_path(family)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('no longer active')
      expect(response.body).to include(family_member_path(family, membership))
    end

    it 'shows the lapsed owner member removal and family deletion controls' do
      membership = create(:family_membership, user: member, family: family)
      owner.update!(plan: :pro)
      sign_in owner

      get family_path(family)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(family_member_path(family, membership))
      expect(response.body).to include('Delete Family')
    end

    it 'keeps the removal notice when a lapsed owner removes a member' do
      membership = create(:family_membership, user: member, family: family)
      owner.update!(plan: :pro)
      sign_in owner

      delete family_member_path(family, membership)

      expect(response).to redirect_to(family_path(family))
      expect(flash[:notice]).to include('removed')
    end

    it 'keeps the Family link in the navbar for members of a lapsed family' do
      create(:family_membership, user: member, family: family)
      owner.update!(plan: :pro)
      sign_in member

      get stats_path

      expect(response).to have_http_status(:ok)
      # family_home_path is a controller helper returning families_path.
      expect(response.body).to include(families_path)
    end

    it 'lets a member of a lapsed family turn off location sharing' do
      membership = create(:family_membership, user: member, family: family)
      membership.update_sharing!(true)
      owner.update!(plan: :pro)
      sign_in member

      patch family_location_sharing_path(family), params: { enabled: 'false' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(membership.reload.sharing_active?).to be(false)
    end

    it 'shows a lapsed owner the pending invitations page' do
      # invitations#index stays open (not plan-gated), so a lapsed owner still
      # reaches it — no global upgrade bounce.
      create(:family_invitation, family: family, invited_by: owner, email: 'someone@example.com')
      owner.update!(plan: :pro)
      sign_in owner

      get family_invitations_path(family)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('someone@example.com')
    end

    it 'lets a lapsed owner revoke a pending invitation' do
      invitation = create(:family_invitation, family: family, invited_by: owner, email: 'someone@example.com')
      owner.update!(plan: :pro)
      sign_in owner

      expect { delete family_invitation_path(family, invitation.token) }
        .to change { invitation.reload.status }.from('pending').to('cancelled')

      expect(response).to redirect_to(family_path(family))
      expect(flash[:notice]).to eq('Invitation cancelled')
    end

    it 'keeps the alert when a lapsed owner deletes a family that still has members' do
      create(:family_membership, user: member, family: family)
      owner.update!(plan: :pro)
      sign_in owner

      expect { delete family_path(family) }.not_to change(Family, :count)

      expect(response).to redirect_to(family_path(family))
      expect(flash[:alert]).to include('Cannot delete family with members')
    end

    it 'can leave the family after the owner stops paying' do
      membership = create(:family_membership, user: member, family: family)
      owner.update!(plan: :pro)
      sign_in member

      expect { delete family_member_path(family, membership) }
        .to change { member.reload.member_of?(family) }.from(true).to(false)

      expect(response).to redirect_to(families_path)
    end

    it 'warns an invitee on the invitation page when the family plan has lapsed' do
      invitation = create(:family_invitation, family: family, invited_by: owner, email: member.email)
      owner.update!(plan: :pro)
      sign_in member

      get family_invitation_path(family, invitation.token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('currently inactive')
      expect(response.body).not_to include(accept_family_invitation_path(token: invitation.token))
    end

    it 'keeps location requests blocked for a lapsed family' do
      create(:family_membership, user: member, family: family)
      owner.update!(plan: :pro)
      sign_in member

      post family_location_requests_path(family), params: { target_user_id: owner.id }

      expect(response).to redirect_to(new_family_path)
    end

    it 'cannot accept an invitation into a family whose plan has lapsed' do
      invitation = create(:family_invitation, family: family, invited_by: owner, email: member.email)
      owner.update!(plan: :pro)
      sign_in member

      expect { post accept_family_invitation_path(token: invitation.token) }
        .not_to change(Family::Membership, :count)

      expect(response).to redirect_to(root_path)
    end
  end

  describe 'non-HTML requests against the web guard' do
    # #show/#index are no longer plan-gated (membership-scoped so lapsed families
    # stay reachable), so the gate's JSON-403 / turbo-redirect branches are
    # exercised through #edit — which is still gated. A lapsed owner owns the
    # family (set_family would find it) but the gate runs first and refuses.
    let(:owner) { create(:user, plan: :family, skip_auto_trial: true) }
    let(:family) { create(:family, creator: owner) }

    before do
      create(:family_membership, user: owner, family: family, role: :owner)
      owner.update!(plan: :pro)
    end

    it 'returns JSON 403 for JSON requests' do
      sign_in owner

      get edit_family_path(family, format: :json)

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('family_plan_required')
    end

    it 'redirects turbo stream requests to the upgrade page' do
      sign_in owner

      get edit_family_path(family), headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to redirect_to(new_family_path)
      expect(response).to have_http_status(:see_other)
    end
  end

  describe 'self-hosted instances' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

    it 'keeps the family feature open to every plan' do
      user = create(:user, plan: :lite)
      sign_in user

      get new_family_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="family[name]"')
    end
  end
end
