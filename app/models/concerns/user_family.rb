# frozen_string_literal: true

module UserFamily
  extend ActiveSupport::Concern

  # Ceiling on live-location broadcast fan-out.
  MAX_FAMILIES = (ENV['MAX_FAMILIES_PER_USER'].presence || 10).to_i

  included do
    has_many :family_memberships, dependent: :destroy, class_name: 'Family::Membership'
    has_many :families, through: :family_memberships
    has_many :created_families, class_name: 'Family', foreign_key: 'creator_id',
             inverse_of: :creator, dependent: :destroy
    has_many :sent_family_invitations, class_name: 'Family::Invitation', foreign_key: 'invited_by_id',
             inverse_of: :invited_by, dependent: :destroy
    has_many :sent_location_requests, class_name: 'Family::LocationRequest', foreign_key: 'requester_id',
             inverse_of: :requester, dependent: :destroy
    has_many :received_location_requests, class_name: 'Family::LocationRequest', foreign_key: 'target_user_id',
             inverse_of: :target_user, dependent: :destroy
  end

  DEFAULT_HISTORY_WINDOW = '7d'
  VALID_HISTORY_WINDOWS = %w[24h 7d 30d all].freeze

  def in_family?
    family_memberships.exists?
  end

  def member_of?(family)
    return false unless family

    family_memberships.exists?(family_id: family.id)
  end

  def membership_for(family)
    return nil unless family

    family_memberships.find_by(family_id: family.id)
  end

  def family_map_sharing_active?
    return false unless in_family?

    Family::Membership.where(family_id: families.select(:id)).any?(&:sharing_active?)
  end

  def owner_of?(family)
    return false unless family

    family_memberships.exists?(family_id: family.id, role: Family::Membership.roles[:owner])
  end

  # Prevent account deletion if the user owns a family with other members.
  def can_delete_account?
    owned_family_ids = family_memberships.where(role: Family::Membership.roles[:owner]).pluck(:family_id)
    Family.where(id: owned_family_ids).none? { |family| family.members.count > 1 }
  end

  def can_create_more_families?
    family_memberships.count < MAX_FAMILIES
  end

  # Fallback helpers for single-family mobile consumers and upstream compatibility
  def family
    families.order(created_at: :desc).first
  end

  def family_membership
    family_memberships.order(created_at: :desc).first
  end

  def created_family
    created_families.order(created_at: :desc).first
  end

  def family_owner?
    family_memberships.exists?(role: Family::Membership.roles[:owner])
  end

  def family_sharing_enabled?
    family_memberships.any?(&:sharing_active?)
  end

  def update_family_location_sharing!(enabled, duration: nil, share_history: nil, history_window: nil,
                                      history_before_sharing: nil)
    return false unless in_family?

    current_settings = settings || {}
    current_settings['family'] ||= {}

    caster = ActiveModel::Type::Boolean.new
    is_enabled = caster.cast(enabled)

    if is_enabled
      existing_started_at = current_settings.dig('family', 'location_sharing', 'started_at')
      existing_share_history = current_settings.dig('family', 'location_sharing', 'share_history')
      existing_history_window = current_settings.dig('family', 'location_sharing', 'history_window')
      existing_duration = current_settings.dig('family', 'location_sharing', 'duration')
      existing_expires_at = current_settings.dig('family', 'location_sharing', 'expires_at')

      sharing_config = { 'enabled' => true }
      sharing_config['started_at'] = existing_started_at || Time.current.iso8601
      cast_share_history = share_history.nil? ? (existing_share_history || false) : caster.cast(share_history)
      sharing_config['share_history'] = cast_share_history
      validated_window = validate_history_window(history_window || existing_history_window)
      sharing_config['history_window'] = validated_window
      # Only explicit confirmation may grant access to earlier points.
      previous_consent = current_settings.dig('family', 'location_sharing', 'history_before_sharing') == true
      consent = history_before_sharing.nil? ? previous_consent : caster.cast(history_before_sharing)
      sharing_config['history_before_sharing'] = sharing_config['share_history'] && consent

      if duration.present?
        expiration_time = sharing_expiration_time(duration)

        sharing_config['expires_at'] = expiration_time.iso8601 if expiration_time
        sharing_config['duration'] = duration
      elsif existing_duration.present?
        sharing_config['duration'] = existing_duration
        carried_expiry = carried_sharing_expiry(existing_duration, existing_expires_at)
        sharing_config['expires_at'] = carried_expiry.iso8601 if carried_expiry
      end

      current_settings['family']['location_sharing'] = sharing_config
    else
      current_settings['family']['location_sharing'] = { 'enabled' => false }
    end

    update!(settings: current_settings)

    family_memberships.each do |membership|
      membership.update_sharing!(
        is_enabled,
        duration: duration,
        share_history: share_history.nil? ? nil : caster.cast(share_history),
        history_window: history_window
      )
    end
  end

  def family_sharing_expires_at
    family_membership&.sharing_expires_at
  end

  def family_sharing_duration
    family_membership&.sharing_duration_label
  end

  def family_sharing_started_at
    family_membership&.sharing_started_at
  end

  def family_share_history?
    family_memberships.any?(&:share_history?)
  end

  def family_history_window
    family_membership&.history_window
  end

  def family_history_before_sharing?
    settings.dig('family', 'location_sharing', 'history_before_sharing') == true
  end

  def family_history_points(start_at:, end_at:)
    return Point.none unless family_sharing_enabled?
    return Point.none unless family_share_history?

    family_membership&.history_points(start_at: start_at, end_at: end_at) || Point.none
  end

  def latest_location_for_family
    return nil unless family_sharing_enabled?

    family_membership&.latest_location
  end

  private

  def sharing_expiration_time(duration)
    case duration
    when '1h' then 1.hour.from_now
    when '6h' then 6.hours.from_now
    when '12h' then 12.hours.from_now
    when '24h' then 24.hours.from_now
    when 'permanent' then nil
    else duration.to_i.hours.from_now if duration.to_i.positive?
    end
  end

  # Re-enabling without explicit duration preserves active or re-arms lapsed expiry.
  def carried_sharing_expiry(existing_duration, existing_expires_at)
    return nil if existing_expires_at.blank?

    existing_expiry = begin
      Time.zone.parse(existing_expires_at)
    rescue ArgumentError
      nil
    end
    return existing_expiry if existing_expiry&.future?

    sharing_expiration_time(existing_duration)
  end

  def validate_history_window(window)
    VALID_HISTORY_WINDOWS.include?(window) ? window : DEFAULT_HISTORY_WINDOW
  end
end
