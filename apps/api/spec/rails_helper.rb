require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include ApiHelpers
  config.include ActiveSupport::Testing::TimeHelpers

  config.before(:suite) { DatabaseTruncation.call }

  config.around(:each, :concurrency) do |example|
    Rails.application.eager_load!
    DatabaseTruncation.call
    example.run
  ensure
    DatabaseTruncation.call
  end
end
