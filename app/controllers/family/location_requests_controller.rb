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
      redirect_to family_path(@family),
                  alert: I18n.t('controllers.family.location_requests.user_not_found_in_your_family')
      return
    end

    result = Families::CreateLocationRequest.new(requester: current_user, target_user: target, family: @family).call

    if result.success?
      redirect_to family_path(@family),
                  notice: I18n.t('controllers.family.location_requests.location_request_sent_successfully')
    else
      redirect_to family_path(@family), alert: result.payload[:message]
    end
  end

  def show
    # View rendered by template
  end

  def accept
    unless actionable?
      alert = I18n.t('controllers.family.location_requests.this_request_has_expired_or_already_been_responded_to')
      redirect_to family_path(@family),
                  alert: alert
      return
    end

    duration = params[:duration] || @request.suggested_duration
    ActiveRecord::Base.transaction do
      current_user.membership_for(@family).update_sharing!(true, duration: duration)
      @request.update!(status: :accepted, responded_at: Time.current)
    end

    redirect_to family_path(@family), notice: I18n.t('controllers.family.location_requests.location_sharing_enabled')
  end

  def decline
    unless actionable?
      alert = I18n.t('controllers.family.location_requests.this_request_has_expired_or_already_been_responded_to')
      redirect_to family_path(@family),
                  alert: alert
      return
    end

    @request.update!(status: :declined, responded_at: Time.current)

    redirect_to family_path(@family), notice: I18n.t('controllers.family.location_requests.location_request_declined')
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

    redirect_to family_path(@family),
                alert: I18n.t('controllers.family.location_requests.you_are_not_authorized_to_view_this_request')
  end

  def ensure_user_in_family!
    return if current_user&.in_family?

    redirect_to root_path, alert: I18n.t('controllers.family.location_requests.you_must_be_part_of_a_family')
  end

  def actionable?
    @request.pending? && @request.expires_at > Time.current
  end
end
