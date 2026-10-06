require "rails_helper"

RSpec.describe "Test 4: idempotency semantics" do
  let!(:setup) { provision }
  let(:sandbox) { setup.first }
  let(:token) { setup.last }
  let(:facility) { sandbox.facilities.first }
  let(:court) { facility.courts.first }
  let(:customer) { sandbox.customers.first }
  let(:body) { hold_body(court, customer, tomorrow_at(facility, 10)) }

  it "replays the stored status and identical body for the same key and request" do
    post_hold(token, body, key: "same-key")
    first_status = response.status
    first_body = response.body

    post_hold(token, body, key: "same-key")

    expect(first_status).to eq(201)
    expect(response.status).to eq(201)
    expect(response.body).to eq(first_body)
    expect(response.headers["Idempotent-Replayed"]).to eq("true")
    expect(Hold.count).to eq(1)
    expect(RequestLog.order(:id).pluck(:replayed)).to eq([ false, true ])
  end

  it "replays a stored error response too" do
    other = hold_body(court, customer, tomorrow_at(facility, 10)).merge(ttl_seconds: 5)
    post_hold(token, other, key: "bad")
    first_body = response.body
    post_hold(token, other, key: "bad")

    expect(response.status).to eq(422)
    expect(response.body).to eq(first_body)
    expect(response.headers["Idempotent-Replayed"]).to eq("true")
  end

  it "rejects the same key with a different body" do
    post_hold(token, body, key: "reused")
    post_hold(token, body.merge(ttl_seconds: 300), key: "reused")

    expect(response.status).to eq(409)
    expect(json["code"]).to eq("idempotency_key_reused")
    expect(Hold.count).to eq(1)
  end

  it "rejects the same key on a different path" do
    post_hold(token, body, key: "reused-path")
    delete "/v1/holds/#{json['id']}", headers: auth(token, idempotency_key: "reused-path")

    expect(response.status).to eq(409)
    expect(json["code"]).to eq("idempotency_key_reused")
  end

  it "treats the same JSON with keys in another order as the same request" do
    post_hold(token, body, key: "ordered")
    post_hold(token, body.to_a.reverse.to_h, key: "ordered")

    expect(response.status).to eq(201)
    expect(response.headers["Idempotent-Replayed"]).to eq("true")
  end

  it "treats keys that differ only in case as different keys" do
    post_hold(token, body, key: "Key-aBc")
    post_hold(token, hold_body(court, customer, tomorrow_at(facility, 14)), key: "key-ABC")

    expect(response.status).to eq(201)
    expect(Hold.count).to eq(2)
  end

  it "fingerprints the query string and ignores it as a source of body fields" do
    other_court = facility.courts.order(:id).second
    post "/v1/holds?court_id=#{other_court.id}", params: body.to_json, headers: auth(token, idempotency_key: "query")
    expect(response.status).to eq(201)
    expect(json["court_id"]).to eq(court.id)

    post "/v1/holds?court_id=0", params: body.to_json, headers: auth(token, idempotency_key: "query")
    expect(response.status).to eq(409)
    expect(json["code"]).to eq("idempotency_key_reused")
  end

  it "scopes keys per API key" do
    other_token = issue_token(sandbox)
    post_hold(token, body, key: "shared")
    post_hold(other_token, body, key: "shared")

    expect(response.status).to eq(409)
    expect(json["code"]).to eq("slot_unavailable")
  end

  it "requires an Idempotency-Key on every mutation" do
    post "/v1/holds", params: body.to_json, headers: auth(token)
    expect(response.status).to eq(400)
    expect(json["code"]).to eq("idempotency_key_missing")

    post_hold(token, body)
    delete "/v1/holds/#{json['id']}", headers: auth(token)
    expect(response.status).to eq(400)
    expect(json["code"]).to eq("idempotency_key_missing")
  end

  context "with concurrent requests sharing one key", :concurrency do
    self.use_transactional_tests = false

    it "executes the operation once" do
      requests = Array.new(10) do
        { method: "POST", path: "/v1/holds", body: body, headers: auth(token, idempotency_key: "concurrent-key") }
      end

      results = ConcurrentRequests.run(requests)

      winners = results.select { |r| r.status == 201 }
      others = results.reject { |r| r.status == 201 }
      expect(winners).not_to be_empty
      expect(winners.map(&:body).uniq.size).to eq(1)
      expect(others.map { |r| [ r.status, r.json["code"] ] }.uniq).to eq([ [ 409, "idempotency_in_progress" ] ]).or eq([])
      expect(Hold.count).to eq(1)
      expect(IdempotencyRecord.count).to eq(1)
    end
  end
end
