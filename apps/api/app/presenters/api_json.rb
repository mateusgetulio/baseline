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
end
