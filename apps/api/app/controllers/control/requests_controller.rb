module Control
  class RequestsController < BaseController
    def index
      logs = RequestLog.where(sandbox_id: sandbox.id).order(id: :desc).limit(50)
      render json: {
        data: logs.map do |log|
          {
            id: log.id, key_id: log.api_key_id, method: log.http_method, path: log.path, status: log.status,
            code: log.error_code, replayed: log.replayed, client: log.client, duration_ms: log.duration_ms,
            created_at: log.created_at.utc.iso8601(3)
          }
        end
      }
    end
  end
end
