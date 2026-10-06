module V1
  class FacilitiesController < BaseController
    before_action -> { require_permission!("availability.read") }

    def index
      rows, next_cursor = paginate(Facility.where(sandbox_id: current_key.sandbox_id))
      render json: { data: rows.map { |f| ApiJson.facility(f) }, next_cursor: next_cursor }
    end
  end
end
