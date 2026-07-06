# frozen_string_literal: true

class Families::UpdateLocationSharing
  Result = Struct.new(:success?, :payload, :status, keyword_init: true)

  def initialize(membership:, enabled:, duration:, share_history: nil, history_window: nil)
    @membership = membership
    @enabled_param = enabled
    @duration_param = duration
    @share_history_param = share_history
    @history_window_param = history_window
    @boolean_caster = ActiveModel::Type::Boolean.new
  end

  def call
    membership.update_sharing!(
      enabled?,
      duration: duration_param,
      share_history: share_history_param.nil? ? nil : boolean_caster.cast(share_history_param),
      history_window: history_window_param
    )
    success_result
  rescue StandardError => e
    ExceptionReporter.call(e, "Error in Families::UpdateLocationSharing: #{e.message}")

    failure_result('An error occurred while updating location sharing', :internal_server_error)
  end

  private

  attr_reader :membership, :enabled_param, :duration_param, :share_history_param, :history_window_param, :boolean_caster

  def enabled?
    @enabled ||= boolean_caster.cast(enabled_param)
  end

  def success_result
    payload = {
      success: true,
      enabled: enabled?,
      duration: membership.sharing_duration_label,
      message: build_sharing_message
    }

    if enabled? && membership.sharing_expires_at.present?
      payload[:expires_at] = membership.sharing_expires_at.iso8601
      payload[:expires_at_formatted] = membership.sharing_expires_at.strftime('%b %d at %I:%M %p')
    end

    Result.new(success?: true, payload: payload, status: :ok)
  end

  def failure_result(message, status)
    Result.new(success?: false, payload: { success: false, message: message }, status: status)
  end

  def build_sharing_message
    return 'Location sharing disabled' unless enabled?

    case duration_param
    when '1h' then 'Location sharing enabled for 1 hour'
    when '6h' then 'Location sharing enabled for 6 hours'
    when '12h' then 'Location sharing enabled for 12 hours'
    when '24h' then 'Location sharing enabled for 24 hours'
    when 'permanent', nil then 'Location sharing enabled'
    else
      if duration_param.to_i.positive?
        "Location sharing enabled for #{duration_param.to_i} hours"
      else
        'Location sharing enabled'
      end
    end
  end
end
