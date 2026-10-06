require "rails_helper"

RSpec.describe "Test 9: responses validate against openapi.yaml" do
  let!(:setup) { provision }
  let(:sandbox) { setup.first }
  let(:token) { setup.last }
  let(:facility) { sandbox.facilities.first }
  let(:court) { facility.courts.first }
  let(:customer) { sandbox.customers.first }

  it "documents every data plane and control plane route" do
    documented = OpenapiContract.document["paths"].flat_map do |path, operations|
      operations.keys.map { |verb| "#{verb.upcase} #{path.gsub(/\{[^}]+\}/, '{}')}" }
    end
    routed = Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s.sub("(.:format)", "")
      next unless path.start_with?("/v1/", "/sandbox")

      "#{route.verb} #{path.gsub(/:\w+/, '{}')}"
    end

    expect(routed).to match_array(documented)
  end

  it "validates the read endpoints" do
    get "/v1/me", headers: auth(token)
    expect(response).to match_openapi("GET", "/v1/me")

    get "/v1/facilities", headers: auth(token)
    expect(response).to match_openapi("GET", "/v1/facilities")

    get "/v1/facilities/#{facility.id}/courts", headers: auth(token)
    expect(response).to match_openapi("GET", "/v1/facilities/{facility_id}/courts")

    get "/v1/availability", params: { facility_id: facility.id, date: (Date.current + 1).iso8601, duration_minutes: 60 },
                            headers: auth(token)
    expect(response).to match_openapi("GET", "/v1/availability")
  end

  it "validates the booking flow" do
    post_hold(token, hold_body(court, customer, tomorrow_at(facility, 10)))
    expect(response).to match_openapi("POST", "/v1/holds")
    hold_id = json["id"]

    post "/v1/holds/#{hold_id}/preview", headers: auth(token)
    expect(response).to match_openapi("POST", "/v1/holds/{hold_id}/preview")

    confirm(token, json["preview_token"])
    expect(response).to match_openapi("POST", "/v1/bookings")

    post_hold(token, hold_body(court, customer, tomorrow_at(facility, 14)))
    delete "/v1/holds/#{json['id']}", headers: auth(token, idempotency_key: SecureRandom.uuid)
    expect(response).to match_openapi("DELETE", "/v1/holds/{hold_id}")
  end

  it "validates Problem Details responses" do
    get "/v1/me"
    expect(response).to match_openapi("GET", "/v1/me")

    post_hold(token, hold_body(court, customer, tomorrow_at(facility, 10)).merge(ttl_seconds: 1))
    expect(response).to match_openapi("POST", "/v1/holds")

    confirm(token, "nope")
    expect(response).to match_openapi("POST", "/v1/bookings")
  end

  it "validates the control plane" do
    previous = ENV["SANDBOX_ADMIN_TOKEN"]
    ENV["SANDBOX_ADMIN_TOKEN"] = "contract-admin"
    admin = { "Authorization" => "Bearer contract-admin", "Content-Type" => "application/json" }

    post "/sandbox", params: { name: "Contract" }.to_json, headers: admin
    expect(response).to match_openapi("POST", "/sandbox")
    created = json
    id = created["sandbox"]["id"]

    post "/sandbox/#{id}/keys", params: { permissions: [ "availability.read" ] }.to_json, headers: admin
    expect(response).to match_openapi("POST", "/sandbox/{sandbox_id}/keys")

    delete "/sandbox/#{id}/keys/#{json['id']}", headers: admin
    expect(response).to match_openapi("DELETE", "/sandbox/{sandbox_id}/keys/{key_id}")

    sandbox = Sandbox.find(id)
    facility = sandbox.facilities.first
    post_hold(created["key"]["api_key"], hold_body(facility.courts.first, sandbox.customers.first, tomorrow_at(facility, 10)))
    post "/sandbox/#{id}/holds/#{json['id']}/expire", headers: admin
    expect(response).to match_openapi("POST", "/sandbox/{sandbox_id}/holds/{hold_id}/expire")

    get "/sandbox/#{id}/requests", headers: admin
    expect(response).to match_openapi("GET", "/sandbox/{sandbox_id}/requests")

    post "/sandbox/#{id}/reset", headers: admin
    expect(response).to match_openapi("POST", "/sandbox/{sandbox_id}/reset")
  ensure
    ENV["SANDBOX_ADMIN_TOKEN"] = previous
  end

  it "catches a response that drifts from the document" do
    get "/v1/me", headers: auth(token)
    drifted = response.dup
    allow(drifted).to receive(:body).and_return(JSON.parse(response.body).merge("extra" => 1).to_json)

    expect(OpenapiContract.errors_for("GET", "/v1/me", drifted)).not_to be_empty
  end
end
