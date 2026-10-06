module Control
  class BaseController < ApplicationController
    before_action :authenticate_admin!

    private

    def authenticate_admin!
      expected = ENV["SANDBOX_ADMIN_TOKEN"].to_s
      given = request.authorization.to_s.delete_prefix("Bearer ").strip
      return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(given, expected)

      raise ApiError.new(status: 401, code: "unauthorized", title: "Missing or invalid sandbox admin token",
                         detail: "Send SANDBOX_ADMIN_TOKEN as 'Authorization: Bearer <token>'.")
    end

    def sandbox
      @sandbox ||= Sandbox.find_by(id: params[:sandbox_id]) || raise(ApiError.not_found)
    end

    def key_json(key, plaintext = nil)
      json = { id: key.id, sandbox_id: key.sandbox_id, permissions: key.permissions, revoked_at: key.revoked_at&.utc&.iso8601 }
      json[:api_key] = plaintext if plaintext
      json
    end

    def requested_permissions
      permissions = request.request_parameters.fetch("permissions", ApiKey::PERMISSIONS)
      unless permissions.is_a?(Array) && permissions.any? && (permissions - ApiKey::PERMISSIONS).empty?
        raise ApiError.validation([ { name: "permissions",
                                      reason: "must be a non-empty list drawn from #{ApiKey::PERMISSIONS.join(', ')}" } ])
      end
      permissions.uniq
    end
  end
end
