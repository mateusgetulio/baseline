class PreviewToken < ApplicationRecord
  TTL = 5.minutes
  TOKEN_FORMAT = /\Abl_preview_[A-Za-z0-9]{40}\z/

  belongs_to :hold
  belongs_to :customer

  def self.issue!(hold:, price_cents:, currency:, now: Time.current)
    plaintext = "bl_preview_#{SecureRandom.alphanumeric(40)}"
    record = create!(hold: hold, customer_id: hold.customer_id, token_digest: digest(plaintext),
                     price_cents: price_cents, currency: currency, expires_at: [ now + TTL, hold.expires_at ].min)
    [ record, plaintext ]
  end

  def self.find_by_plaintext(plaintext)
    return unless plaintext.is_a?(String) && plaintext.match?(TOKEN_FORMAT)

    find_by(token_digest: digest(plaintext))
  end

  def self.digest(plaintext)
    OpenSSL::Digest::SHA256.hexdigest(plaintext)
  end
end
