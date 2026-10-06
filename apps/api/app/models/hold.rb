class Hold < ApplicationRecord
  MAX_ACTIVE_PER_KEY = 3

  belongs_to :sandbox
  belongs_to :court
  belongs_to :customer
  belongs_to :api_key

  scope :active_at, ->(now) { where(status: "active").where("expires_at > ?", now) }
  scope :overlapping, ->(starts_at, ends_at) { where("starts_at < ? AND ends_at > ?", ends_at, starts_at) }

  def effective_status(now = Time.current)
    status == "active" && expires_at <= now ? "expired" : status
  end

  def active?(now = Time.current)
    effective_status(now) == "active"
  end
end
