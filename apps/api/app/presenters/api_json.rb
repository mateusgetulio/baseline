module ApiJson
  module_function

  def instant(time, facility)
    time.in_time_zone(facility.zone).iso8601
  end

  def facility(facility)
    { id: facility.id, name: facility.name, time_zone: facility.time_zone }
  end

  def court(court)
    {
      id: court.id,
      facility_id: court.facility_id,
      name: court.name,
      sport: court.sport,
      hourly_rate_cents: court.hourly_rate_cents,
      currency: court.currency
    }
  end

  def hold(hold, now = Time.current)
    facility = hold.court.facility
    {
      id: hold.id,
      court_id: hold.court_id,
      customer_id: hold.customer_id,
      starts_at: instant(hold.starts_at, facility),
      ends_at: instant(hold.ends_at, facility),
      expires_at: instant(hold.expires_at, facility),
      status: hold.effective_status(now)
    }
  end

  def booking(booking)
    facility = booking.court.facility
    {
      id: booking.id,
      hold_id: booking.hold_id,
      court_id: booking.court_id,
      customer_id: booking.customer_id,
      starts_at: instant(booking.starts_at, facility),
      ends_at: instant(booking.ends_at, facility),
      price_cents: booking.price_cents,
      currency: booking.currency,
      status: booking.status
    }
  end

  def preview(hold, token, plaintext)
    court = hold.court
    facility = court.facility
    {
      hold_id: hold.id,
      facility: facility(facility),
      court: { id: court.id, name: court.name, sport: court.sport },
      customer: { id: hold.customer.id, name: hold.customer.name },
      starts_at: instant(hold.starts_at, facility),
      ends_at: instant(hold.ends_at, facility),
      price_cents: token.price_cents,
      currency: token.currency,
      summary: summary(hold, token),
      preview_token: plaintext,
      preview_token_expires_at: instant(token.expires_at, facility)
    }
  end

  def summary(hold, token)
    court = hold.court
    facility = court.facility
    starts_at = hold.starts_at.in_time_zone(facility.zone)
    ends_at = hold.ends_at.in_time_zone(facility.zone)
    minutes = ((hold.ends_at - hold.starts_at) / 60).round
    "Book #{court.name} (#{court.sport}) at #{facility.name} for #{hold.customer.name} " \
      "on #{starts_at.strftime('%A, %B %-d, %Y')}, from #{starts_at.strftime('%H:%M')} to #{ends_at.strftime('%H:%M')} " \
      "(#{offsets(starts_at, ends_at)}, #{facility.time_zone}). " \
      "#{minutes} minutes, total #{money(token.price_cents, token.currency)}."
  end

  def offsets(starts_at, ends_at)
    return "UTC#{starts_at.formatted_offset}" if starts_at.utc_offset == ends_at.utc_offset

    "starts at UTC#{starts_at.formatted_offset}, ends at UTC#{ends_at.formatted_offset}"
  end

  def money(cents, currency)
    format("%s %d.%02d", currency, cents / 100, cents % 100)
  end
end
