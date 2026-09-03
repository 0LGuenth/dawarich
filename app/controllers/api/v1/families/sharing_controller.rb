# frozen_string_literal: true

class Api::V1::Families::SharingController < Api::V1::Families::BaseController
  def update
    params.require(:enabled)

    memberships = target_memberships
    return render_not_in_family if memberships.empty?

    results = memberships.map do |membership|
      Families::UpdateLocationSharing.new(
        membership: membership,
        enabled: params[:enabled],
        duration: params[:duration],
        share_history: params[:share_history],
        history_window: params[:history_window]
      ).call
    end

    if results.all?(&:success?)
      render json: results.first.payload, status: results.first.status
    else
      failure = results.find { |r| !r.success? }
      render json: failure.payload, status: failure.status
    end
  rescue ActionController::ParameterMissing => e
    error = I18n.t('controllers.api.v1.families.sharing.missing_required_parameter_param', parameter: e.param)
    render json: { error: error }, status: :bad_request
  end

  private

  # Updates all memberships for single-family mobile apps unless scoped.
  def target_memberships
    if params[:family_id].present?
      current_api_user.family_memberships.where(family_id: params[:family_id])
    else
      current_api_user.family_memberships.order(created_at: :desc)
    end
  end
end
