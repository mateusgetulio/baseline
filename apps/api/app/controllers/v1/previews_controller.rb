module V1
  class PreviewsController < BaseController
    before_action -> { require_permission!("bookings.read") }

    def create
      hold = Hold.find_by(id: params[:hold_id], api_key_id: current_key.id) || raise(ApiError.not_found)
      unless hold.active?
        raise ApiError.conflict("hold_not_active", "Hold is not active",
                                "Hold #{hold.id} is #{hold.effective_status} and cannot be previewed.")
      end

      court = hold.court
      token, plaintext = PreviewToken.issue!(hold: hold, price_cents: court.price_cents_for(hold.starts_at, hold.ends_at),
                                             currency: court.currency)
      render json: ApiJson.preview(hold, token, plaintext), status: :created
    end
  end
end
