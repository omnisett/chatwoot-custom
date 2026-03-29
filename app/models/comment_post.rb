# frozen_string_literal: true

# == Schema Information
#
# Table name: comment_posts
#
#  id                  :bigint           not null, primary key
#  account_id          :bigint           not null
#  inbox_id            :bigint           not null
#  platform            :string           not null
#  post_id             :string           not null
#  page_id             :string
#  post_text           :text
#  post_media_url      :string
#  post_media_type     :string
#  post_permalink      :string
#  post_created_at     :datetime
#  conversations_count :integer          default(0), not null
#  last_comment_at     :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
class CommentPost < ApplicationRecord
  belongs_to :account
  belongs_to :inbox

  validates :post_id, presence: true, uniqueness: { scope: :account_id }
  validates :platform, presence: true, inclusion: { in: %w[facebook instagram] }

  scope :ordered_by_latest_comment, -> { order(last_comment_at: :desc) }
  scope :ordered_by_post_date, -> { order(post_created_at: :desc) }
  scope :for_platform, ->(platform) { where(platform: platform) if platform.present? }
  scope :for_inbox, ->(inbox_id) { where(inbox_id: inbox_id) if inbox_id.present? }

  # Find conversations that belong to this post via additional_attributes.post_id
  def conversations
    account.conversations.where("additional_attributes->>'post_id' = ?", post_id)
  end

  # Recompute aggregate counters from actual conversations
  def recount!
    convs = conversations
    update!(
      conversations_count: convs.count,
      last_comment_at: convs.maximum(:created_at) || created_at
    )
  end
end
