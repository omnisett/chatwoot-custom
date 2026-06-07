require 'rails_helper'

RSpec.describe 'Webhooks::InstagramController', type: :request do
  describe 'GET /webhooks/verify' do
    it 'returns 401 when valid params are not present' do
      get '/webhooks/instagram/verify'
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 401 when invalid params' do
      with_modified_env IG_VERIFY_TOKEN: '123456' do
        get '/webhooks/instagram/verify', params: { 'hub.challenge' => '123456', 'hub.mode' => 'subscribe', 'hub.verify_token' => 'invalid' }
        expect(response).to have_http_status(:not_found)
      end
    end

    it 'returns challenge when valid params' do
      with_modified_env IG_VERIFY_TOKEN: '123456' do
        get '/webhooks/instagram/verify', params: { 'hub.challenge' => '123456', 'hub.mode' => 'subscribe', 'hub.verify_token' => '123456' }
        expect(response.body).to include '123456'
      end
    end
  end

  describe 'POST /webhooks/instagram' do
    let!(:dm_params) { build(:instagram_message_create_event).with_indifferent_access }

    it 'call the instagram events job with the params' do
      allow(Webhooks::InstagramEventsJob).to receive(:perform_later)
      expect(Webhooks::InstagramEventsJob).to receive(:perform_later)

      instagram_params = dm_params.merge(object: 'instagram')
      post '/webhooks/instagram', params: instagram_params
      expect(response).to have_http_status(:success)
    end

    it 'forwards instagram comment events to Omni AI without requiring a DM event' do
      comment_params = {
        object: 'instagram',
        entry: [
          {
            id: 'ig_123',
            changes: [
              {
                field: 'comments',
                value: {
                  id: 'comment_123',
                  text: 'price?',
                  from: { id: 'user_123', username: 'client_ig' },
                  media: { id: 'media_123' }
                }
              }
            ]
          }
        ]
      }.with_indifferent_access

      allow(OmniAi::CommentForwarder).to receive(:forward).and_return({ enqueued: true, reason: 'enqueued' })
      allow(Webhooks::InstagramEventsJob).to receive(:perform_later)

      post '/webhooks/instagram', params: comment_params

      expect(response).to have_http_status(:success)
      expect(OmniAi::CommentForwarder).to have_received(:forward).with(
        platform: 'instagram',
        entries: comment_params[:entry],
        instagram_id: 'ig_123'
      )
      expect(Webhooks::InstagramEventsJob).not_to have_received(:perform_later)
    end

    context 'when processing echo events' do
      let!(:echo_params) { build(:instagram_story_mention_event_with_echo).with_indifferent_access }

      it 'delays processing for echo events by 2 seconds' do
        job_double = class_double(Webhooks::InstagramEventsJob)
        allow(Webhooks::InstagramEventsJob).to receive(:set).with(wait: 2.seconds).and_return(job_double)
        allow(job_double).to receive(:perform_later)

        instagram_params = echo_params.merge(object: 'instagram')
        post '/webhooks/instagram', params: instagram_params
        expect(response).to have_http_status(:success)
        expect(Webhooks::InstagramEventsJob).to have_received(:set).with(wait: 2.seconds)
        expect(job_double).to have_received(:perform_later)
      end
    end
  end
end
