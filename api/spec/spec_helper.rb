# Loaded via `--require spec_helper` in .rspec, before rails_helper pulls in
# the application. SimpleCov has to start before any application code is
# loaded or it cannot see which lines ran.

require "simplecov"

SimpleCov.start "rails" do
  enable_coverage :branch

  # Generated or trivial code. Measuring it inflates the number without
  # telling anyone anything.
  skip "/spec/"
  skip "/config/"
  skip "/db/"
  skip "app/channels/"
  skip "app/jobs/"
  skip "app/mailers/"

  # Mirrors the layout in CLAUDE.md "Code structure".
  group "Queries",     "app/queries"
  group "Services",    "app/services"
  group "Statistics",  "app/lib/stats"
  group "Serializers", "app/serializers"

  # The floor is only enforced on a full run. Running a single spec file
  # would otherwise "fail" for not exercising the rest of the application,
  # which trains people to ignore the result.
  if ENV["COVERAGE"]
    minimum_coverage line: 80
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # The performance spec seeds 10,000 employees. That belongs in a deliberate
  # run, not in the suite a developer runs on every save. Opt in with
  # `rspec --tag perf`, which sets this filter and overrides the exclusion.
  config.filter_run_excluding :perf unless ENV["INCLUDE_PERF"]

  config.disable_monkey_patching!
  config.warnings = false

  config.default_formatter = "doc" if config.files_to_run.one?

  # Deterministic ordering. A fixed seed means a failure caused by test
  # order reproduces instead of appearing at random, per CLAUDE.md rule 6.
  config.order = :defined
end
