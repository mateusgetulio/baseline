require "rails_helper"

RSpec.describe "Test 2: confirm race", :concurrency, type: :request do
  self.use_transactional_tests = false

  it "turns one preview token into exactly one booking under 10 concurrent confirms" do
    sandbox, token = provision
    facility = sandbox.facilities.first
    _hold_id, preview_token = held_and_previewed(token, facility.courts.first, sandbox.customers.first, tomorrow_at(facility, 10))

    results = ConcurrentRequests.run(
      Array.new(10) do
        { method: "POST", path: "/v1/bookings", body: { preview_token: preview_token },
          headers: auth(token, idempotency_key: SecureRandom.uuid) }
      end
    )

    expect(results.map(&:status).tally).to eq(201 => 1, 409 => 9)
    expect(results.reject { |r| r.status == 201 }.map { |r| r.json["code"] }.uniq).to eq([ "preview_token_used" ])
    expect(Booking.count).to eq(1)
    expect(Hold.sole.status).to eq("converted")
  end
end
