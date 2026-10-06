require "rails_helper"

RSpec.describe "Test 5: preview and token rules" do
  let!(:setup) { provision }
  let(:sandbox) { setup.first }
  let(:token) { setup.last }
  let(:facility) { sandbox.facilities.first }
  let(:court) { facility.courts.first }
  let(:customer) { sandbox.customers.first }
  let(:starts_at) { tomorrow_at(facility, 10) }

  it "previews a hold with price, summary and a token, then books it" do
    post_hold(token, hold_body(court, customer, starts_at, minutes: 90))
    preview = preview_hold(token, json["id"])

    expect(response.status).to eq(201)
    expect(preview["price_cents"]).to eq(6000)
    expect(preview["summary"]).to include(court.name, facility.name, customer.name, "10:00 to 11:30", "USD 60.00")
    expect(preview["preview_token"]).to start_with("bl_preview_")
    expect(PreviewToken.last.token_digest).not_to include(preview["preview_token"])

    confirm(token, preview["preview_token"])
    expect(response.status).to eq(201)
    expect(json).to include("status" => "confirmed", "price_cents" => 6000, "starts_at" => starts_at.iso8601)
  end

  it "rejects a missing token" do
    post "/v1/bookings", params: {}.to_json, headers: auth(token, idempotency_key: SecureRandom.uuid)
    expect(response.status).to eq(422)
    expect(json["code"]).to eq("preview_token_missing")
  end

  it "rejects an unknown token and a token issued to another key" do
    confirm(token, "bl_preview_#{'a' * 40}")
    expect(response.status).to eq(422)
    expect(json["code"]).to eq("preview_token_invalid")

    _hold_id, preview_token = held_and_previewed(token, court, customer, starts_at)
    confirm(issue_token(sandbox), preview_token)
    expect(response.status).to eq(422)
    expect(json["code"]).to eq("preview_token_invalid")
    expect(Booking.count).to eq(0)
  end

  it "rejects an expired token after five minutes even while the hold is still active" do
    _hold_id, preview_token = held_and_previewed(token, court, customer, starts_at, ttl: 600)

    travel 301.seconds do
      confirm(token, preview_token)
      expect(response.status).to eq(410)
      expect(json["code"]).to eq("preview_token_expired")
    end
    expect(Booking.count).to eq(0)
  end

  it "caps the token lifetime at the hold's expiry" do
    post_hold(token, hold_body(court, customer, starts_at, ttl: 60))
    preview = preview_hold(token, json["id"])

    expect(Time.iso8601(preview["preview_token_expires_at"])).to be_within(1.second).of(Hold.last.expires_at)
  end

  it "rejects a used token" do
    _hold_id, preview_token = held_and_previewed(token, court, customer, starts_at)
    confirm(token, preview_token)
    confirm(token, preview_token)

    expect(response.status).to eq(409)
    expect(json["code"]).to eq("preview_token_used")
    expect(Booking.count).to eq(1)
  end

  it "rejects a token whose price no longer matches the hold" do
    _hold_id, preview_token = held_and_previewed(token, court, customer, starts_at)
    court.update!(hourly_rate_cents: 5000)

    confirm(token, preview_token)
    expect(response.status).to eq(409)
    expect(json["code"]).to eq("preview_token_mismatch")
    expect(Booking.count).to eq(0)
  end

  it "rejects a token whose customer no longer matches the hold" do
    hold_id, preview_token = held_and_previewed(token, court, customer, starts_at)
    Hold.find(hold_id).update!(customer: sandbox.customers.second)

    confirm(token, preview_token)
    expect(response.status).to eq(409)
    expect(json["code"]).to eq("preview_token_mismatch")
  end

  it "rejects a token for a hold that was released" do
    hold_id, preview_token = held_and_previewed(token, court, customer, starts_at)
    delete "/v1/holds/#{hold_id}", headers: auth(token, idempotency_key: SecureRandom.uuid)

    confirm(token, preview_token)
    expect(response.status).to eq(409)
    expect(json["code"]).to eq("hold_not_active")
  end

  it "lets only the hold owner preview" do
    post_hold(token, hold_body(court, customer, starts_at))
    post "/v1/holds/#{json['id']}/preview", headers: auth(issue_token(sandbox))

    expect(response.status).to eq(404)
  end

  it "does not need an Idempotency-Key to preview" do
    post_hold(token, hold_body(court, customer, starts_at))
    post "/v1/holds/#{json['id']}/preview", headers: auth(token)
    expect(response.status).to eq(201)
  end
end
