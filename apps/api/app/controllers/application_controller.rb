class ApplicationController < ActionController::API
  PROBLEM_TYPE_BASE = "https://baseline.test/docs/errors#".freeze

  wrap_parameters false

  rescue_from StandardError, with: :render_internal_error
  rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_malformed_request
  rescue_from ApiError, with: :render_problem

  def route_not_found
    raise ApiError.not_found("No route matches #{request.method} #{request.path}.")
  end

  private

  def problem_body(error)
    body = {
      type: "#{PROBLEM_TYPE_BASE}#{error.code}",
      title: error.title,
      status: error.status,
      detail: error.message,
      code: error.code
    }
    body[:invalid_params] = error.invalid_params if error.invalid_params
    body
  end

  def render_problem(error)
    @error_code = error.code
    render json: problem_body(error), status: error.status, content_type: "application/problem+json"
  end

  def render_malformed_request(_error)
    render_problem(ApiError.new(status: 400, code: "malformed_request", title: "The request body is not valid JSON"))
  end

  def render_internal_error(error)
    Rails.logger.error("#{error.class}: #{error.message}\n#{error.backtrace&.first(15)&.join("\n")}")
    render_problem(ApiError.new(status: 500, code: "internal_error", title: "Unexpected server error"))
  end
end
