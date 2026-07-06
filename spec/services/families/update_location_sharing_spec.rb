# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::UpdateLocationSharing do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:membership) { create(:family_membership, user: user) }

  describe '.call' do
    context 'when enabling location sharing with a duration' do
      around do |example|
        travel_to(Time.zone.local(2024, 1, 1, 12, 0, 0)) { example.run }
      end

      it 'returns a successful result with the expected payload' do
        result = described_class.new(membership: membership, enabled: 'true', duration: '1h').call

        expect(result).to be_success
        expect(result.status).to eq(:ok)
        expect(result.payload[:success]).to be true
        expect(result.payload[:enabled]).to be true
        expect(result.payload[:duration]).to eq('1h')
        expect(result.payload[:message]).to eq('Location sharing enabled for 1 hour')
        expect(result.payload[:expires_at]).to eq(1.hour.from_now.iso8601)
        expect(result.payload[:expires_at_formatted]).to eq(1.hour.from_now.strftime('%b %d at %I:%M %p'))
      end

      it 'enables sharing on the membership' do
        described_class.new(membership: membership, enabled: 'true', duration: '1h').call

        expect(membership.reload.sharing_active?).to be(true)
      end
    end

    context 'when disabling location sharing' do
      before { membership.update_sharing!(true, duration: 'permanent') }

      it 'returns a successful result without expiration details' do
        result = described_class.new(membership: membership, enabled: 'false', duration: nil).call

        expect(result).to be_success
        expect(result.payload[:success]).to be true
        expect(result.payload[:enabled]).to be false
        expect(result.payload[:message]).to eq('Location sharing disabled')
        expect(result.payload).not_to have_key(:expires_at)
        expect(result.payload).not_to have_key(:expires_at_formatted)
      end

      it 'disables sharing on the membership' do
        described_class.new(membership: membership, enabled: 'false', duration: nil).call

        expect(membership.reload.sharing_active?).to be(false)
      end
    end

    context 'when update raises an unexpected error' do
      before do
        allow(membership).to receive(:update_sharing!).and_raise(StandardError, 'boom')
      end

      it 'returns a failure result with internal server error status' do
        result = described_class.new(membership: membership, enabled: 'true', duration: '1h').call

        expect(result).not_to be_success
        expect(result.status).to eq(:internal_server_error)
        expect(result.payload[:success]).to be false
        expect(result.payload[:message]).to eq('An error occurred while updating location sharing')
      end
    end

    context 'when enabling with share_history and history_window' do
      context 'with share_history true and history_window 7d' do
        it 'persists share_history as boolean true' do
          described_class.new(
            membership: membership, enabled: 'true', duration: '1h',
            share_history: 'true', history_window: '7d'
          ).call

          expect(membership.reload.share_history?).to be true
        end

        it 'persists history_window as 7d' do
          described_class.new(
            membership: membership, enabled: 'true', duration: '1h',
            share_history: 'true', history_window: '7d'
          ).call

          expect(membership.reload.history_window).to eq('7d')
        end
      end

      context 'with share_history false' do
        it 'persists share_history as boolean false' do
          described_class.new(
            membership: membership, enabled: 'true', duration: '1h',
            share_history: 'false', history_window: '30d'
          ).call

          expect(membership.reload.share_history?).to be false
        end
      end

      context 'with invalid history_window' do
        it 'falls back to 24h' do
          described_class.new(
            membership: membership, enabled: 'true', duration: '1h',
            share_history: nil, history_window: 'invalid_value'
          ).call

          expect(membership.reload.history_window).to eq('24h')
        end
      end

      context 'with nil share_history preserves existing value' do
        before do
          membership.update_sharing!(true, duration: 'permanent', share_history: true, history_window: '30d')
        end

        it 'preserves existing share_history' do
          described_class.new(
            membership: membership, enabled: 'true', duration: 'permanent',
            share_history: nil, history_window: nil
          ).call

          expect(membership.reload.share_history?).to be true
        end

        it 'preserves existing history_window' do
          described_class.new(
            membership: membership, enabled: 'true', duration: 'permanent',
            share_history: nil, history_window: nil
          ).call

          expect(membership.reload.history_window).to eq('30d')
        end
      end
    end
  end
end
