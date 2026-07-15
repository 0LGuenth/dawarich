# frozen_string_literal: true

class AddSharingToFamilyMemberships < ActiveRecord::Migration[8.0]
  def change
    add_column :family_memberships, :sharing_enabled, :boolean, null: false, default: false
    add_column :family_memberships, :sharing_expires_at, :datetime
    add_column :family_memberships, :sharing_started_at, :datetime
    add_column :family_memberships, :share_history, :boolean, null: false, default: false
    add_column :family_memberships, :history_window, :string, null: false, default: '7d'
    add_column :family_memberships, :sharing_duration, :string
  end
end
