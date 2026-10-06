class ApiKey < ApplicationRecord
  PERMISSIONS = %w[availability.read holds.write bookings.read bookings.write].freeze
  TOKEN_FORMAT = /\Abl_test_([a-z0-9]{12})_([A-Za-z0-9]{32})\z/

  belongs_to :sandbox

  validate :permissions_are_known

  def self.issue!(sandbox:, permissions: PERMISSIONS)
    lookup = SecureRandom.hex(6)
    secret = SecureRandom.alphanumeric(32)
    key = create!(sandbox: sandbox, lookup: lookup, secret_digest: digest(secret), permissions: permissions)
    [ key, "bl_test_#{lookup}_#{secret}" ]
  end

  def self.authenticate(token)
    match = TOKEN_FORMAT.match(token.to_s)
    return unless match

    key = find_by(lookup: match[1])
    return unless key && key.revoked_at.nil?
    return unless ActiveSupport::SecurityUtils.secure_compare(key.secret_digest, digest(match[2]))

    key
  end

  def self.digest(secret)
    OpenSSL::Digest::SHA256.hexdigest(secret)
  end

  def permitted?(permission)
    permissions.include?(permission)
  end

  def revoked?
    revoked_at.present?
  end

  private

  def permissions_are_known
    unless permissions.is_a?(Array) && permissions.any? && (permissions - PERMISSIONS).empty?
      errors.add(:permissions, "must be a non-empty subset of #{PERMISSIONS.join(', ')}")
    end
  end
end
