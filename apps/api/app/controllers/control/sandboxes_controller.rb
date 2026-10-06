module Control
  class SandboxesController < BaseController
    def create
      name = request.request_parameters["name"].presence || "Sandbox"
      raise ApiError.validation([ { name: "name", reason: "must be a string of at most 100 characters" } ]) unless name.is_a?(String) && name.length <= 100

      created, key, plaintext = Sandboxes::Provision.call(name: name, permissions: requested_permissions)
      render json: { sandbox: { id: created.id, name: created.name }, key: key_json(key, plaintext) }, status: :created
    end

    def reset
      Sandboxes::Reset.call(sandbox)
      render json: { sandbox: { id: sandbox.id, name: sandbox.name }, reset_at: Time.current.utc.iso8601 }
    end
  end
end
