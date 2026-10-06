class ApiError < StandardError
  attr_reader :status, :code, :title, :invalid_params

  def initialize(status:, code:, title:, detail: nil, invalid_params: nil)
    @status = status
    @code = code
    @title = title
    @invalid_params = invalid_params
    super(detail || title)
  end

  def self.unauthorized
    new(status: 401, code: "unauthorized", title: "Missing or invalid API key",
        detail: "Send a valid key as 'Authorization: Bearer <key>'.")
  end

  def self.permission_denied(permission)
    new(status: 403, code: "permission_denied", title: "Key lacks a required permission",
        detail: "This request needs the '#{permission}' permission.")
  end

  def self.not_found(detail = "The resource does not exist or is not visible to this key.")
    new(status: 404, code: "not_found", title: "Not found", detail: detail)
  end

  def self.validation(invalid_params)
    new(status: 422, code: "validation_failed", title: "The request has invalid parameters",
        detail: invalid_params.map { |p| "#{p[:name]} #{p[:reason]}" }.join("; "), invalid_params: invalid_params)
  end

  def self.conflict(code, title, detail = nil)
    new(status: 409, code: code, title: title, detail: detail)
  end
end
