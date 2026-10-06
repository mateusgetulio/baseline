class IdempotencyRecord < ApplicationRecord
  belongs_to :api_key

  def self.claim(api_key_id:, key:, fingerprint:)
    now = Time.current
    sql = sanitize_sql_array([
      "INSERT IGNORE INTO idempotency_records " \
      "(api_key_id, `key`, request_method, request_path, body_digest, state, created_at, updated_at) " \
      "VALUES (?, ?, ?, ?, ?, 'in_progress', ?, ?)",
      api_key_id, key, fingerprint[:request_method], fingerprint[:request_path], fingerprint[:body_digest], now, now
    ])
    claimed = connection.exec_update(sql) == 1
    [ find_by(api_key_id: api_key_id, key: key), claimed ]
  end

  def same_request?(fingerprint)
    request_method == fingerprint[:request_method] &&
      request_path == fingerprint[:request_path] &&
      body_digest == fingerprint[:body_digest]
  end
end
