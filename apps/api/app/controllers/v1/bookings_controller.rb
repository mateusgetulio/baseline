module V1
  class BookingsController < BaseController
    SIMULATIONS = %w[drop_response_after_commit].freeze

    before_action -> { require_permission!("bookings.write") }
    before_action :check_simulation!

    def create
      result = idempotently { [ 201, ApiJson.booking(confirm_booking) ] }
      return render_idempotent(result) unless drop_response?(result)

      raise ApiError.new(status: 502, code: "simulated_lost_response", title: "Simulated lost response",
                         detail: "The booking was committed and its 201 stored under your Idempotency-Key. " \
                                 "Retry with the same key to receive it.")
    end

    private

    def confirm_booking
      Bookings::Confirm.new(api_key: current_key, plaintext_token: request.request_parameters["preview_token"]).call
    end

    def simulation
      request.headers["X-Sandbox-Simulate"]
    end

    def check_simulation!
      return if simulation.nil?

      unless SIMULATIONS.include?(simulation)
        raise ApiError.validation([ { name: "X-Sandbox-Simulate", reason: "must be one of #{SIMULATIONS.join(', ')}" } ])
      end
      return if current_key.sandbox_key?

      raise ApiError.validation([ { name: "X-Sandbox-Simulate", reason: "is only accepted on sandbox keys" } ])
    end

    def drop_response?(result)
      status, _body, replayed = result
      simulation == "drop_response_after_commit" && !replayed && status == 201
    end
  end
end
