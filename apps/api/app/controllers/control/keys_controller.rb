module Control
  class KeysController < BaseController
    def create
      key, plaintext = ApiKey.issue!(sandbox: sandbox, permissions: requested_permissions)
      render json: key_json(key, plaintext), status: :created
    end

    def destroy
      key = sandbox.api_keys.find_by(id: params[:id]) || raise(ApiError.not_found)
      key.update!(revoked_at: Time.current) unless key.revoked?
      render json: key_json(key)
    end
  end
end
