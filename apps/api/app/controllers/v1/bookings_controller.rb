module V1
  class BookingsController < BaseController
    before_action -> { require_permission!("bookings.write") }

    def create
      render_idempotent(idempotently { [ 201, ApiJson.booking(confirm_booking) ] })
    end

    private

    def confirm_booking
      Bookings::Confirm.new(api_key: current_key, plaintext_token: request.request_parameters["preview_token"]).call
    end
  end
end
