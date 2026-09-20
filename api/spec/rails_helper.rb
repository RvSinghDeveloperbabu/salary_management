require "spec_helper"

ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "shoulda/matchers"

# Every spec runs at this instant. Salary history is effective-dated, so a
# suite that reads the wall clock would start failing as fixtures aged past
# their boundaries — a spec that passes on Tuesday and fails on Wednesday is
# worse than no spec (CLAUDE.md rule 6).
#
# A date well clear of month and year boundaries, so "18 months ago" and
# "24 months of payroll" arithmetic has no edge cases to trip on.
SPEC_FROZEN_TIME = Time.utc(2026, 6, 15, 12, 0, 0).freeze

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]

  # Each example runs in a transaction that is rolled back afterwards. With
  # SQLite's single writer this also keeps specs from leaking state into one
  # another, which matters because they run serially.
  config.use_transactional_fixtures = true

  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include ActiveSupport::Testing::TimeHelpers

  # Determinism, part one: the clock does not move.
  config.around(:each) do |example|
    travel_to(SPEC_FROZEN_TIME) { example.run }
  end

  # Determinism, part two: Faker produces the same sequence for every
  # example, not merely for every run.
  config.before(:each) do
    Faker::Config.random = Random.new(42)
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
