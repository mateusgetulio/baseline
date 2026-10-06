class Booking < ApplicationRecord
  belongs_to :sandbox
  belongs_to :court
  belongs_to :customer
  belongs_to :hold
  belongs_to :api_key

  scope :confirmed, -> { where(status: "confirmed") }
  scope :overlapping, ->(starts_at, ends_at) { where("starts_at < ? AND ends_at > ?", ends_at, starts_at) }
end
