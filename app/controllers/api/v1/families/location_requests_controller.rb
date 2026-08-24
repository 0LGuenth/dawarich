# frozen_string_literal: true

class Api::V1::Families::LocationRequestsController < Api::V1::Families::BaseController
  def create
    target = family_members.find_by(id: params[:target_user_id])

    unless target
      return render json: { error: I18n.t('controllers.family.location_requests.user_not_found_in_your_family') },
                    status: :not_found
    end

    family = family_for_request(target)

    unless family
      return render json: { error: I18n.t('controllers.family.location_requests.user_not_found_in_your_family') },
                    status: :not_found
    end

    result = Families::CreateLocationRequest.new(requester: current_api_user, target_user: target, family: family).call

    if result.success?
      request_record = result.payload[:request]
      render json: {
        request: {
          id: request_record.id,
          target_user_id: request_record.target_user_id,
          expires_at: request_record.expires_at.iso8601
        }
      }, status: :created
    else
      render json: result.payload, status: result.status
    end
  end

  def accept
    respond_to_request(:accept)
  end

  def decline
    respond_to_request(:decline)
  end

  private

  def family_members
    User.joins(:family_memberships).where(family_memberships: { family_id: current_api_user.family_ids })
  end

  # Prefer the active family when both are members, else the first shared one.
  def family_for_request(target)
    return active_family if target.member_of?(active_family)

    current_api_user.families.find { |family| target.member_of?(family) }
  end

  def respond_to_request(decision)
    request_record = Family::LocationRequest.where(family_id: current_api_user.family_ids).find_by(id: params[:id])

    unless request_record
      return render json: { error: I18n.t('controllers.api.v1.families.location_requests.not_found') },
                    status: :not_found
    end

    result = Families::RespondToLocationRequest.new(
      request: request_record,
      responder: current_api_user,
      decision: decision,
      duration: params[:duration]
    ).call

    render json: result.payload, status: result.status
  end
end
