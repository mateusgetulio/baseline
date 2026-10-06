require "rails_helper"

RSpec.describe "Test 3: lost response simulation" do
  let!(:setup) { provision }
  let(:sandbox) { setup.first }
  let(:token) { setup.last }
  let(:facility) { sandbox.facilities.first }
  let(:simulate) { { "X-Sandbox-Simulate" => "drop_response_after_commit" } }

  before do
    _hold_id, @preview_token = held_and_previewed(token, facility.courts.first, sandbox.customers.first, tomorrow_at(facility, 10))
  end

  it "commits the booking, answers 502, and replays the stored 201 on retry with the same key" do
    confirm(token, @preview_token, key: "lost-1", extra: simulate)

    expect(response.status).to eq(502)
    expect(json["code"]).to eq("simulated_lost_response")
    expect(Booking.count).to eq(1)

    confirm(token, @preview_token, key: "lost-1")

    expect(response.status).to eq(201)
    expect(response.headers["Idempotent-Replayed"]).to eq("true")
    expect(json).to include("id" => Booking.sole.id, "status" => "confirmed")
    expect(Booking.count).to eq(1)
    expect(RequestLog.order(:id).last(2).map { |l| [ l.status, l.error_code, l.replayed ] })
      .to eq([ [ 502, "simulated_lost_response", false ], [ 201, nil, true ] ])
  end

  it "replays the stored 201 even if the retry still carries the simulation header" do
    confirm(token, @preview_token, key: "lost-2", extra: simulate)
    confirm(token, @preview_token, key: "lost-2", extra: simulate)

    expect(response.status).to eq(201)
    expect(Booking.count).to eq(1)
  end

  it "still answers a new key with preview_token_used" do
    confirm(token, @preview_token, key: "lost-3", extra: simulate)
    confirm(token, @preview_token, key: "a-different-key")

    expect(response.status).to eq(409)
    expect(json["code"]).to eq("preview_token_used")
    expect(Booking.count).to eq(1)
  end

  it "passes real errors through instead of simulating" do
    confirm(token, "bl_preview_#{'z' * 40}", extra: simulate)
    expect(response.status).to eq(422)
    expect(json["code"]).to eq("preview_token_invalid")
  end

  it "rejects an unknown simulation mode" do
    confirm(token, @preview_token, extra: { "X-Sandbox-Simulate" => "explode" })
    expect(response.status).to eq(422)
    expect(Booking.count).to eq(0)
  end
end
