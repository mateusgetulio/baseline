class Availability
  STEP = 30.minutes

  def initialize(facility, date, duration_minutes, now: Time.current)
    @facility = facility
    @date = date
    @duration = duration_minutes.minutes
    @now = now
  end

  def as_json(*)
    {
      facility_id: @facility.id,
      date: @date.iso8601,
      time_zone: @facility.time_zone,
      duration_minutes: @duration.in_minutes.to_i,
      courts: courts.map { |court| court_json(court) }
    }
  end

  private

  def courts
    @courts ||= @facility.courts.order(:id).to_a
  end

  def window
    @window ||= @facility.opening_window(@date).map(&:utc)
  end

  def busy_by_court
    @busy_by_court ||= begin
      ids = courts.map(&:id)
      holds = Hold.active_at(@now).where(court_id: ids).overlapping(*window)
      bookings = Booking.confirmed.where(court_id: ids).overlapping(*window)
      (holds.to_a + bookings.to_a).group_by(&:court_id)
    end
  end

  def court_json(court)
    busy = busy_by_court.fetch(court.id, [])
    slots = []
    starts_at = window.first
    while starts_at + @duration <= window.last
      ends_at = starts_at + @duration
      if starts_at >= @now && busy.none? { |b| b.starts_at < ends_at && b.ends_at > starts_at }
        slots << {
          starts_at: ApiJson.instant(starts_at, @facility),
          ends_at: ApiJson.instant(ends_at, @facility),
          price_cents: court.price_cents_for(starts_at, ends_at),
          currency: court.currency
        }
      end
      starts_at += STEP
    end
    { court_id: court.id, name: court.name, sport: court.sport, slots: slots }
  end
end
