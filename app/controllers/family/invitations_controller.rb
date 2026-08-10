# frozen_string_literal: true

class Family::InvitationsController < ApplicationController
  before_action :authenticate_user!, except: %i[show]
  # #index and #destroy stay open so a lapsed owner can still see and revoke
  # pending invitations; accepting them is blocked separately while lapsed.
  before_action :ensure_family_feature_available!, except: %i[show index destroy]
  before_action :set_family, except: %i[show]
  before_action :set_invitation_by_id_and_family, only: %i[destroy]

  def index
    authorize @family, :show?

    @pending_invitations = @family.family_invitations.active
  end

  def show
    token = params[:token] || params[:id]
    @invitation = Family::Invitation.find_by!(token: token)

    redirect_to root_path, alert: 'This invitation has expired.' and return if @invitation.expired?

    redirect_to root_path, alert: 'This invitation is no longer valid.' and return unless @invitation.pending?

    # Warns the invitee up front instead of letting them click Accept only to
    # be refused by the plan validation in Families::AcceptInvitation.
    @family_plan_active = DawarichSettings.family_feature_available_for?(@invitation.family.owner)
  end

  def create
    authorize @family, :invite?

    service = Families::Invite.new(
      family: @family,
      email: invitation_params[:email],
      invited_by: current_user
    )

    if service.call
      redirect_to family_path(@family), notice: 'Invitation sent successfully!'
    else
      redirect_to family_path(@family), alert: service.error_message || 'Failed to send invitation'
    end
  end

  def destroy
    authorize @family, :manage_invitations?

    begin
      if @invitation.update(status: :cancelled)
        redirect_to family_path(@family), notice: 'Invitation cancelled'
      else
        redirect_to family_path(@family), alert: 'Failed to cancel invitation. Please try again'
      end
    rescue StandardError => e
      Rails.logger.error "Error cancelling family invitation: #{e.message}"
      redirect_to family_path(@family), alert: 'An unexpected error occurred while cancelling the invitation'
    end
  end

  private

  def set_family
    @family = current_user.families.find(params[:family_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to families_path, alert: 'Family not found'
  end

  def set_invitation_by_id_and_family
    # For authenticated nested routes: /families/:family_id/invitations/:id
    # The :id param contains the token value
    @family = current_user.families.find(params[:family_id])
    @invitation = @family.family_invitations.find_by!(token: params[:id])
  end

  def invitation_params
    params.require(:family_invitation).permit(:email)
  end
end
