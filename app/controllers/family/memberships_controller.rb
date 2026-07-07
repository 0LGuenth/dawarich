# frozen_string_literal: true

class Family::MembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_family_feature_enabled!
  before_action :set_family, except: %i[create]
  before_action :set_membership, only: %i[destroy]
  before_action :set_invitation, only: %i[create]

  def create
    authorize @invitation, policy_class: Family::MembershipPolicy

    service = Families::AcceptInvitation.new(
      invitation: @invitation,
      user: current_user
    )

    if service.call
      redirect_to family_path(@invitation.family), notice: 'Welcome to the family!'
    else
      redirect_to root_path, alert: service.error_message || 'Unable to accept invitation'
    end
  rescue Pundit::NotAuthorizedError
    alert = if @invitation.expired?
              'This invitation is no longer valid or has expired'
            elsif !@invitation.pending?
              'This invitation has already been processed'
            elsif @invitation.email != current_user.email
              'This invitation is not for your email address'
            else
              'You are not authorized to accept this invitation'
            end

    redirect_to root_path, alert: alert
  rescue StandardError => e
    Rails.logger.error "Error accepting family invitation: #{e.message}"

    redirect_to root_path, alert: 'An unexpected error occurred. Please try again later'
  end

  def destroy
    authorize @membership

    member_user = @membership.user
    service = Families::Memberships::Destroy.new(user: current_user, family: @family, member_to_remove: member_user)

    if service.call
      if member_user == current_user
        redirect_to families_path, notice: 'You have left the family'
      else
        redirect_to family_path(@family), notice: "#{member_user.email} has been removed from the family"
      end
    else
      redirect_to family_path(@family), alert: service.error_message || 'Failed to remove member'
    end
  end

  private

  def set_family
    @family = current_user.families.find(params[:family_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to families_path, alert: 'Family not found'
  end

  def set_membership
    @membership = @family.family_memberships.find(params[:id])
  end

  def set_invitation
    @invitation = Family::Invitation.find_by!(token: params[:token])
  end
end
