# frozen_string_literal: true

# POST /api/v1/omni_ai/comment_reply
#
# Called by omni-ai backend to post an AI-generated reply to an Instagram or
# Facebook comment. Uses the access_token stored in Chatwoot's inbox channel,
# so the token is never exposed to the omni-ai process.
#
# Auth:   Authorization: Bearer {OMNI_AI_WEBHOOK_TOKEN}
# Body:   inbox_id, comment_id, reply_text, platform ("instagram" | "facebook")

class OmniAi::CommentRepliesController < ActionController::API
  include OmniAi::InboxResolver

  before_action :verify_token

  def create
    comment_id = params[:comment_id].to_s.strip
    reply_text = params[:reply_text].to_s.strip
    platform   = params[:platform].to_s.downcase.presence || 'instagram'

    if comment_id.blank? || reply_text.blank?
      return render json: { error: 'comment_id and reply_text are required' }, status: :bad_request
    end

    inbox = resolve_inbox
    return render json: { error: 'inbox not found' }, status: :not_found unless inbox

    candidates = reply_candidates(inbox, platform).select do |candidate|
      candidate[:access_token].present?
    end
    if candidates.empty?
      return render json: { error: 'inbox channel has no usable access_token' }, status: :unprocessable_entity
    end

    attempts = []
    last_response = nil

    candidates.each do |candidate|
      response = HTTParty.post(
        "#{candidate[:graph_base]}/#{comment_id}/#{candidate[:edge]}",
        query: { message: reply_text, access_token: candidate[:access_token] }
      )

      attempts << { source: candidate[:source], code: response.code }
      if response.success?
        Rails.logger.info(
          "[OmniAi] comment_reply posted: comment=#{comment_id} " \
          "platform=#{platform} source=#{candidate[:source]}"
        )
        return render json: {
          success: true,
          id: parsed_response(response)['id'],
          source: candidate[:source]
        }, status: :ok
      end

      last_response = response
      Rails.logger.warn(
        "[OmniAi] comment_reply Graph API error: comment=#{comment_id} " \
        "platform=#{platform} source=#{candidate[:source]} " \
        "code=#{response.code} body=#{response.body&.truncate(500)}"
      )
    end

    render json: {
      error: parsed_response(last_response),
      code: last_response&.code,
      attempts: attempts
    }, status: :unprocessable_entity
  end

  private

  def verify_token
    expected = ENV.fetch('OMNI_AI_WEBHOOK_TOKEN', '')
    actual   = request.headers['Authorization'].to_s.delete_prefix('Bearer ').strip
    return head :unauthorized unless expected.present?
    return head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(actual, expected)
  end

  def reply_candidates(inbox, platform)
    channel = inbox.channel
    return [] unless channel

    return facebook_reply_candidates(channel) if platform == 'facebook'

    instagram_reply_candidates(channel, inbox.account_id)
  end

  def facebook_reply_candidates(channel)
    return [] unless channel.respond_to?(:page_access_token)

    [
      {
        source: 'facebook_page',
        graph_base: facebook_graph_base,
        edge: 'comments',
        access_token: safe_access_token(channel, :page_access_token)
      }
    ]
  end

  def instagram_reply_candidates(channel, account_id)
    candidates = []

    if channel.is_a?(Channel::Instagram)
      candidates << {
        source: 'instagram_business_login',
        graph_base: instagram_graph_base,
        edge: 'replies',
        access_token: safe_access_token(channel, :access_token)
      }

      facebook_channel = Channel::FacebookPage.find_by(
        account_id: account_id,
        instagram_id: channel.instagram_id
      )
      candidates.concat(instagram_via_facebook_candidates(facebook_channel)) if facebook_channel
    elsif channel.is_a?(Channel::FacebookPage)
      candidates.concat(instagram_via_facebook_candidates(channel))

      instagram_channel = if channel.instagram_id.present?
                            Channel::Instagram.find_by(instagram_id: channel.instagram_id)
                          end
      if instagram_channel
        candidates << {
          source: 'instagram_business_login',
          graph_base: instagram_graph_base,
          edge: 'replies',
          access_token: safe_access_token(instagram_channel, :access_token)
        }
      end
    end

    candidates
  end

  def instagram_via_facebook_candidates(channel)
    return [] unless channel&.respond_to?(:page_access_token)

    [
      {
        source: 'facebook_page_instagram_graph',
        graph_base: facebook_graph_base,
        edge: 'replies',
        access_token: safe_access_token(channel, :page_access_token)
      }
    ]
  end

  def safe_access_token(channel, method_name)
    channel.public_send(method_name)
  rescue StandardError => e
    Rails.logger.warn(
      "[OmniAi] comment_reply token resolution failed: channel=#{channel.class.name} " \
      "error=#{e.class} #{e.message}"
    )
    nil
  end

  def instagram_graph_base
    "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v24.0')}"
  end

  def facebook_graph_base
    "https://graph.facebook.com/#{GlobalConfigService.load('FACEBOOK_API_VERSION', 'v24.0')}"
  end

  def parsed_response(response)
    return {} unless response

    response.parsed_response || {}
  rescue StandardError
    { 'raw' => response.body }
  end
end
