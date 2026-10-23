# frozen_string_literal: true

class Users::Destroy
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    user_id = user.id
    user_email = user.email

    cancel_scheduled_jobs

    Users::DataLock.with_exclusive(user_id) do
      purge_attachments_for('Import', user.imports)
      purge_attachments_for('Export', user.exports)
      purge_attachments_for('Points::RawDataArchive', user.raw_data_archives)

      ActiveRecord::Base.transaction do
        created_families = Family.where(creator_id: user_id).to_a
        blocking = created_families.find { |f| Family::Membership.where(family_id: f.id).count > 1 }
        if blocking
          error_message = I18n.t('services.users.destroy.cannot_delete_user_who_owns_a_family_with_other_members')
          Rails.logger.warn "#{error_message}: user_id=#{user_id}"
          user.errors.add(:base, error_message)
          raise ActiveRecord::RecordInvalid, user
        end

        user.points.delete_all
        user.imports.delete_all
        user.stats.delete_all
        user.exports.delete_all
        user.posters.destroy_all
        user.route_videos.destroy_all
        user.notifications.delete_all
        user.achievement_progresses.delete_all
        user.user_achievements.delete_all
        user.flights.delete_all
        user.notes.delete_all
        user.service_settings.delete_all

        PlaceVisit.where(visit_id: user.visits.select(:id)).delete_all
        PlaceVisit.where(place_id: user.places.select(:id)).delete_all

        user.visits.delete_all
        user.areas.delete_all

        Visit.where(place_id: user.places.select(:id)).update_all(place_id: nil)
        user.places.delete_all

        Tagging.where(tag_id: user.tags.select(:id)).delete_all
        user.tags.delete_all

        user.trips.find_each(&:destroy!)
        user.trip_sources.delete_all

        TrackSegment.where(track_id: user.tracks.select(:id)).delete_all
        delete_video_exports_for(user)
        user.tracks.delete_all
        Points::Revision.where(user_id: user.id).delete_all
        Tracks::Revision.where(user_id: user.id).delete_all

        user.raw_data_archives.delete_all
        user.digests.delete_all
        user.sent_family_invitations.delete_all if user.respond_to?(:sent_family_invitations)

        Family::LocationRequest.where(requester_id: user.id)
                               .or(Family::LocationRequest.where(target_user_id: user.id))
                               .delete_all

        Family::Membership.where(user_id: user.id).delete_all

        created_families.each do |created_family|
          Family::LocationRequest.where(family_id: created_family.id).delete_all
          Family::Membership.where(family_id: created_family.id).delete_all
          created_family.delete
        end

        user.delete
      end
    end

    Rails.logger.info "User #{user_id} (#{user_email}) and all associated data deleted"

    cleanup_user_cache(user_id)

    true
  end

  private

  CANCELLABLE_JOB_CLASSES = %w[
    Users::MailerSendingJob
    Users::Digests::Yearly::EmailSendingJob
    Users::Digests::Monthly::EmailSendingJob
    Users::Digests::EmailSendingJob
    Tracks::RealtimeGenerationJob
    Tracks::BoundaryResolverJob
  ].freeze

  def cancel_scheduled_jobs
    scheduled_set = Sidekiq::ScheduledSet.new

    jobs_cancelled = scheduled_set.select do |job|
      wrapped_class = job.item['wrapped']
      next false unless CANCELLABLE_JOB_CLASSES.include?(wrapped_class)

      # ActiveJob stores arguments in args[0]['arguments'], first argument is user_id
      job.args.first&.dig('arguments')&.first == user.id
    end.map(&:delete).count

    Rails.logger.info "Cancelled #{jobs_cancelled} scheduled jobs for user #{user.id}"
  rescue StandardError => e
    Rails.logger.warn "Failed to cancel scheduled jobs for user #{user.id}: #{e.message}"
    ExceptionReporter.call(e, 'Failed to cancel scheduled jobs during user deletion')
  end

  def purge_attachments_for(record_type, relation)
    ActiveStorage::Attachment
      .where(record_type: record_type, record_id: relation.select(:id))
      .find_each(&:purge)
  rescue StandardError => e
    Rails.logger.warn "Failed to purge #{record_type} attachments: #{e.message}"
    ExceptionReporter.call(e, "Failed to purge #{record_type} attachments for user #{user.id}")
  end

  # video_exports has no model class; use raw SQL to avoid NameError.
  def delete_video_exports_for(user)
    return unless ActiveRecord::Base.connection.table_exists?('video_exports')

    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array(
        ['DELETE FROM video_exports WHERE user_id = ?', user.id]
      )
    )
  end

  def cleanup_user_cache(user_id)
    cache_keys = [
      "dawarich/user_#{user_id}_countries_visited",
      "dawarich/user_#{user_id}_cities_visited",
      "dawarich/user_#{user_id}_total_distance",
      "dawarich/user_#{user_id}_years_tracked"
    ]

    cache_keys.each { |key| Rails.cache.delete(key) }

    Rails.logger.info "Cleared cache for user #{user_id}"
  rescue StandardError => e
    Rails.logger.warn "Failed to clear cache for user #{user_id}: #{e.message}"
  end
end
