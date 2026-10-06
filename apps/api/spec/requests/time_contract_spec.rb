require "rails_helper"

RSpec.describe "Test 8: time contract" do
  let!(:setup) { provision }
  let(:sandbox) { setup.first }
  let(:token) { setup.last }
  let(:zone) { ActiveSupport::TimeZone["America/New_York"] }
  let(:all_day) do
    sandbox.facilities.create!(name: "Harbor Point Night Courts", time_zone: zone.name, opens_minute: 0, closes_minute: 1440)
           .tap { |f| f.courts.create!(name: "Court N", sport: "tennis", hourly_rate_cents: 4000, currency: "USD") }
  end

  def next_fall_back_date
    (Date.current + 1..Date.current + 400).find do |date|
      zone.local(date.year, date.month, date.day, 0).utc_offset > zone.local(date.year, date.month, date.day, 12).utc_offset
    end
  end

  it "returns both 01:30 slots with distinct offsets and no duplicate instants on a fall-back day" do
    date = next_fall_back_date
    get "/v1/availability", params: { facility_id: all_day.id, date: date.iso8601, duration_minutes: 60 },
                            headers: auth(token)

    expect(response.status).to eq(200)
    starts = json["courts"].first["slots"].map { |s| s["starts_at"] }
    expect(starts).to include("#{date.iso8601}T01:30:00-04:00", "#{date.iso8601}T01:30:00-05:00")
    expect(starts.map { |s| Time.iso8601(s) }.uniq.size).to eq(starts.size)
    expect(starts.size).to eq(49)
    expect(starts).to all(match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\z/))
  end

  it "accepts a hold on the second 01:30 and keeps the first one free" do
    date = next_fall_back_date
    second = "#{date.iso8601}T01:30:00-05:00"
    post_hold(token, { court_id: all_day.courts.first.id, customer_id: sandbox.customers.first.id,
                       starts_at: second, ends_at: "#{date.iso8601}T02:30:00-05:00", ttl_seconds: 120 })

    expect(response.status).to eq(201)
    expect(json["starts_at"]).to eq(second)

    get "/v1/availability", params: { facility_id: all_day.id, date: date.iso8601, duration_minutes: 60 },
                            headers: auth(token)
    starts = json["courts"].first["slots"].map { |s| s["starts_at"] }
    expect(starts).to include("#{date.iso8601}T01:00:00-04:00")
    expect(starts).not_to include(second)
  end

  it "rejects naked local times on mutations" do
    facility = sandbox.facilities.first
    starts_at = tomorrow_at(facility, 10)
    post_hold(token, hold_body(facility.courts.first, sandbox.customers.first, starts_at)
                       .merge(starts_at: starts_at.strftime("%Y-%m-%dT%H:%M:%S")))

    expect(response.status).to eq(422)
    expect(json["invalid_params"].map { |p| p["name"] }).to include("starts_at")
  end

  it "stores instants in UTC" do
    facility = sandbox.facilities.first
    starts_at = tomorrow_at(facility, 10)
    post_hold(token, hold_body(facility.courts.first, sandbox.customers.first, starts_at))

    raw = ActiveRecord::Base.connection.select_value("SELECT starts_at FROM holds WHERE id = #{json['id'].to_i}")
    expect(raw.to_s).to start_with(starts_at.utc.strftime("%Y-%m-%d %H:%M:%S"))
  end
end
