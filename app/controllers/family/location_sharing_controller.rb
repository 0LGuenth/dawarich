# frozen_string_literal: true

class Family::LocationSharingController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!
  before_action :ensure_family_feature_enabled!
  before_action :set_family
  before_action :set_membership

  def update
    result = Families::UpdateLocationSharing.new(
      membership: @membership,
      enabled: params[:enabled],
      duration: params[:duration],
      share_history: params[:share_history],
      history_window: params[:history_window]
    ).call

    respond_to do |format|
      format.turbo_stream do
        @membership.reload
        streams = [
          turbo_stream.replace(
            "location-sharing-#{current_user.id}",
            partial: 'families/location_sharing_toggle',
            locals: { member: current_user, membership: @membership, family: @family }
          ),
          turbo_stream.replace(
            'family-navbar-indicator',
            partial: 'families/navbar_indicator',
            locals: { user: current_user }
          ),
          stream_flash(result.success? ? :success : :error, result.payload[:message])
        ]
        render turbo_stream: streams
      end
      format.json { render json: result.payload, status: result.status }
    end
  end

  private

  def set_family
    @family = current_user.families.find(params[:family_id])
  rescue ActiveRecord::RecordNotFound
    render_not_in_family
  end

  def set_membership
    @membership = current_user.membership_for(@family) if @family
    render_not_in_family unless @membership
  end

  def render_not_in_family
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: stream_flash(:error, 'User is not part of this family'), status: :not_found
      end
      format.json { render json: { error: 'User is not part of this family' }, status: :not_found }
    end
  end
end
