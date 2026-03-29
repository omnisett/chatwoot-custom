# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════════════
# Omni-AI Webhook Auto-Registration
# ═══════════════════════════════════════════════════════════════════════════════
#
# Automatically creates an account-level webhook in Chatwoot on app boot
# so that message_created / message_updated / conversation events are
# forwarded to the Omni-AI backend (POST /webhooks/chatwoot).
#
# This webhook handles regular DM messages from Instagram, Facebook, WhatsApp.
# (Comment forwarding is handled separately by omni_ai_comments.rb.)
#
# ENV vars required:
#   OMNI_AI_WEBHOOK_URL    — e.g. https://ai.shoev.co.il/webhooks/chatwoot
#   OMNI_AI_WEBHOOK_TOKEN  — shared token (sent as webhook secret for X-Chatwoot-Signature)
#   OMNI_AI_WEBHOOK_ACCOUNT_ID — Chatwoot account ID to register webhook for
#   OMNI_AI_WEBHOOK_ENABLED — "true" to enable (default: "false")
#
# Safe for restarts: checks if webhook already exists before creating.
# ═══════════════════════════════════════════════════════════════════════════════

Rails.application.config.after_initialize do
  next unless ENV.fetch('OMNI_AI_WEBHOOK_ENABLED', 'false') == 'true'

  url        = ENV.fetch('OMNI_AI_WEBHOOK_URL', '').strip
  account_id = ENV.fetch('OMNI_AI_WEBHOOK_ACCOUNT_ID', '').strip
  token      = ENV.fetch('OMNI_AI_WEBHOOK_TOKEN', '').strip

  if url.blank? || account_id.blank?
    Rails.logger.warn('[OmniAI Webhook] OMNI_AI_WEBHOOK_URL or OMNI_AI_WEBHOOK_ACCOUNT_ID not set, skipping.')
    next
  end

  begin
    account = Account.find_by(id: account_id)
    unless account
      Rails.logger.warn("[OmniAI Webhook] Account #{account_id} not found, skipping.")
      next
    end

    desired_subs = %w[message_created message_updated conversation_created conversation_status_changed conversation_updated]

    existing = account.webhooks.find_by(url: url)
    if existing
      Rails.logger.info("[OmniAI Webhook] Webhook already exists (id=#{existing.id}), ensuring config is up to date.")
      unless (desired_subs - existing.subscriptions).empty?
        existing.update!(subscriptions: desired_subs)
        Rails.logger.info("[OmniAI Webhook] Updated subscriptions to #{desired_subs.join(', ')}")
      end
      # Ensure secret is set (may be missing if webhook was created before secret column migration)
      if token.present?
        existing.update_column(:secret, token) rescue nil
        Rails.logger.info("[OmniAI Webhook] Ensured webhook secret is set.")
      end
      next
    end

    webhook = account.webhooks.create!(
      url: url,
      subscriptions: desired_subs
    )

    # Override the auto-generated secret with our shared token if provided
    webhook.update_column(:secret, token) if token.present?

    Rails.logger.info("[OmniAI Webhook] Created webhook id=#{webhook.id} url=#{url} for account #{account_id}")
  rescue StandardError => e
    Rails.logger.error("[OmniAI Webhook] Failed to register webhook: #{e.message}")
  end
end
