module Holds
  class Create
    def initialize(api_key:, court:, customer:, starts_at:, ends_at:, ttl_seconds:, now: Time.current)
      @api_key = api_key
      @court = court
      @customer = customer
      @starts_at = starts_at
      @ends_at = ends_at
      @ttl_seconds = ttl_seconds
      @now = now
    end

    def call
      validate_window!

      ReadCommitted.transaction do
        ApiKey.lock.find(@api_key.id)
        Court.lock.find(@court.id)

        if Hold.active_at(@now).where(api_key_id: @api_key.id).count >= Hold::MAX_ACTIVE_PER_KEY
          raise ApiError.conflict("hold_limit_reached", "Active hold limit reached",
                                  "A key can have at most #{Hold::MAX_ACTIVE_PER_KEY} active holds. Release or book one first.")
        end
        if slot_taken?
          raise ApiError.conflict("slot_unavailable", "Slot is not available",
                                  "The court is already held or booked for part of this window.")
        end

        Hold.create!(
          sandbox_id: @api_key.sandbox_id, court: @court, customer: @customer, api_key: @api_key,
          starts_at: @starts_at, ends_at: @ends_at, expires_at: @now + @ttl_seconds, status: "active"
        )
      end
    end

    private

    def slot_taken?
      Hold.active_at(@now).where(court_id: @court.id).overlapping(@starts_at, @ends_at).exists? ||
        Booking.confirmed.where(court_id: @court.id).overlapping(@starts_at, @ends_at).exists?
    end

    def validate_window!
      errors = []
      minutes = (@ends_at - @starts_at) / 60
      unless minutes == minutes.to_i && Params.valid_duration_minutes?(minutes.to_i)
        errors << { name: "ends_at", reason: "must be 30 to 240 minutes after starts_at, in steps of 30" }
      end
      errors << { name: "starts_at", reason: "must be in the future" } if @starts_at <= @now
      facility = @court.facility
      opens_at, closes_at = facility.opening_window(facility.local_date_of(@starts_at))
      unless @starts_at >= opens_at && @ends_at <= closes_at
        errors << { name: "starts_at", reason: "window must fall within the facility's opening hours" }
      end
      unless ((@starts_at - opens_at).to_i % Availability::STEP.to_i).zero?
        errors << { name: "starts_at", reason: "must start on the 30 minute slot grid returned by availability" }
      end
      raise ApiError.validation(errors) if errors.any?
    end
  end
end
