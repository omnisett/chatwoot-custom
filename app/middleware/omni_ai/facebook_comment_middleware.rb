# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════════════
# Rack middleware to intercept Facebook Page webhook POST /bot requests
# that contain comment events (field='feed', item='comment').
#
# The facebook-messenger gem only processes `messaging[]` entries and ignores
# `changes[]` entries. This middleware taps into the raw request body,
# detects comment payloads, and forwards them to Omni-AI — BEFORE the gem
# processes it. The original request continues unmodified.
#
# Insert BEFORE the Facebook::Messenger::Server mount in the middleware stack.
# ═══════════════════════════════════════════════════════════════════════════════

module OmniAi
  class FacebookCommentMiddleware
    BOT_PATH = '/bot'

    def initialize(app)
      @app = app
    end

    def call(env)
      request = Rack::Request.new(env)

      # Only intercept POST /bot with JSON body
      if request.post? && request.path == BOT_PATH && json_content?(request)
        body = read_body(request)
        if body.present?
          begin
            payload = JSON.parse(body).with_indifferent_access
            if payload[:object] == 'page' && comment_entries?(payload[:entry])
              page_id = payload[:entry]&.first&.dig(:id)
              OmniAi::CommentForwarder.forward(
                platform: 'facebook',
                entries: payload[:entry].as_json,
                page_id: page_id
              )
              Rails.logger.info("[OmniAi] Forwarded Facebook comment webhook (page_id=#{page_id})")
            end
          rescue JSON::ParserError => e
            Rails.logger.warn("[OmniAi::FacebookCommentMiddleware] JSON parse error: #{e.message}")
          end
        end
      end

      # Always pass through to the original handler
      @app.call(env)
    end

    private

    def json_content?(request)
      ct = request.content_type.to_s.downcase
      ct.include?('application/json') || ct.include?('text/json')
    end

    def read_body(request)
      body = request.body.read
      request.body.rewind # Rewind so downstream can read it again
      body
    end

    def comment_entries?(entries)
      return false unless entries.is_a?(Array)

      entries.any? do |entry|
        changes = entry[:changes] || entry['changes'] || []
        changes.any? do |change|
          field = change[:field] || change['field']
          value = change[:value] || change['value'] || {}
          item = value[:item] || value['item']
          field.to_s == 'feed' && item.to_s == 'comment'
        end
      end
    end
  end
end
