class Webhooks::InstagramController < ActionController::API
  include MetaTokenVerifyConcern

  def events
    Rails.logger.info('Instagram webhook received events')
    if params['object'].casecmp('instagram').zero?
      unsafe_params = params.to_unsafe_h
      entry_params = unsafe_params[:entry] || unsafe_params['entry'] || []

      # ── Omni-AI: forward comment events to AI backend ──
      if OmniAi::CommentForwarder.contains_ig_comments?(entry_params)
        ig_id = OmniAi::CommentForwarder.extract_page_id(entry_params)
        result = OmniAi::CommentForwarder.forward(
          platform: 'instagram',
          entries: entry_params,
          instagram_id: ig_id
        )
        if result[:enqueued]
          Rails.logger.info("[OmniAi] Enqueued Instagram comment webhook forward (ig_id=#{ig_id})")
        else
          Rails.logger.warn("[OmniAi] Skipped Instagram comment webhook forward (ig_id=#{ig_id}, reason=#{result[:reason]})")
        end
      end

      # ── Original Chatwoot DM flow (unchanged) ──
      if contains_messaging_event?(entry_params)
        if contains_echo_event?(entry_params)
          # Add delay to prevent race condition where echo arrives before send message API completes
          # This avoids duplicate messages when echo comes early during API processing
          ::Webhooks::InstagramEventsJob.set(wait: 2.seconds).perform_later(entry_params)
        else
          ::Webhooks::InstagramEventsJob.perform_later(entry_params)
        end
      end

      render json: :ok
    else
      Rails.logger.warn("Message is not received from the instagram webhook event: #{params['object']}")
      head :unprocessable_entity
    end
  end

  private

  def contains_messaging_event?(entry_params)
    return false unless entry_params.is_a?(Array)

    entry_params.any? do |entry|
      entry[:messaging].present? ||
        entry['messaging'].present? ||
        entry[:standby].present? ||
        entry['standby'].present?
    end
  end

  def contains_echo_event?(entry_params)
    return false unless entry_params.is_a?(Array)

    entry_params.any? do |entry|
      # Check messaging array for echo events
      messaging_events = entry[:messaging] || entry['messaging'] || []
      messaging_events.any? do |messaging|
        message = messaging[:message] || messaging['message'] || {}
        message[:is_echo].present? || message['is_echo'].present?
      end
    end
  end

  def valid_token?(token)
    # Validates against both IG_VERIFY_TOKEN (Instagram channel via Facebook page) and
    # INSTAGRAM_VERIFY_TOKEN (Instagram channel via direct Instagram login)
    token == GlobalConfigService.load('IG_VERIFY_TOKEN', '') ||
      token == GlobalConfigService.load('INSTAGRAM_VERIFY_TOKEN', '')
  end
end
