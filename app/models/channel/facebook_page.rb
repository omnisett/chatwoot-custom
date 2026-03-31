# == Schema Information
#
# Table name: channel_facebook_pages
#
#  id                :integer          not null, primary key
#  page_access_token :string           not null
#  user_access_token :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :integer          not null
#  instagram_id      :string
#  page_id           :string           not null
#
# Indexes
#
#  index_channel_facebook_pages_on_page_id                 (page_id)
#  index_channel_facebook_pages_on_page_id_and_account_id  (page_id,account_id) UNIQUE
#

class Channel::FacebookPage < ApplicationRecord
  include Channelable
  include Reauthorizable

  # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
  if Chatwoot.encryption_configured?
    encrypts :page_access_token
    encrypts :user_access_token
  end

  self.table_name = 'channel_facebook_pages'

  validates :page_id, uniqueness: { scope: :account_id }

  after_create_commit :schedule_subscribe
  after_update_commit :subscribe, if: :saved_change_to_page_access_token?
  before_destroy :unsubscribe

  def name
    'Facebook'
  end

  def create_contact_inbox(instagram_id, name)
    @contact_inbox = ::ContactInboxWithContactBuilder.new({
                                                            source_id: instagram_id,
                                                            inbox: inbox,
                                                            contact_attributes: { name: name }
                                                          }).perform
  end

  # Schedule subscribe via background job with delay to avoid race conditions
  # (e.g. old inbox's DeleteObjectJob may unsubscribe after new one subscribes)
  def schedule_subscribe
    Channels::Facebook::ResubscribeJob.set(wait: 5.seconds).perform_later(id)
    Rails.logger.info("[FacebookPage] Scheduled subscribe for page_id=#{page_id} (channel_id=#{id}) in 5s")
  rescue StandardError => e
    Rails.logger.error("[FacebookPage] Failed to schedule subscribe for page_id=#{page_id}: #{e.class} — #{e.message}")
    subscribe # Fallback: try inline
  end

  def subscribe
    # ref https://developers.facebook.com/docs/messenger-platform/reference/webhook-events
    result = Facebook::Messenger::Subscriptions.subscribe(
      access_token: page_access_token,
      subscribed_fields: %w[
        feed messages message_deliveries message_echoes message_reads standby messaging_handovers
      ]
    )
    Rails.logger.info("[FacebookPage] Subscribed page_id=#{page_id} to webhooks: #{result}")
    result
  rescue StandardError => e
    Rails.logger.error("[FacebookPage] Failed to subscribe page_id=#{page_id}: #{e.class} — #{e.message}")
    # Retry once after 5 seconds in a background job
    Channels::Facebook::ResubscribeJob.perform_later(id) if persisted?
    true
  end

  def unsubscribe
    # Skip unsubscribe if another channel with the same page_id exists (inbox re-created)
    if Channel::FacebookPage.where(page_id: page_id).where.not(id: id).exists?
      Rails.logger.info("[FacebookPage] Skipping unsubscribe for page_id=#{page_id} — another channel exists")
      return true
    end

    Facebook::Messenger::Subscriptions.unsubscribe(access_token: page_access_token)
    Rails.logger.info("[FacebookPage] Unsubscribed page_id=#{page_id} from webhooks")
  rescue StandardError => e
    Rails.logger.error("[FacebookPage] Failed to unsubscribe page_id=#{page_id}: #{e.class} — #{e.message}")
    true
  end
end
