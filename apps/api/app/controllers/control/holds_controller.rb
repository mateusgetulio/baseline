module Control
  class HoldsController < BaseController
    def expire
      hold = ReadCommitted.transaction do
        found = Hold.lock.find_by(id: params[:hold_id], sandbox_id: sandbox.id) || raise(ApiError.not_found)
        unless found.active?
          raise ApiError.conflict("hold_not_active", "Hold is not active",
                                  "Hold #{found.id} is #{found.effective_status} and cannot be expired.")
        end
        found.update!(status: "expired", expires_at: Time.current)
        found
      end
      render json: ApiJson.hold(hold)
    end
  end
end
