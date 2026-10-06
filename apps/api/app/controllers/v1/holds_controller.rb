module V1
  class HoldsController < BaseController
    before_action -> { require_permission!("holds.write") }

    def create
      render_idempotent(idempotently { [ 201, ApiJson.hold(create_hold) ] })
    end

    def destroy
      render_idempotent(idempotently { [ 200, ApiJson.hold(release_hold) ] })
    end

    private

    def create_hold
      body = ActionController::Parameters.new(request.request_parameters).permit(:court_id, :customer_id, :starts_at, :ends_at, :ttl_seconds)
      errors = []
      %i[court_id customer_id starts_at ends_at ttl_seconds].each do |field|
        errors << { name: field.to_s, reason: "is required" } if body[field].blank?
      end
      raise ApiError.validation(errors) if errors.any?

      court = find_court!(body[:court_id])
      customer = find_customer!(body[:customer_id])
      starts_at = Params.instant(body[:starts_at])
      ends_at = Params.instant(body[:ends_at])
      ttl = Params.integer(body[:ttl_seconds])
      errors << { name: "starts_at", reason: Params::INSTANT_RULE } unless starts_at
      errors << { name: "ends_at", reason: Params::INSTANT_RULE } unless ends_at
      errors << { name: "ttl_seconds", reason: "must be an integer from 30 to 600" } unless ttl&.between?(30, 600)
      raise ApiError.validation(errors) if errors.any?

      Holds::Create.new(api_key: current_key, court: court, customer: customer,
                        starts_at: starts_at, ends_at: ends_at, ttl_seconds: ttl).call
    end

    def release_hold
      hold = Hold.lock.find_by(id: params[:id], api_key_id: current_key.id) || raise(ApiError.not_found)
      unless hold.active?
        raise ApiError.conflict("hold_not_active", "Hold is not active",
                                "Hold #{hold.id} is #{hold.effective_status} and cannot be released.")
      end

      hold.update!(status: "released")
      hold
    end
  end
end
