# frozen_string_literal: true

class Family::Membership < ApplicationRecord
  self.table_name = 'family_memberships'

  belongs_to :family
  belongs_to :user

  validates :user_id, presence: true
  validates :user_id, uniqueness: { scope: :family_id, message: 'is already a member of this family' }
  validates :role, presence: true

  # Enforce both caps at the model level so direct creates
  # (e.g. console) can't bypass the service-only checks.
  validate :within_user_family_limit, on: :create
  validate :within_family_member_limit, on: :create

  enum :role, { owner: 0, member: 1 }

  VALID_HISTORY_WINDOWS = %w[24h 7d 30d all].freeze

  after_create :clear_family_cache
  after_update :clear_family_cache
  after_destroy :clear_family_cache
  after_destroy :cleanup_on_departure

  def sharing_active?
    return false unless sharing_enabled?

    sharing_expires_at.blank? || sharing_expires_at.future?
  end

  def update_sharing!(enabled, duration: nil, share_history: nil, history_window: nil)
    if enabled
      self.sharing_enabled = true
      self.sharing_started_at ||= Time.current
      self.share_history = share_history unless share_history.nil?
      self.history_window = validate_history_window(history_window) if history_window.present?

      apply_duration(duration) if duration.present?
    else
      self.sharing_enabled = false
      self.sharing_expires_at = nil
    end

    save!
  end

  def sharing_duration_label
    sharing_duration.presence || 'permanent'
  end

  def history_points(start_at:, end_at:)
    return Point.none unless sharing_active?
    return Point.none unless share_history?
    return Point.none unless sharing_started_at

    window_start = case history_window
                   when '7d' then 7.days.ago
                   when '30d' then 30.days.ago
                   when 'all' then 1.year.ago
                   else 24.hours.ago
                   end

    effective_start = [start_at, sharing_started_at, window_start].max
    return Point.none if effective_start >= end_at

    user.scoped_points
        .where('timestamp >= ? AND timestamp <= ?', effective_start.to_i, end_at.to_i)
        .order(timestamp: :asc)
  end

  def latest_location
    return nil unless sharing_active?

    latest_point = user.scoped_points.select(:lonlat, :timestamp).order(timestamp: :desc).limit(1).first
    return nil unless latest_point

    {
      user_id: user.id,
      email: user.email,
      latitude: latest_point.lat,
      longitude: latest_point.lon,
      timestamp: latest_point.timestamp,
      updated_at: Time.zone.at(latest_point.timestamp)
    }
  end

  private

  # MAX_FAMILIES applies to all instances including self-hosted
  def within_user_family_limit
    return if user.nil? || user.family_memberships.count < UserFamily::MAX_FAMILIES

    errors.add(:base, "You have reached the maximum number of families (#{UserFamily::MAX_FAMILIES})")
  end

  # MAX_MEMBERS bypasses self-hosted (mirrors Family#full?, counting members not pending invites).
  def within_family_member_limit
    return if DawarichSettings.self_hosted? || family.nil?
    return if family.family_memberships.count < Family::MAX_MEMBERS

    errors.add(:base, 'This family has reached the maximum number of members.')
  end

  def apply_duration(duration)
    self.sharing_duration = duration
    self.sharing_expires_at = case duration
                              when '1h' then 1.hour.from_now
                              when '6h' then 6.hours.from_now
                              when '12h' then 12.hours.from_now
                              when '24h' then 24.hours.from_now
                              when 'permanent' then nil
                              else duration.to_i.positive? ? duration.to_i.hours.from_now : nil
                              end
  end

  def validate_history_window(window)
    VALID_HISTORY_WINDOWS.include?(window) ? window : '24h'
  end

  def clear_family_cache
    family.clear_member_cache!
  end

  def cleanup_on_departure
    # Expire pending location requests for this family involving the departing user
    Family::LocationRequest
      .pending
      .where(family_id: family_id)
      .where('requester_id = ? OR target_user_id = ?', user_id, user_id)
      .update_all(status: Family::LocationRequest.statuses[:expired], updated_at: Time.current)
  rescue StandardError => e
    ExceptionReporter.call(e, "Error cleaning up on family departure: #{e.message}")
  end
end
