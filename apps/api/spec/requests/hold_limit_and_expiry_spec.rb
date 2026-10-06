require "rails_helper"

RSpec.describe "Test 6: hold limit and expiry" do
  let!(:setup) { provision }
  let(:sandbox) { setup.first }
  let(:token) { setup.last }
  let(:facility) { sandbox.facilities.first }
  let(:courts) { facility.courts.order(:id).to_a }
  let(:customer) { sandbox.customers.first }

  it "returns hold_limit_reached for a key's fourth active hold" do
    3.times { |i| post_hold(token, hold_body(courts[i], customer, tomorrow_at(facility, 10))) }
    expect(Hold.where(status: "active").count).to eq(3)

    post_hold(token, hold_body(courts[0], customer, tomorrow_at(facility, 14)))

    expect(response.status).to eq(409)
    expect(json["code"]).to eq("hold_limit_reached")
    expect(Hold.count).to eq(3)
  end

  it "frees a slot under the limit once a hold is released" do
    ids = 3.times.map do |i|
      post_hold(token, hold_body(courts[i], customer, tomorrow_at(facility, 10)))
      json["id"]
    end
    delete "/v1/holds/#{ids.first}", headers: auth(token, idempotency_key: SecureRandom.uuid)
    expect(response.status).to eq(200)
    expect(json["status"]).to eq("released")

    post_hold(token, hold_body(courts[0], customer, tomorrow_at(facility, 10)))
    expect(response.status).to eq(201)
  end

  it "does not count expired holds toward the limit" do
    3.times { |i| post_hold(token, hold_body(courts[i], customer, tomorrow_at(facility, 10), ttl: 30)) }

    travel 31.seconds do
      post_hold(token, hold_body(courts[0], customer, tomorrow_at(facility, 14)))
      expect(response.status).to eq(201)
    end
  end

  it "frees the slot when a hold expires" do
    starts_at = tomorrow_at(facility, 10)
    post_hold(token, hold_body(courts[0], customer, starts_at, ttl: 30))
    hold_id = json["id"]

    expect(slot_starts(courts[0], starts_at)).not_to include(starts_at.iso8601)

    travel 31.seconds do
      expect(slot_starts(courts[0], starts_at)).to include(starts_at.iso8601)

      delete "/v1/holds/#{hold_id}", headers: auth(token, idempotency_key: SecureRandom.uuid)
      expect(response.status).to eq(409)
      expect(json["code"]).to eq("hold_not_active")

      post_hold(issue_token(sandbox), hold_body(courts[0], customer, starts_at))
      expect(response.status).to eq(201)
    end
  end

  context "with concurrent holds from one key", :concurrency do
    self.use_transactional_tests = false

    it "never lets the key exceed three active holds" do
      requests = courts.product((8..14).to_a).map do |court, hour|
        { method: "POST", path: "/v1/holds", body: hold_body(court, customer, tomorrow_at(facility, hour)),
          headers: auth(token, idempotency_key: SecureRandom.uuid) }
      end

      results = ConcurrentRequests.run(requests)

      expect(results.map(&:status).tally).to eq(201 => 3, 409 => requests.size - 3)
      expect(results.reject { |r| r.status == 201 }.map { |r| r.json["code"] }.uniq).to eq([ "hold_limit_reached" ])
      expect(Hold.where(status: "active").count).to eq(3)
    end
  end

  it "will not preview or book an expired hold" do
    hold_id, preview_token = held_and_previewed(token, courts[0], customer, tomorrow_at(facility, 10), ttl: 30)

    travel 31.seconds do
      post "/v1/holds/#{hold_id}/preview", headers: auth(token)
      expect(response.status).to eq(409)
      expect(json["code"]).to eq("hold_not_active")

      confirm(token, preview_token)
      expect(response.status).to eq(410)
      expect(json["code"]).to eq("preview_token_expired")
    end
    expect(Booking.count).to eq(0)
  end

  def slot_starts(court, starts_at)
    get "/v1/availability", params: { facility_id: facility.id, date: starts_at.to_date.iso8601, duration_minutes: 60 },
                            headers: auth(token)
    json["courts"].find { |c| c["court_id"] == court.id }["slots"].map { |s| s["starts_at"] }
  end
end
