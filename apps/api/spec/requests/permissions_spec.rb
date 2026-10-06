require "rails_helper"

RSpec.describe "Test 7: permissions and sandbox scope" do
  let!(:setup) { provision }
  let(:sandbox) { setup.first }
  let(:token) { setup.last }
  let(:facility) { sandbox.facilities.first }
  let(:court) { facility.courts.first }
  let(:customer) { sandbox.customers.first }

  describe "missing permission" do
    it "returns 403 when a read-only key creates a hold" do
      read_only = issue_token(sandbox, permissions: [ "availability.read" ])
      post_hold(read_only, hold_body(court, customer, tomorrow_at(facility, 10)))

      expect(response.status).to eq(403)
      expect(json["code"]).to eq("permission_denied")
      expect(Hold.count).to eq(0)
    end

    it "returns 403 when a holds-only key reads availability" do
      holds_only = issue_token(sandbox, permissions: [ "holds.write" ])
      get "/v1/facilities", headers: auth(holds_only)

      expect(response.status).to eq(403)
      expect(json["code"]).to eq("permission_denied")
    end
  end

  describe "authentication" do
    it "rejects a missing, malformed or revoked key with 401" do
      get "/v1/me"
      expect(response.status).to eq(401)

      get "/v1/me", headers: auth("bl_test_nope")
      expect(response.status).to eq(401)

      ApiKey.where(sandbox: sandbox).update_all(revoked_at: Time.current)
      get "/v1/me", headers: auth(token)
      expect(response.status).to eq(401)
      expect(json["code"]).to eq("unauthorized")
    end

    it "rejects a key whose secret does not match" do
      tampered = token.sub(/.\z/) { |c| c == "a" ? "b" : "a" }
      get "/v1/me", headers: auth(tampered)
      expect(response.status).to eq(401)
    end
  end

  describe "a key from another sandbox" do
    let(:outsider) { provision.last }

    it "gets 404 on this sandbox's facility, availability, court and customer" do
      get "/v1/facilities/#{facility.id}/courts", headers: auth(outsider)
      expect(response.status).to eq(404)

      get "/v1/availability", params: { facility_id: facility.id, date: Date.tomorrow.iso8601, duration_minutes: 60 },
                              headers: auth(outsider)
      expect(response.status).to eq(404)

      post_hold(outsider, hold_body(court, customer, tomorrow_at(facility, 10)))
      expect(response.status).to eq(404)
      expect(json["code"]).to eq("not_found")
    end

    it "does not see this sandbox's facilities" do
      get "/v1/facilities", headers: auth(outsider)
      expect(json["data"].map { |f| f["id"] }).not_to include(facility.id)
    end

    it "gets 404 when releasing this sandbox's hold" do
      post_hold(token, hold_body(court, customer, tomorrow_at(facility, 10)))
      delete "/v1/holds/#{json['id']}", headers: auth(outsider, idempotency_key: SecureRandom.uuid)

      expect(response.status).to eq(404)
      expect(Hold.last.status).to eq("active")
    end
  end

  it "lets only the owning key release a hold" do
    post_hold(token, hold_body(court, customer, tomorrow_at(facility, 10)))
    hold_id = json["id"]

    delete "/v1/holds/#{hold_id}", headers: auth(issue_token(sandbox), idempotency_key: SecureRandom.uuid)
    expect(response.status).to eq(404)

    delete "/v1/holds/#{hold_id}", headers: auth(token, idempotency_key: SecureRandom.uuid)
    expect(response.status).to eq(200)
  end
end
