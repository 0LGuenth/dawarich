# frozen_string_literal: true

class Family::LocationRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_family_feature_available!
  before_action :set_family
  before_action :set_request, only: %i[show accept decline]
  before_action :authorize_target_user!, only: %i[show accept decline]

  def create
    target = @family.members.find_by(id: params[:target_user_id])

    unless target
      redirect_to family_path(@family), alert: 'User not found in your family'
      return
    end

    result = Families::CreateLocationRequest.new(requester: current_user, target_user: target, family: @family).call

    if result.success?
      redirect_to family_path(@family), notice: 'Location request sent successfully'
    else
      redirect_to family_path(@family), alert: result.payload[:message]
    end
  end

  def show
    # View rendered by template
  end

  def accept
    unless actionable?
      redirect_to family_path(@family), alert: 'This request has expired or already been responded to'
      return
    end

    duration = params[:duration] || @request.suggested_duration
    ActiveRecord::Base.transaction do
      current_user.membership_for(@family).update_sharing!(true, duration: duration)
      @request.update!(status: :accepted, responded_at: Time.current)
    end

    redirect_to family_path(@family), notice: 'Location sharing enabled'
  end

  def decline
    unless actionable?
      redirect_to family_path(@family), alert: 'This request has expired or already been responded to'
      return
    end

    @request.update!(status: :declined, responded_at: Time.current)

    redirect_to family_path(@family), notice: 'Location request declined'
  end

  private

  def set_family
    @family = current_user.families.find(params[:family_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to families_path, alert: 'Family not found'
  end

  def set_request
    @request = @family.location_requests.find(params[:id])
  end

  def authorize_target_user!
    return if @request.target_user == current_user

    redirect_to family_path(@family), alert: 'You are not authorized to view this request'
  end

  def actionable?
    @request.pending? && @request.expires_at > Time.current
  end
end
