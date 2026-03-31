# frozen_string_literal: true

# Proxy controller that forwards Comments page requests from the Chatwoot
# frontend to the Omni-AI backend.  Keeps all comment data isolated in
# Omni-AI's own database — nothing stored in Chatwoot tables.
#
# Routes:
#   GET  /auth/omni_ai/comments/stats
#   GET  /auth/omni_ai/comments/by-post
#   GET  /auth/omni_ai/comments/post/:postId
#   GET  /auth/omni_ai/comments/post-info/:postId
#   PUT  /auth/omni_ai/comments/:id/reply
#   GET  /auth/omni_ai/comments/commenter/:commenterId
#   POST /auth/omni_ai/comments/:commentId/dm  — trigger DM via Chatwoot channel
#   GET  /auth/omni_ai/comments                — list all

class OmniAi::CommentsProxyController < Api::V1::Accounts::BaseController
  before_action :verify_access

  # Proxy GET requests to omni-ai backend
  def stats
    proxy_get('/api/comments/stats')
  end

  def by_post
    proxy_get('/api/comments/by-post', permitted_query(:platform, :q))
  end

  def post_comments
    proxy_get("/api/comments/post/#{encoded_param(:post_id)}")
  end

  def post_info
    proxy_get("/api/comments/post-info/#{encoded_param(:post_id)}", permitted_query(:platform))
  end

  def index
    proxy_get('/api/comments', permitted_query(:platform, :status, :q, :limit))
  end

  def commenter_history
    proxy_get("/api/comments/commenter/#{encoded_param(:commenter_id)}")
  end

  # Proxy PUT reply
  def reply
    proxy_put("/api/comments/#{encoded_param(:id)}/reply", { reply: params[:reply] })
  end

  # DM flow: create/find contact, send message through Chatwoot channel
  def send_dm
    comment_id = params[:comment_id]
    dm_text = params[:dm_text]
    platform = params[:platform] || 'facebook'

    return render json: { error: 'dm_text required' }, status: :bad_request if dm_text.blank?

    # Fetch comment details from omni-ai to get commenter info
    comment_res = fetch_from_omni("/api/comments/#{ERB::Util.url_encode(comment_id)}")
    return render json: { error: 'comment_not_found' }, status: :not_found unless comment_res

    commenter_id = comment_res['commenter_id']
    commenter_name = comment_res['commenter_name'] || comment_res['commenter_username'] || 'User'

    # Use the private_reply flow (reuse existing OmniAi controller logic)
    inbox_id = resolve_inbox_id(platform)
    return render json: { error: 'no_inbox_configured' }, status: :unprocessable_entity unless inbox_id

    inbox = Inbox.find_by(id: inbox_id)
    return render json: { error: 'inbox_not_found' }, status: :not_found unless inbox

    # Find or create contact
    contact_inbox = find_or_create_contact(inbox, commenter_id, commenter_name, platform)
    return render json: { error: 'contact_creation_failed' }, status: :unprocessable_entity unless contact_inbox

    # Find or create conversation, then send message
    conversation = find_or_create_conversation(contact_inbox, inbox)

    outgoing = conversation.messages.create!(
      account: current_account,
      inbox: inbox,
      message_type: :outgoing,
      content: dm_text,
      sender: current_user
    )

    # Update omni-ai backend with DM info
    proxy_put("/api/comments/#{ERB::Util.url_encode(comment_id)}/dm", {
      dm_text: dm_text,
      dm_conversation_id: conversation.display_id.to_s,
      dm_message_id: outgoing.id.to_s,
      dm_contact_id: contact_inbox.contact_id.to_s
    })

    render json: {
      success: true,
      conversation_id: conversation.display_id,
      message_id: outgoing.id
    }
  rescue StandardError => e
    Rails.logger.error("[OmniAi::CommentsProxy] DM send error: #{e.message}")
    render json: { error: 'dm_send_failed', details: e.message }, status: :unprocessable_entity
  end

  private

  def verify_access
    enabled = ENV.fetch('OMNI_COMMENTS_PAGE_ENABLED', 'false')
    return head :not_found unless enabled.to_s.downcase == 'true'

    allowed_ids = ENV.fetch('OMNI_COMMENTS_PAGE_USER_IDS', '')
    return if allowed_ids.strip.upcase == 'ALL'

    ids = allowed_ids.split(',').map(&:strip).map(&:to_i)
    head :forbidden unless ids.include?(current_user.id)
  end

  def omni_ai_base_url
    @omni_ai_base_url ||= ENV.fetch('OMNI_AI_WEBHOOK_URL', '').sub(%r{/webhooks/chatwoot\z}, '')
  end

  def omni_ai_token
    @omni_ai_token ||= ENV.fetch('OMNI_AI_WEBHOOK_TOKEN', '')
  end

  def proxy_get(path, query_params = {})
    url = "#{omni_ai_base_url}#{path}"
    response = HTTParty.get(url, query: query_params, headers: auth_headers, timeout: 15)
    render json: response.parsed_response, status: response.code
  rescue StandardError => e
    Rails.logger.error("[OmniAi::CommentsProxy] GET #{path} error: #{e.message}")
    render json: { error: 'proxy_error', details: e.message }, status: :bad_gateway
  end

  def proxy_put(path, body = {})
    url = "#{omni_ai_base_url}#{path}"
    response = HTTParty.put(url, body: body.to_json, headers: auth_headers.merge('Content-Type' => 'application/json'), timeout: 15)
    render json: response.parsed_response, status: response.code
  rescue StandardError => e
    Rails.logger.error("[OmniAi::CommentsProxy] PUT #{path} error: #{e.message}")
    render json: { error: 'proxy_error', details: e.message }, status: :bad_gateway
  end

  def fetch_from_omni(path)
    url = "#{omni_ai_base_url}#{path}"
    response = HTTParty.get(url, headers: auth_headers, timeout: 10)
    response.success? ? response.parsed_response : nil
  rescue StandardError
    nil
  end

  def auth_headers
    { 'Authorization' => "Bearer #{omni_ai_token}" }
  end

  def encoded_param(key)
    ERB::Util.url_encode(params[key].to_s)
  end

  def permitted_query(*keys)
    params.permit(*keys).to_h.compact_blank
  end

  def resolve_inbox_id(platform)
    if platform == 'instagram'
      ENV['OMNI_AI_INSTAGRAM_INBOX_ID'].presence || current_account&.inboxes&.joins(:channel)
        &.where(channel_type: 'Channel::Instagram')&.first&.id
    else
      ENV['OMNI_AI_FACEBOOK_INBOX_ID'].presence || current_account&.inboxes&.joins(:channel)
        &.where(channel_type: 'Channel::FacebookPage')&.first&.id
    end
  end

  def find_or_create_contact(inbox, platform_id, name, platform)
    # Try finding existing contact_inbox by source_id
    contact_inbox = inbox.contact_inboxes.find_by(source_id: platform_id)
    return contact_inbox if contact_inbox

    # Create new contact
    contact = current_account.contacts.create!(
      name: name,
      identifier: platform_id
    )
    ContactInbox.create!(
      contact: contact,
      inbox: inbox,
      source_id: platform_id
    )
  rescue ActiveRecord::RecordInvalid => e
    # identifier uniqueness — find existing
    contact = current_account.contacts.find_by(identifier: platform_id)
    if contact
      ci = contact.contact_inboxes.find_by(inbox: inbox)
      return ci if ci
      ContactInbox.create!(contact: contact, inbox: inbox, source_id: platform_id)
    else
      Rails.logger.error("[OmniAi::CommentsProxy] Contact creation failed: #{e.message}")
      nil
    end
  end

  def find_or_create_conversation(contact_inbox, inbox)
    # Find recent open conversation
    conversation = current_account.conversations
      .where(inbox: inbox, contact_inbox: contact_inbox)
      .where(status: [:open, :pending])
      .order(created_at: :desc)
      .first

    return conversation if conversation

    # Create new conversation
    current_account.conversations.create!(
      inbox: inbox,
      contact: contact_inbox.contact,
      contact_inbox: contact_inbox,
      status: :open,
      assignee: current_user
    )
  end
end
