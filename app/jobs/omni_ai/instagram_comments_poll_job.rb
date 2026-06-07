# frozen_string_literal: true

# Fallback for Meta Instagram real comment webhooks occasionally not being
# delivered even while dashboard test webhooks work. Polls recent media comments
# and forwards unseen comments through the same Omni-AI comment flow.
module OmniAi
  class InstagramCommentsPollJob < ApplicationJob
    queue_as :scheduled_jobs

    GRAPH_BASE = 'https://graph.instagram.com/v24.0'
    DEFAULT_MEDIA_LIMIT = 10
    DEFAULT_COMMENTS_LIMIT = 25
    DEFAULT_SEEN_TTL = 14.days
    DEFAULT_LOOKBACK_HOURS = 48

    def perform
      return unless enabled?
      return unless OmniAi::CommentForwarder::ENABLED

      Channel::Instagram.includes(:inbox).find_each do |channel|
        poll_channel(channel)
      rescue StandardError => e
        Rails.logger.error("[OmniAi::InstagramCommentsPollJob] Channel poll failed instagram_id=#{channel&.instagram_id}: #{e.class} - #{e.message}")
      end
    end

    private

    def enabled?
      ENV.fetch('OMNI_AI_INSTAGRAM_COMMENT_POLLING_ENABLED', ENV.fetch('OMNI_AI_COMMENTS_ENABLED', 'false')) == 'true'
    end

    def poll_channel(channel)
      token = channel.access_token
      return if token.blank?

      media_items(channel, token).each do |media|
        comments_for_media(media['id'], token).each do |comment|
          forward_comment(channel, media, comment)
        end
      end
    end

    def media_items(channel, token)
      response = HTTParty.get(
        "#{GRAPH_BASE}/#{channel.instagram_id}/media",
        query: {
          fields: 'id,media_product_type,permalink,timestamp,comments_count',
          limit: media_limit,
          access_token: token
        },
        timeout: 15
      )

      unless response.success?
        Rails.logger.warn("[OmniAi::InstagramCommentsPollJob] Media fetch failed instagram_id=#{channel.instagram_id}: #{response.code} #{response.body&.truncate(500)}")
        return []
      end

      Array(response.parsed_response&.dig('data'))
    end

    def comments_for_media(media_id, token)
      return [] if media_id.blank?

      response = HTTParty.get(
        "#{GRAPH_BASE}/#{media_id}/comments",
        query: {
          fields: 'id,text,timestamp,username,parent_id',
          limit: comments_limit,
          access_token: token
        },
        timeout: 15
      )

      unless response.success?
        Rails.logger.warn("[OmniAi::InstagramCommentsPollJob] Comment fetch failed media_id=#{media_id}: #{response.code} #{response.body&.truncate(500)}")
        return []
      end

      Array(response.parsed_response&.dig('data'))
    end

    def forward_comment(channel, media, comment)
      comment_id = comment['id'].to_s
      return if comment_id.blank? || comment['text'].blank?
      return if too_old?(comment['timestamp'])
      return if seen?(comment_id)

      entry = {
        id: channel.instagram_id,
        time: parsed_time(comment['timestamp']),
        changes: [
          {
            field: 'comments',
            value: {
              id: comment_id,
              text: comment['text'].to_s,
              from: commenter_from(comment),
              media: {
                id: media['id'].to_s,
                media_product_type: media['media_product_type'].presence || 'FEED'
              },
              parent_id: comment['parent_id'].to_s
            }.compact
          }
        ]
      }

      result = OmniAi::CommentForwarder.forward(
        platform: 'instagram',
        entries: [entry],
        instagram_id: channel.instagram_id
      )

      if result[:enqueued]
        mark_seen(comment_id)
        Rails.logger.info("[OmniAi::InstagramCommentsPollJob] Forwarded polled instagram comment comment_id=#{comment_id} media_id=#{media['id']}")
      else
        Rails.logger.warn("[OmniAi::InstagramCommentsPollJob] Skipped polled instagram comment comment_id=#{comment_id} reason=#{result[:reason]}")
      end
    end

    def commenter_from(comment)
      username = comment['username'].to_s
      return {} if username.blank?

      { id: username, username: username }
    end

    def seen?(comment_id)
      Rails.cache.exist?(seen_key(comment_id))
    end

    def mark_seen(comment_id)
      Rails.cache.write(seen_key(comment_id), true, expires_in: seen_ttl)
    end

    def seen_key(comment_id)
      "omni_ai:instagram_comment_poll:seen:#{comment_id}"
    end

    def parsed_time(value)
      Time.zone.parse(value.to_s).to_i
    rescue StandardError
      Time.current.to_i
    end

    def media_limit
      ENV.fetch('OMNI_AI_INSTAGRAM_COMMENT_POLL_MEDIA_LIMIT', DEFAULT_MEDIA_LIMIT).to_i.clamp(1, 50)
    end

    def comments_limit
      ENV.fetch('OMNI_AI_INSTAGRAM_COMMENT_POLL_COMMENTS_LIMIT', DEFAULT_COMMENTS_LIMIT).to_i.clamp(1, 100)
    end

    def too_old?(value)
      timestamp = Time.zone.parse(value.to_s)
      timestamp < lookback_hours.hours.ago
    rescue StandardError
      false
    end

    def lookback_hours
      ENV.fetch('OMNI_AI_INSTAGRAM_COMMENT_POLL_LOOKBACK_HOURS', DEFAULT_LOOKBACK_HOURS).to_i.clamp(1, 24 * 14)
    end

    def seen_ttl
      ENV.fetch('OMNI_AI_INSTAGRAM_COMMENT_POLL_SEEN_TTL_DAYS', 14).to_i.clamp(1, 90).days
    end
  end
end
