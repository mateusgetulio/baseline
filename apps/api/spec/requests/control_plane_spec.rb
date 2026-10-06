require "rails_helper"

RSpec.describe "Sandbox control plane" do
  let(:admin_token) { "admin-#{SecureRandom.hex(8)}" }
  let(:admin) { { "Authorization" => "Bearer #{admin_token}", "Content-Type" => "application/json" } }

  around do |example|
    previous = ENV["SANDBOX_ADMIN_TOKEN"]
    ENV["SANDBOX_ADMIN_TOKEN"] = admin_token
    example.run
  ensure
    ENV["SANDBOX_ADMIN_TOKEN"] = previous
  end

  def create_sandbox(body = {})
    post "/sandbox", params: body.to_json, headers: admin
    json
  end

  it "requires the bootstrap secret" do
    post "/sandbox", params: {}.to_json, headers: { "Content-Type" => "application/json" }
    expect(response.status).to eq(401)

    post "/sandbox", params: {}.to_json, headers: admin.merge("Authorization" => "Bearer wrong")
    expect(response.status).to eq(401)
    expect(response.media_type).to eq("application/problem+json")
  end

  it "refuses everything when no bootstrap secret is configured" do
    ENV["SANDBOX_ADMIN_TOKEN"] = ""
    post "/sandbox", params: {}.to_json, headers: admin.merge("Authorization" => "Bearer ")
    expect(response.status).to eq(401)
  end

  it "does not accept a data plane key" do
    _sandbox, token = provision
    post "/sandbox", params: {}.to_json, headers: auth(token)
    expect(response.status).to eq(401)
  end

  it "creates a seeded sandbox and shows its first key once" do
    body = create_sandbox(name: "Demo")

    expect(response.status).to eq(201)
    expect(body["sandbox"]["name"]).to eq("Demo")
    expect(body["key"]["permissions"]).to match_array(ApiKey::PERMISSIONS)
    expect(body["key"]["api_key"]).to start_with("bl_test_")
    expect(ApiKey.find(body["key"]["id"]).secret_digest).not_to include(body["key"]["api_key"].split("_").last)

    get "/v1/facilities", headers: auth(body["key"]["api_key"])
    expect(json["data"].map { |f| f["name"] }).to eq([ "Harbor Point Racquet Club", "Lakeside Padel" ])
  end

  it "issues a key with chosen permissions and revokes it" do
    sandbox_id = create_sandbox["sandbox"]["id"]
    post "/sandbox/#{sandbox_id}/keys", params: { permissions: [ "availability.read" ] }.to_json, headers: admin
    key = json

    expect(response.status).to eq(201)
    get "/v1/me", headers: auth(key["api_key"])
    expect(json["permissions"]).to eq([ "availability.read" ])

    delete "/sandbox/#{sandbox_id}/keys/#{key['id']}", headers: admin
    expect(json["revoked_at"]).to be_present
    get "/v1/me", headers: auth(key["api_key"])
    expect(response.status).to eq(401)
  end

  it "rejects unknown permissions" do
    sandbox_id = create_sandbox["sandbox"]["id"]
    post "/sandbox/#{sandbox_id}/keys", params: { permissions: [ "admin" ] }.to_json, headers: admin
    expect(response.status).to eq(422)
    expect(json["invalid_params"].first["name"]).to eq("permissions")
  end

  it "resets one sandbox to its seed and leaves the others untouched" do
    first = create_sandbox
    second = create_sandbox
    [ first, second ].each do |created|
      sandbox = Sandbox.find(created["sandbox"]["id"])
      facility = sandbox.facilities.first
      held_and_previewed(created["key"]["api_key"], facility.courts.first, sandbox.customers.first, tomorrow_at(facility, 10))
      confirm(created["key"]["api_key"], json["preview_token"])
    end
    sandbox = Sandbox.find(first["sandbox"]["id"])
    sandbox.facilities.first.update!(name: "Renamed")

    post "/sandbox/#{sandbox.id}/reset", headers: admin

    expect(response.status).to eq(200)
    expect(Booking.where(sandbox: sandbox).count).to eq(0)
    expect(Hold.where(sandbox: sandbox).count).to eq(0)
    expect(sandbox.facilities.pluck(:name)).to eq([ "Harbor Point Racquet Club", "Lakeside Padel" ])
    expect(sandbox.api_keys.count).to eq(1)
    expect(Booking.where(sandbox_id: second["sandbox"]["id"]).count).to eq(1)
    expect(Hold.where(sandbox_id: second["sandbox"]["id"]).count).to eq(1)
  end

  it "expires a hold now and frees its slot" do
    created = create_sandbox
    sandbox = Sandbox.find(created["sandbox"]["id"])
    facility = sandbox.facilities.first
    hold_id, preview_token = held_and_previewed(created["key"]["api_key"], facility.courts.first, sandbox.customers.first,
                                                tomorrow_at(facility, 10), ttl: 600)

    post "/sandbox/#{sandbox.id}/holds/#{hold_id}/expire", headers: admin
    expect(response.status).to eq(200)
    expect(json["status"]).to eq("expired")

    confirm(created["key"]["api_key"], preview_token)
    expect(response.status).to eq(409)
    expect(json["code"]).to eq("hold_not_active")

    post "/sandbox/#{sandbox.id}/holds/#{hold_id}/expire", headers: admin
    expect(response.status).to eq(409)
  end

  it "returns 404 for a hold in another sandbox" do
    first = create_sandbox
    second = create_sandbox
    sandbox = Sandbox.find(first["sandbox"]["id"])
    facility = sandbox.facilities.first
    post_hold(first["key"]["api_key"], hold_body(facility.courts.first, sandbox.customers.first, tomorrow_at(facility, 10)))

    post "/sandbox/#{second['sandbox']['id']}/holds/#{json['id']}/expire", headers: admin
    expect(response.status).to eq(404)
  end

  it "lists the sandbox's recent requests with client and replayed flag" do
    created = create_sandbox
    get "/v1/me", headers: auth(created["key"]["api_key"]).merge("X-Client" => "mcp")
    get "/v1/me", headers: auth(created["key"]["api_key"]).merge("User-Agent" => "curl/8.7.1")

    get "/sandbox/#{created['sandbox']['id']}/requests", headers: admin

    expect(json["data"].map { |r| [ r["method"], r["path"], r["status"], r["client"], r["replayed"] ] })
      .to eq([ [ "GET", "/v1/me", 200, "curl", false ], [ "GET", "/v1/me", 200, "mcp", false ] ])
  end
end
