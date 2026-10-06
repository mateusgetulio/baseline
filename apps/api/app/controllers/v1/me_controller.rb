module V1
  class MeController < BaseController
    def show
      render json: {
        key_id: current_key.id,
        sandbox: { id: current_key.sandbox.id, name: current_key.sandbox.name },
        permissions: current_key.permissions
      }
    end
  end
end
