module Params
  INSTANT_FORMAT = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})\z/
  INSTANT_RULE = "must be an RFC 3339 instant with an offset, like 2026-11-01T10:00:00-04:00".freeze
  DURATION_RULE = "must be a whole number of minutes from 30 to 240, in steps of 30".freeze

  module_function

  def instant(value)
    return unless value.is_a?(String) && value.match?(INSTANT_FORMAT)

    Time.iso8601(value).utc
  rescue ArgumentError
    nil
  end

  def date(value)
    return unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    parsed = Date.iso8601(value)
    parsed if parsed.between?(Date.current - 1, Date.current + 730)
  rescue Date::Error
    nil
  end

  def integer(value)
    return value if value.is_a?(Integer)
    return value.to_i if value.is_a?(String) && value.match?(/\A\d+\z/)

    nil
  end

  def valid_duration_minutes?(minutes)
    minutes.between?(30, 240) && (minutes % 30).zero?
  end
end
