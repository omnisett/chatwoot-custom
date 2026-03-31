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

  after_create_commit :subscribe
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
    Facebook::Messenger::Subscriptions.unsubscribe(access_token: page_access_token)
    Rails.logger.info("[FacebookPage] Unsubscribed page_id=#{page_id} from webhooks")
  rescue StandardError => e
    Rails.logger.error("[FacebookPage] Failed to unsubscribe page_id=#{page_id}: #{e.class} — #{e.message}")
    true
  end
end
