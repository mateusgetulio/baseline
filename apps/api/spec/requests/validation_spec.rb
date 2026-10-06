require "rails_helper"

RSpec.describe "Request validation" do
  let!(:setup) { provision }
  let(:sandbox) { setup.first }
  let(:token) { setup.last }
  let(:facility) { sandbox.facilities.first }
  let(:court) { facility.courts.first }
  let(:customer) { sandbox.customers.first }

  def invalid_names
    json["invalid_params"].map { |p| p["name"] }
  end

  it "rejects a hold that starts off the slot grid" do
    post_hold(token, hold_body(court, customer, tomorrow_at(facility, 10, 7)))
    expect(response.status).to eq(422)
    expect(invalid_names).to include("starts_at")
  end

  it "rejects a hold outside opening hours, in the past, too long or with a bad ttl" do
    post_hold(token, hold_body(court, customer, tomorrow_at(facility, 21, 30)))
    expect(invalid_names).to include("starts_at")

    post_hold(token, hold_body(court, customer, tomorrow_at(facility, 10) - 2.days))
    expect(invalid_names).to include("starts_at")

    post_hold(token, hold_body(court, customer, tomorrow_at(facility, 10), minutes: 270))
    expect(invalid_names).to include("ends_at")

    post_hold(token, hold_body(court, customer, tomorrow_at(facility, 10), ttl: 601))
    expect(response.status).to eq(422)
    expect(invalid_names).to eq([ "ttl_seconds" ])
  end

  it "rejects availability dates outside the bookable range and bad durations" do
    get "/v1/availability", params: { facility_id: facility.id, date: "9999-12-31", duration_minutes: 45 },
                            headers: auth(token)
    expect(response.status).to eq(422)
    expect(response.media_type).to eq("application/problem+json")
    expect(invalid_names).to match_array(%w[date duration_minutes])
  end

  it "rejects a bad page limit or cursor" do
    get "/v1/facilities", params: { limit: "abc" }, headers: auth(token)
    expect(invalid_names).to eq([ "limit" ])

    get "/v1/facilities", params: { cursor: "nope" }, headers: auth(token)
    expect(invalid_names).to eq([ "cursor" ])
  end

  it "pages through facilities with a cursor" do
    get "/v1/facilities", params: { limit: 1 }, headers: auth(token)
    first = json
    get "/v1/facilities", params: { limit: 1, cursor: first["next_cursor"] }, headers: auth(token)

    expect(first["data"].size).to eq(1)
    expect(json["data"].first["id"]).not_to eq(first["data"].first["id"])
    expect(json["next_cursor"]).to be_nil
  end

  it "answers malformed JSON and unknown routes with Problem Details" do
    post "/v1/holds", params: "{bad", headers: auth(token, idempotency_key: "x")
    expect(response.status).to eq(400)
    expect(json["code"]).to eq("malformed_request")

    get "/v1/nothing-here", headers: auth(token)
    expect(response.status).to eq(404)
    expect(response.media_type).to eq("application/problem+json")
  end
end
