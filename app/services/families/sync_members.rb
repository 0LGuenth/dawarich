# frozen_string_literal: true

module Families
  class SyncMembers
    attr_reader :family

    def initialize(family:, notify: true)
      @family = family
      @notify = notify
    end

    def call
      return false if DawarichSettings.self_hosted?
      return false if family.blank?

      to_notify = []

      family.with_lock do
        refresh_access_until
        syncable_members.each do |member|
          granted? ? grant(member) : to_notify << lapse(member)
        end
      end

      to_notify.compact.each { |member| Families::LapseNotificationJob.perform_later(member.id, family.id) }

      true
    end

    private

    def owner
      @owner ||= User.find_by(id: family.creator_id)
    end

    def refresh_access_until
      return unless owner&.family?
      return if owner.active_until.blank?

      family.update!(access_until: owner.active_until)
    end

    def granted?
      family.access_until&.future? || false
    end

    def syncable_members
      family.members.includes(:family_memberships).reject do |member|
        member == owner || member.own_subscription_live?
      end
    end

    def grant(member)
      member.skip_family_sync = true
      new_until = [member.families.where.not(id: family.id).maximum(:access_until), family.access_until].compact.max
      member.update!(
        plan: :pro, status: :active, active_until: new_until, subscription_source: :none
      )
      Families::LapseNotice.clear(member)
    end

    def lapse(member)
      return if other_active_family?(member)

      member.skip_family_sync = true
      member.update!(plan: :lite, status: :inactive, active_until: family.access_until)
      return nil if Families::LapseNotice.notified?(member)
      return Families::LapseNotice.mark(member) && nil unless @notify

      member
    end

    def other_active_family?(member)
      member.families.where.not(id: family.id).any?(&:access_live?)
    end
  end
end
