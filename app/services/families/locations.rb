# frozen_string_literal: true

class Families::Locations
  attr_reader :user

  MAX_POINTS_PER_MEMBER = 5000

  def initialize(user)
    @user = user
  end

  def call
    return [] unless available?

    sharing_groups do |family, memberships|
      members = memberships.filter_map { |m| latest_location(m) }
      next if members.empty?

      { family_id: family.id, family_name: family.name, members: members }
    end
  end

  def history(start_at:, end_at:)
    return [] unless available?

    sharing_groups do |family, memberships|
      members = memberships.filter_map { |m| history_for(m, start_at: start_at, end_at: end_at) }
      next if members.empty?

      { family_id: family.id, family_name: family.name, members: members }
    end
  end

  private

  def available?
    DawarichSettings.family_feature_available_for?(user) && user.in_family?
  end

  # Yields [family, sharing_memberships] for each of the user's families that
  # has at least one actively-sharing member. Compacts nil block results.
  def sharing_groups
    user.families.includes(family_memberships: :user).filter_map do |family|
      memberships = family.family_memberships.select(&:sharing_active?)
      next if memberships.empty?

      yield(family, memberships)
    end
  end

  def latest_location(membership)
    point = membership.user.points.complete.order(timestamp: :desc).first
    return nil unless point

    {
      user_id: membership.user_id,
      email: membership.user.email,
      email_initial: membership.user.email.first.upcase,
      family_id: membership.family_id,
      family_name: membership.family.name,
      latitude: point.lat,
      longitude: point.lon,
      timestamp: point.timestamp,
      updated_at: Time.zone.at(point.timestamp),
      battery: point.battery,
      battery_status: point.battery_status
    }
  end

  def history_for(membership, start_at:, end_at:)
    points = membership.history_points(start_at: start_at, end_at: end_at)
    total = points.count
    return nil if total.zero?

    sampled = sample(points, total)

    {
      user_id: membership.user_id,
      email: membership.user.email,
      email_initial: membership.user.email.first.upcase,
      family_id: membership.family_id,
      family_name: membership.family.name,
      sharing_since: membership.sharing_started_at&.iso8601,
      # Read coordinates from the PostGIS lonlat geometry.
      # Order stays [lat, lon, ts] for the frontend.
      points: sampled.pluck(
        Arel.sql('ST_Y(lonlat::geometry)'),
        Arel.sql('ST_X(lonlat::geometry)'),
        :timestamp
      )
    }
  end

  def sample(points, total)
    return points unless total > MAX_POINTS_PER_MEMBER

    nth = (total.to_f / MAX_POINTS_PER_MEMBER).ceil
    numbered = points.select('id, ROW_NUMBER() OVER (ORDER BY timestamp ASC) - 1 AS row_num').to_sql
    points.where("id IN (SELECT id FROM (#{numbered}) numbered WHERE mod(row_num, ?) = 0)", nth)
  end
end
