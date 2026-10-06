module ApiHelpers
  def provision(permissions: ApiKey::PERMISSIONS)
    sandbox, _key, token = Sandboxes::Provision.call(name: "Spec sandbox", permissions: permissions)
    [ sandbox, token ]
  end

  def issue_token(sandbox, permissions: ApiKey::PERMISSIONS)
    ApiKey.issue!(sandbox: sandbox, permissions: permissions).last
  end

  def auth(token, idempotency_key: nil, extra: {})
    headers = { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
    headers["Idempotency-Key"] = idempotency_key if idempotency_key
    headers.merge(extra)
  end

  def json
    JSON.parse(response.body)
  end

  def tomorrow_at(facility, hour, minute = 0)
    day = Time.current.in_time_zone(facility.zone).to_date + 1
    facility.zone.local(day.year, day.month, day.day, hour, minute)
  end

  def hold_body(court, customer, starts_at, minutes: 60, ttl: 120)
    { court_id: court.id, customer_id: customer.id, starts_at: starts_at.iso8601,
      ends_at: (starts_at + minutes.minutes).iso8601, ttl_seconds: ttl }
  end

  def post_hold(token, body, key: SecureRandom.uuid)
    post "/v1/holds", params: body.to_json, headers: auth(token, idempotency_key: key)
  end

  def preview_hold(token, hold_id)
    post "/v1/holds/#{hold_id}/preview", headers: auth(token)
    json
  end

  def confirm(token, preview_token, key: SecureRandom.uuid, extra: {})
    post "/v1/bookings", params: { preview_token: preview_token }.to_json,
                         headers: auth(token, idempotency_key: key, extra: extra)
  end

  def held_and_previewed(token, court, customer, starts_at, ttl: 120)
    post_hold(token, hold_body(court, customer, starts_at, ttl: ttl))
    hold_id = json["id"]
    [ hold_id, preview_hold(token, hold_id)["preview_token"] ]
  end
end
