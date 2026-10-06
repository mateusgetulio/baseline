module V1
  class AvailabilityController < BaseController
    before_action -> { require_permission!("availability.read") }

    def show
      errors = []
      errors << { name: "facility_id", reason: "is required" } if params[:facility_id].blank?
      date = Params.date(params[:date])
      errors << { name: "date", reason: "must be a calendar date in YYYY-MM-DD form, from yesterday to two years ahead" } unless date
      duration = Params.integer(params[:duration_minutes])
      unless duration && Params.valid_duration_minutes?(duration)
        errors << { name: "duration_minutes", reason: Params::DURATION_RULE }
      end
      raise ApiError.validation(errors) if errors.any?

      facility = find_facility!(params[:facility_id])
      render json: Availability.new(facility, date, duration).as_json
    end
  end
end
