# frozen_string_literal: true

class Api::V1::Accounts::CommentPostsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def index
    sort = params[:sort_by]&.to_s == 'post_date' ? :ordered_by_post_date : :ordered_by_latest_comment
    @comment_posts = Current.account.comment_posts
                            .for_inbox(params[:inbox_id])
                            .for_platform(params[:platform])
                            .public_send(sort)
                            .page(params[:page] || 1)
                            .per(20)

    render json: {
      data: {
        meta: { total_count: @comment_posts.total_count, page: @comment_posts.current_page },
        payload: @comment_posts.map { |post| serialize_post(post) }
      }
    }
  end

  def show
    @comment_post = Current.account.comment_posts.find(params[:id])
    conversations = @comment_post.conversations
                                 .includes(:contact, :inbox, :messages)
                                 .order(last_activity_at: :desc)
                                 .limit(50)

    render json: {
      data: {
        post: serialize_post(@comment_post),
        conversations: conversations.map { |c| serialize_conversation(c) }
      }
    }
  end

  # Called by omni-ai when a comment is processed — creates/updates post record
  def upsert
    post = Current.account.comment_posts.find_or_initialize_by(post_id: params[:post_id])
    post.assign_attributes(upsert_params)
    post.last_comment_at = Time.current
    post.conversations_count = (post.conversations_count || 0) + 1 if post.new_record? || params[:increment_count]
    post.save!

    render json: { data: serialize_post(post) }, status: post.previously_new_record? ? :created : :ok
  end

  private

  def check_authorization
    authorize(Current.account) if defined?(authorize)
  end

  def upsert_params
    params.permit(
      :inbox_id, :platform, :post_id, :page_id,
      :post_text, :post_media_url, :post_media_type,
      :post_permalink, :post_created_at
    )
  end

  def serialize_post(post)
    {
      id: post.id,
      platform: post.platform,
      post_id: post.post_id,
      page_id: post.page_id,
      post_text: post.post_text&.truncate(200),
      post_media_url: post.post_media_url,
      post_media_type: post.post_media_type,
      post_permalink: post.post_permalink,
      post_created_at: post.post_created_at&.iso8601,
      conversations_count: post.conversations_count,
      last_comment_at: post.last_comment_at&.iso8601,
      inbox_id: post.inbox_id,
      created_at: post.created_at.iso8601,
      updated_at: post.updated_at.iso8601
    }
  end

  def serialize_conversation(conv)
    {
      id: conv.id,
      status: conv.status,
      contact: {
        id: conv.contact&.id,
        name: conv.contact&.name,
        thumbnail: conv.contact&.avatar_url
      },
      additional_attributes: conv.additional_attributes,
      last_activity_at: conv.last_activity_at&.to_i,
      created_at: conv.created_at.iso8601,
      messages_count: conv.messages.count,
      last_message: conv.messages.order(created_at: :desc).first&.then { |m|
        { content: m.content&.truncate(100), created_at: m.created_at.iso8601, message_type: m.message_type }
      }
    }
  end
end
