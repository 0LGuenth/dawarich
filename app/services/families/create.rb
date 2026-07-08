# frozen_string_literal: true

module Families
  class Create
    include ActiveModel::Validations

    attr_reader :user, :name, :family, :error_message

    validates :name, presence: { message: 'Family name is required' }
    validates :name, length: {
      maximum: 50,
      message: 'Family name must be 50 characters or less'
    }

    def initialize(user:, name:)
      @user = user
      @name = name&.strip
      @error_message = nil
    end

    def call
      return false unless valid?
      return false unless validate_user_eligibility
      return false unless validate_feature_access

      ActiveRecord::Base.transaction do
        create_family
        create_owner_membership
        send_notification
      end

      true
    rescue ActiveRecord::RecordInvalid => e
      handle_record_invalid_error(e)

      false
    rescue StandardError => e
      handle_generic_error(e)

      false
    end

    private

    def validate_user_eligibility
      return true if user.can_create_more_families?

      @error_message = "You have reached the maximum number of families (#{UserFamily::MAX_FAMILIES})"
      false
    end

    def validate_feature_access
      return true if can_create_family?

      @error_message =
        if DawarichSettings.self_hosted?
          'Family feature is not available on this instance'
        else
          'Family feature requires an active subscription'
        end

      false
    end

    def can_create_family?
      return true if DawarichSettings.self_hosted?

      # TODO: Add cloud plan validation here when needed
      # For now, allow all users to create families
      true
    end

    def create_family
      @family = Family.create!(name: name, creator: user)
    end

    # Lock the user row so concurrent creates can't both pass the MAX_FAMILIES check
    def create_owner_membership
      user.with_lock do
        Family::Membership.create!(family: family, user: user, role: :owner)
      end
    end

    def send_notification
      Notification.create!(
        user: user,
        kind: :info,
        title: 'Family Created',
        content: "You've successfully created the family '#{family.name}'"
      )
    rescue StandardError => e
      # Don't fail the entire operation if notification fails
      ExceptionReporter.call(e, "Unexpected error in Families::Create: #{e.message}")
    end

    def handle_record_invalid_error(error)
      @error_message =
        if family&.errors&.any?
          family.errors.full_messages.first
        else
          "Failed to create family: #{error.message}"
        end
    end

    def handle_generic_error(error)
      ExceptionReporter.call(error, "Unexpected error in Families::Create: #{error.message}")
      @error_message = 'An unexpected error occurred while creating the family. Please try again'
    end
  end
end
