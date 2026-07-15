# frozen_string_literal: true

class BackfillMembershipSharingFromUserSettings < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    User.where.not(settings: nil).find_each do |user|
      sharing = user.settings.dig('family', 'location_sharing')
      next unless sharing.is_a?(Hash) && sharing['enabled'] == true

      membership = Family::Membership.find_by(user_id: user.id)
      next unless membership

      membership.update_columns(
        sharing_enabled: true,
        sharing_started_at: parse_time(sharing['started_at']),
        sharing_expires_at: parse_time(sharing['expires_at']),
        share_history: sharing['share_history'] == true,
        history_window: sharing['history_window'].presence || '7d',
        sharing_duration: sharing['duration']
      )
    end
  end

  def down
    Family::Membership.update_all(
      sharing_enabled: false, sharing_started_at: nil, sharing_expires_at: nil,
      share_history: false, history_window: '7d', sharing_duration: nil
    )
  end

  private

  def parse_time(value)
    value.present? ? Time.zone.parse(value) : nil
  rescue ArgumentError
    nil
  end
end
