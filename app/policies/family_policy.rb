# frozen_string_literal: true

class FamilyPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    user.member_of?(record)
  end

  def create?
    # NOTE: the per-user family cap is is enforced in Families::Create where it
    # results in a proper error message instead of "not authorized"
    return true if DawarichSettings.self_hosted?

    # Add cloud subscription checks here when implemented
    true
  end

  def update?
    user.owner_of?(record)
  end

  def destroy?
    user.owner_of?(record)
  end

  def leave?
    user.member_of?(record) && !family_owner_with_members?
  end

  def invite?
    user.owner_of?(record)
  end

  def manage_invitations?
    user.owner_of?(record)
  end

  def update_location_sharing?
    user.member_of?(record)
  end

  private

  def family_owner_with_members?
    user.owner_of?(record) && record.members.count > 1
  end
end
