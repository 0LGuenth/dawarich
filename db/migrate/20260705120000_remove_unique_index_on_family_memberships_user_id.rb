# frozen_string_literal: true

class RemoveUniqueIndexOnFamilyMembershipsUserId < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    remove_index :family_memberships, column: :user_id, unique: true,
                 name: 'index_family_memberships_on_user_id', algorithm: :concurrently, if_exists: true
    add_index :family_memberships, :user_id,
              name: 'index_family_memberships_on_user_id', algorithm: :concurrently, if_not_exists: true
    # Prevent duplicate rows for the same (user, family) pair.
    add_index :family_memberships, %i[user_id family_id], unique: true,
              name: 'index_family_memberships_on_user_and_family',
              algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :family_memberships, column: %i[user_id family_id], unique: true,
                 name: 'index_family_memberships_on_user_and_family', algorithm: :concurrently, if_exists: true
    remove_index :family_memberships, column: :user_id,
                 name: 'index_family_memberships_on_user_id', algorithm: :concurrently, if_exists: true
    add_index :family_memberships, :user_id, unique: true,
              name: 'index_family_memberships_on_user_id', algorithm: :concurrently, if_not_exists: true
  end
end
