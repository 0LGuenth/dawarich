# frozen_string_literal: true

class Families::UpdateLocationSharing
  Result = Struct.new(:success?, :payload, :status, keyword_init: true)

  def initialize(enabled:, membership: nil, user: nil, duration: nil, share_history: nil, history_window: nil,
                 history_before_sharing: nil)
    @membership = membership || user&.family_membership
    @user = user || membership&.user
    @enabled_param = enabled
    @duration_param = duration
    @share_history_param = share_history
    @history_window_param = history_window
    @history_before_sharing_param = history_before_sharing
    @boolean_caster = ActiveModel::Type::Boolean.new
  end

  def call
    unless membership
      return failure_result(
        I18n.t('services.families.update_location_sharing.not_in_family', default: 'Not in a family'),
        :not_found
      )
    end

    membership.update_sharing!(
      enabled?,
      duration: duration_param,
      share_history: share_history_param.nil? ? nil : boolean_caster.cast(share_history_param),
      history_window: history_window_param
    )
    success_result
  rescue StandardError => e
    ExceptionReporter.call(e, "Error in Families::UpdateLocationSharing: #{e.message}")

    failure_result(I18n.t('services.families.update_location_sharing.unexpected_error'), :internal_server_error)
  end

  private

  attr_reader :membership, :user, :enabled_param, :duration_param, :share_history_param, :history_window_param,
              :history_before_sharing_param, :boolean_caster

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
      payload[:expires_at_formatted] = I18n.l(membership.sharing_expires_at, format: :short_with_time)
    end

    Result.new(success?: true, payload: payload, status: :ok)
  end

  def failure_result(message, status)
    Result.new(success?: false, payload: { success: false, message: message }, status: status)
  end

  def build_sharing_message
    return I18n.t('services.families.update_location_sharing.disabled') unless enabled?

    case duration_param
    when '1h' then I18n.t('services.families.update_location_sharing.enabled_for_hours', count: 1)
    when '6h' then I18n.t('services.families.update_location_sharing.enabled_for_hours', count: 6)
    when '12h' then I18n.t('services.families.update_location_sharing.enabled_for_hours', count: 12)
    when '24h' then I18n.t('services.families.update_location_sharing.enabled_for_hours', count: 24)
    when 'permanent', nil then I18n.t('services.families.update_location_sharing.enabled')
    else
      if duration_param.to_i.positive?
        I18n.t('services.families.update_location_sharing.enabled_for_hours', count: duration_param.to_i)
      else
        I18n.t('services.families.update_location_sharing.enabled')
      end
    end
  end
end
