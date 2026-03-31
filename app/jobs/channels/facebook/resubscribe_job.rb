# frozen_string_literal: true

class Channels::Facebook::ResubscribeJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 15.seconds, attempts: 5

  def perform(channel_id)
    channel = Channel::FacebookPage.find_by(id: channel_id)
    return unless channel

    Rails.logger.info("[FacebookPage::ResubscribeJob] Attempting subscribe for page_id=#{channel.page_id} (channel_id=#{channel_id})")

    result = Facebook::Messenger::Subscriptions.subscribe(
      access_token: channel.page_access_token,
      subscribed_fields: %w[
        feed messages message_deliveries message_echoes message_reads standby messaging_handovers
      ]
    )
    Rails.logger.info("[FacebookPage::ResubscribeJob] Subscribed page_id=#{channel.page_id}: #{result}")
  end
end
