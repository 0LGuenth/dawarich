# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260705120002_backfill_membership_sharing_from_user_settings')

RSpec.describe BackfillMembershipSharingFromUserSettings do
  let(:user) { create(:user) }
  let!(:membership) { create(:family_membership, user: user) }

  def set_sharing_blob(blob)
    user.update!(settings: user.settings.merge('family' => { 'location_sharing' => blob }))
  end

  describe '#up' do
    it 'backfills the membership from legacy enabled sharing settings' do
      started_at = 1.hour.ago
      expires_at = 1.hour.from_now
      set_sharing_blob(
        'enabled' => true,
        'started_at' => started_at.iso8601,
        'expires_at' => expires_at.iso8601,
        'share_history' => true,
        'history_window' => '48h',
        'duration' => '1h'
      )

      described_class.new.up
      membership.reload

      expect(membership.sharing_enabled).to be(true)
      expect(membership.share_history).to be(true)
      expect(membership.history_window).to eq('48h')
      expect(membership.sharing_duration).to eq('1h')
      expect(membership.sharing_started_at).to be_within(1.second).of(started_at)
      expect(membership.sharing_expires_at).to be_within(1.second).of(expires_at)
    end

    it "falls back to '24h' history_window when the blob's history_window is blank" do
      set_sharing_blob(
        'enabled' => true,
        'share_history' => false,
        'history_window' => ''
      )

      described_class.new.up
      membership.reload

      expect(membership.sharing_enabled).to be(true)
      expect(membership.history_window).to eq('24h')
    end

    it 'leaves the membership at defaults when sharing is not enabled' do
      set_sharing_blob('enabled' => false, 'history_window' => '48h')

      described_class.new.up
      membership.reload

      expect(membership.sharing_enabled).to be(false)
      expect(membership.share_history).to be(false)
      expect(membership.history_window).to eq('24h')
      expect(membership.sharing_duration).to be_nil
    end

    it 'leaves the membership at defaults when there is no sharing blob' do
      membership # ensure it exists

      described_class.new.up
      membership.reload

      expect(membership.sharing_enabled).to be(false)
    end

    it 'is idempotent when run twice' do
      started_at = 1.hour.ago
      set_sharing_blob(
        'enabled' => true,
        'started_at' => started_at.iso8601,
        'share_history' => true,
        'history_window' => '48h',
        'duration' => '1h'
      )

      described_class.new.up
      described_class.new.up
      membership.reload

      expect(membership.sharing_enabled).to be(true)
      expect(membership.share_history).to be(true)
      expect(membership.history_window).to eq('48h')
      expect(membership.sharing_duration).to eq('1h')
      expect(membership.sharing_started_at).to be_within(1.second).of(started_at)
    end

    it 'does not destroy the user settings blob' do
      set_sharing_blob('enabled' => true, 'history_window' => '48h')

      described_class.new.up
      user.reload

      expect(user.settings.dig('family', 'location_sharing')).to be_present
      expect(user.settings.dig('family', 'location_sharing', 'enabled')).to be(true)
    end
  end
end
