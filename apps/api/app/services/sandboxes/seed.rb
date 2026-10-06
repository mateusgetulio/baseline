module Sandboxes
  module Seed
    FACILITIES = [
      {
        name: "Harbor Point Racquet Club", time_zone: "America/New_York", opens_minute: 7 * 60, closes_minute: 22 * 60,
        courts: [
          { name: "Court 1", sport: "tennis", hourly_rate_cents: 4000, currency: "USD" },
          { name: "Court 2", sport: "tennis", hourly_rate_cents: 4000, currency: "USD" },
          { name: "Court 3", sport: "pickleball", hourly_rate_cents: 2500, currency: "USD" }
        ]
      },
      {
        name: "Lakeside Padel", time_zone: "America/Chicago", opens_minute: 6 * 60, closes_minute: 23 * 60,
        courts: [
          { name: "Padel 1", sport: "padel", hourly_rate_cents: 3600, currency: "USD" },
          { name: "Padel 2", sport: "padel", hourly_rate_cents: 3600, currency: "USD" }
        ]
      }
    ].freeze

    CUSTOMERS = [
      { name: "Avery Lindqvist", email: "avery@players.test" },
      { name: "Jonah Okonkwo-Reyes", email: "jonah@players.test" },
      { name: "Priya Castellanos", email: "priya@players.test" },
      { name: "Theo Marchetti", email: "theo@players.test" }
    ].freeze

    module_function

    def call(sandbox)
      FACILITIES.each do |attrs|
        facility = sandbox.facilities.create!(attrs.except(:courts))
        attrs[:courts].each { |court| facility.courts.create!(court) }
      end
      CUSTOMERS.each { |attrs| sandbox.customers.create!(attrs) }
    end
  end
end
