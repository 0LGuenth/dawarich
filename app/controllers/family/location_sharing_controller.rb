# frozen_string_literal: true

class Family::LocationSharingController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!
  # No plan gate: turning sharing off is a privacy action and must stay
  # reachable after the family's plan lapses. Readers are gated on their side.
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
          turbo_stream.replace(
            'family-getting-started-slot',
            partial: 'families/getting_started',
            locals: {
              family: @family,
              user: current_user,
              pending_invitations: @family.active_invitations
            }
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
        render turbo_stream: stream_flash(
          :error,
          I18n.t('controllers.family.location_sharing.user_is_not_part_of_a_family')
        ), status: :not_found
      end
      format.json do
        render json: { error: I18n.t('controllers.family.location_sharing.user_is_not_part_of_a_family') },
               status: :not_found
      end
    end
  end
end
