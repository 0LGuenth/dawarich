# frozen_string_literal: true

# A user whose Membership survives but whose Entitlement has gone. The payload
# carries only what is needed to explain the state — the family's name and
# whether this user is the Family owner, so the client can offer renewal to the
# one person who can act on it. Member identities and locations are deliberately
# absent: a lapsed user has no entitlement to them.
class Api::LapsedFamilySerializer
  def initialize(user)
    @user = user
  end

  def call
    {
      lapsed: true,
      family: { name: active_family&.name },
      me: {
        user_id: user.id,
        owner: active_membership&.owner? || false
      }
    }
  end

  private

  attr_reader :user

  def active_family
    @active_family ||= user.family_memberships.order(created_at: :desc).first&.family
  end

  def active_membership
    @active_membership ||= user.membership_for(active_family)
  end
end
