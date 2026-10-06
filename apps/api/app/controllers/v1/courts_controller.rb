module V1
  class CourtsController < BaseController
    before_action -> { require_permission!("availability.read") }

    def index
      facility = find_facility!(params[:facility_id])
      rows, next_cursor = paginate(facility.courts)
      render json: { data: rows.map { |c| ApiJson.court(c) }, next_cursor: next_cursor }
    end
  end
end
