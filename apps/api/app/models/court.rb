class Court < ApplicationRecord
  belongs_to :facility

  def price_cents_for(starts_at, ends_at)
    seconds = (ends_at - starts_at).to_i
    Rational(hourly_rate_cents * seconds, 3600).round
  end
end
