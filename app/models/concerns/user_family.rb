# frozen_string_literal: true

module UserFamily
  extend ActiveSupport::Concern

  # Total families (created + joined) a single user may belong to.
  # Applies to all instances including self-hosted, this is the ceiling on
  # live-location broadcast fan-out.
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

  def owner_of?(family)
    return false unless family

    family_memberships.exists?(family_id: family.id, role: Family::Membership.roles[:owner])
  end

  # NOTE: this rule ("cannot delete while owning a family with other members")
  # is duplicated in Users::Destroy, which re-checks it inside the
  # deletion transaction to stay TOCTOU-safe. Keep the two in sync.
  # Ownership is by membership role (consistent with owner_of?), not creator_id.
  def can_delete_account?
    owned_family_ids = family_memberships.where(role: Family::Membership.roles[:owner]).pluck(:family_id)
    Family.where(id: owned_family_ids).none? { |family| family.members.count > 1 }
  end

  # Named `can_create_more_families?` (not `can_create_family?`) to avoid
  # colliding with the pre-existing private Families::Create#can_create_family?,
  # which gates cloud feature access.
  def can_create_more_families?
    family_memberships.count < MAX_FAMILIES
  end
end
