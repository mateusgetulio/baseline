require "rails_helper"

RSpec.describe "Test 1: hold race", :concurrency do
  self.use_transactional_tests = false

  it "lets exactly one of 20 concurrent holds from 20 keys win the same court and window" do
    sandbox, = provision
    facility = sandbox.facilities.first
    court = facility.courts.first
    tokens = Array.new(20) { issue_token(sandbox, permissions: [ "holds.write" ]) }
    body = hold_body(court, sandbox.customers.first, tomorrow_at(facility, 10))

    results = ConcurrentRequests.run(
      tokens.map { |token| { method: "POST", path: "/v1/holds", body: body, headers: auth(token, idempotency_key: SecureRandom.uuid) } }
    )

    expect(results.map(&:status).tally).to eq(201 => 1, 409 => 19)
    losers = results.select { |r| r.status == 409 }
    expect(losers.map { |r| r.json["code"] }.uniq).to eq([ "slot_unavailable" ])
    expect(losers.map(&:json).flat_map(&:keys).uniq).to match_array(%w[type title status detail code])
    expect(Hold.where(court_id: court.id, status: "active").count).to eq(1)
  end
end
