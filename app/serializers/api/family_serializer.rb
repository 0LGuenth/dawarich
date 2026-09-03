# frozen_string_literal: true

class Api::FamilySerializer
  def initialize(user)
    @user = user
  end

  # Keeps the upstream single-family shape; members and requests from all of
  # the user's families are intermixed and tagged with their family.
  def call
    {
      lapsed: false,
      family: { name: active_family.name },
      me: me_payload,
      members: members_payload,
      location_requests: {
        incoming: user.received_location_requests.active
                      .includes(:requester, :family)
                      .map { |request| incoming_request(request) },
        outgoing: user.sent_location_requests.active
                      .includes(:family)
                      .map { |request| outgoing_request(request) }
      }
    }
  end

  private

  attr_reader :user

  def active_family
    @active_family ||= user.family_memberships.order(created_at: :desc).first.family
  end

  def active_membership
    @active_membership ||= user.membership_for(active_family)
  end

  def me_payload
    {
      user_id: user.id,
      owner: active_membership.owner?,
      sharing: {
        enabled: active_membership.sharing_active?,
        duration: active_membership.sharing_duration_label,
        expires_at: active_membership.sharing_expires_at&.iso8601,
        started_at: active_membership.sharing_started_at&.iso8601,
        share_history: active_membership.share_history?,
        history_window: active_membership.history_window
      }
    }
  end

  def members_payload
    members = user.family_memberships.includes(:family).order(created_at: :desc).flat_map do |membership|
      membership.family.members.includes(:family_memberships).map do |member|
        member_membership = member.membership_for(membership.family)
        {
          user_id: member.id,
          email: member.email,
          email_initial: prefixed_initial(membership.family, member),
          family_id: membership.family.id,
          family_name: membership.family.name,
          owner: member.owner_of?(membership.family),
          sharing_enabled: member_membership&.sharing_active? || false,
          joined_at: member_membership&.created_at&.iso8601
        }
      end
    end

    dedupe_members(members)
  end

  # Deduplicate by user_id to present one consolidated member list.
  def dedupe_members(members)
    members
      .group_by { |m| m[:user_id] }
      .map do |_id, entries|
        entries.max_by { |e| [e[:sharing_enabled] ? 1 : 0, e[:family_id] == active_family&.id ? 1 : 0] }
      end
  end

  # Avatar initial carries the family when the user is in several families.
  def prefixed_initial(family, member)
    return member.email.first.upcase unless multi_family?

    "#{family.name.first}#{member.email.first}".upcase
  end

  def multi_family?
    @multi_family ||= user.family_memberships.count > 1
  end

  def incoming_request(request)
    {
      id: request.id,
      requester: { user_id: request.requester_id, email: request.requester.email },
      suggested_duration: request.suggested_duration,
      expires_at: request.expires_at.iso8601,
      created_at: request.created_at.iso8601,
      family_id: request.family_id,
      family_name: request.family.name
    }
  end

  def outgoing_request(request)
    {
      id: request.id,
      target_user_id: request.target_user_id,
      created_at: request.created_at.iso8601,
      family_id: request.family_id,
      family_name: request.family.name
    }
  end
end
