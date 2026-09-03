# frozen_string_literal: true

module Families
  class AutoCreate
    attr_reader :user

    def initialize(user:)
      @user = user
    end

    def call
      return false unless eligible?

      ActiveRecord::Base.transaction do
        service = Families::Create.new(user: user, name: default_name, notify: false)
        raise ActiveRecord::Rollback unless service.call

        enable_owner_sharing(service.family)
        Families::SyncMembers.new(family: service.family).call
        notify_owner(service.family)
      end

      user.reload.in_family?
    end

    private

    def eligible?
      return false if DawarichSettings.self_hosted?
      return false unless user.family?
      return false if user.in_family?
      return false if user.created_families.exists?

      true
    end

    def default_name
      I18n.t('services.families.auto_create.default_name', locale: user.locale)
    end

    def enable_owner_sharing(family)
      membership = user.membership_for(family)
      membership&.update_sharing!(true)
    end

    def notify_owner(family)
      I18n.with_locale(user.locale) do
        Notification.create!(
          user: user,
          kind: :info,
          title: I18n.t('services.families.auto_create.notification_title'),
          content: I18n.t(
            'services.families.auto_create.notification_content',
            name: family.name,
            seats: Family::MAX_MEMBERS - 1
          )
        )
      end
    rescue StandardError => e
      ExceptionReporter.call(e, "Unexpected error in Families::AutoCreate: #{e.message}")
    end
  end
end
