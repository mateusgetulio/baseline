module V1
  class BaseController < ApplicationController
    CLIENTS = %w[curl console mcp].freeze

    before_action :authenticate!

    private

    attr_reader :current_key

    def process_action(*)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      super
    ensure
      log_request(started)
    end

    def authenticate!
      token = request.authorization.to_s.delete_prefix("Bearer ").strip
      @current_key = ApiKey.authenticate(token)
      raise ApiError.unauthorized unless @current_key
    end

    def require_permission!(permission)
      raise ApiError.permission_denied(permission) unless current_key.permitted?(permission)
    end

    def log_request(started)
      return unless current_key

      RequestLog.create!(
        sandbox_id: current_key.sandbox_id,
        api_key_id: current_key.id,
        http_method: request.method,
        path: request.fullpath.first(1024),
        status: response.status,
        error_code: @error_code,
        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
        replayed: @replayed == true,
        client: client_label
      )
    rescue StandardError => e
      Rails.logger.error("request log failed: #{e.class}: #{e.message}")
    end

    def client_label
      declared = request.headers["X-Client"].to_s.downcase
      return declared if CLIENTS.include?(declared)

      "curl" if request.user_agent.to_s.start_with?("curl/")
    end

    def find_facility!(id)
      Facility.find_by(id: id, sandbox_id: current_key.sandbox_id) || raise(ApiError.not_found)
    end

    def find_court!(id)
      Court.joins(:facility).where(facilities: { sandbox_id: current_key.sandbox_id }).find_by(id: id) ||
        raise(ApiError.not_found("Court #{id} does not exist or is not visible to this key."))
    end

    def find_customer!(id)
      Customer.find_by(id: id, sandbox_id: current_key.sandbox_id) ||
        raise(ApiError.not_found("Customer #{id} does not exist or is not visible to this key."))
    end

    def paginate(scope)
      limit = params[:limit].nil? ? 50 : Params.integer(params[:limit])
      raise ApiError.validation([ { name: "limit", reason: "must be an integer from 1 to 100" } ]) unless limit&.between?(1, 100)

      after_id = decode_cursor(params[:cursor])
      rows = scope.where("#{scope.table_name}.id > ?", after_id).order(:id).limit(limit + 1).to_a
      next_cursor = rows.size > limit ? Base64.urlsafe_encode64("id:#{rows[limit - 1].id}", padding: false) : nil
      [ rows.first(limit), next_cursor ]
    end

    def decode_cursor(cursor)
      return 0 if cursor.blank?

      decoded = Base64.urlsafe_decode64(cursor.to_s)
      raise ArgumentError unless decoded.match?(/\Aid:\d+\z/)

      decoded.delete_prefix("id:").to_i
    rescue ArgumentError
      raise ApiError.validation([ { name: "cursor", reason: "is not a cursor returned by this API" } ])
    end

    def idempotently
      key = request.headers["Idempotency-Key"].to_s
      if key.blank?
        raise ApiError.new(status: 400, code: "idempotency_key_missing", title: "Idempotency-Key header is required",
                           detail: "Every mutation needs a unique Idempotency-Key header.")
      end
      raise ApiError.validation([ { name: "Idempotency-Key", reason: "must be at most 255 characters" } ]) if key.length > 255

      raise ApiError.validation([ { name: "path", reason: "must be at most 255 characters" } ]) if request.fullpath.length > 255

      fingerprint = request_fingerprint
      record, claimed = IdempotencyRecord.claim(api_key_id: current_key.id, key: key, fingerprint: fingerprint)
      return execute_and_store(record) { yield } if claimed

      if record && !record.same_request?(fingerprint)
        raise ApiError.conflict("idempotency_key_reused", "Idempotency-Key was already used for a different request",
                                "Use a new Idempotency-Key for a different method, path or body.")
      end
      if record.nil? || record.state == "in_progress"
        raise ApiError.conflict("idempotency_in_progress", "A request with this Idempotency-Key is still running",
                                "Retry after the first request finishes to receive its stored response.")
      end
      replay(record)
    end

    def execute_and_store(record)
      status, = ReadCommitted.transaction do
        result = yield
        record.update!(state: "completed", response_status: result[0], response_body: result[1].to_json)
        result
      end
      [ status, record.response_body, false ]
    rescue ApiError => e
      record.update!(state: "completed", response_status: e.status, response_body: problem_body(e).to_json)
      raise
    rescue StandardError
      record.destroy
      raise
    end

    def replay(record)
      [ record.response_status, record.response_body, true ]
    end

    def render_idempotent(result)
      status, body, replayed = result
      @replayed = replayed
      response.headers["Idempotent-Replayed"] = "true" if replayed
      if status >= 400
        @error_code = JSON.parse(body)["code"]
        render body: body, status: status, content_type: "application/problem+json"
      else
        render body: body, status: status, content_type: "application/json"
      end
    end

    def request_fingerprint
      {
        request_method: request.method,
        request_path: request.fullpath,
        body_digest: OpenSSL::Digest::SHA256.hexdigest(canonical_json(request.request_parameters))
      }
    end

    def canonical_json(value)
      case value
      when Hash then "{" + value.keys.map(&:to_s).sort.map { |k| "#{k.to_json}:#{canonical_json(value[k])}" }.join(",") + "}"
      when Array then "[" + value.map { |v| canonical_json(v) }.join(",") + "]"
      else value.to_json
      end
    end
  end
end
