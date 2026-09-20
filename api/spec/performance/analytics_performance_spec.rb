require "rails_helper"

# Excluded from the default run (see spec/spec_helper.rb). Run deliberately:
#
#   docker compose run --rm api bundle exec rspec --tag perf
#
# Builds its own 10,000-employee dataset rather than loading db/seeds.rb:
# the seed file defines top-level constants and reads Date.current, both of
# which fight with the frozen clock and with being loaded twice.
# type: :request is explicit because this file is not under spec/requests/,
# so RSpec cannot infer it from the path.
RSpec.describe "Analytics performance", :perf, type: :request do
  HEADCOUNT = 10_000
  BUDGET_MS = 300

  def self.clear_organisation
    Employee.update_all(current_salary_id: nil)
    AuditEvent.delete_all
    Salary.delete_all
    Employee.delete_all
    PayBand.delete_all
    ExchangeRate.delete_all
    JobLevel.delete_all
    Department.delete_all
  end

  def self.build_organisation
    # Cleans up first as well as afterwards. This data is created in
    # before(:all), outside the per-example transaction, so an aborted run
    # leaves it behind and the next run collides on unique indexes.
    clear_organisation

    now = Time.current
    today = Date.current
    rng = Random.new(42)

    departments = 8.times.map do |i|
      Department.create!(name: "Department #{i}", cost_centre: format("CC-%04d", i))
    end
    levels = (1..6).map { |rank| JobLevel.create!(name: "L#{rank}", rank: rank) }

    currencies = { "US" => "USD", "PL" => "PLN", "IN" => "INR" }
    { "USD" => 1_000_000, "PLN" => 250_000, "INR" => 12_000 }.each do |code, ppm|
      ExchangeRate.create!(base_currency: code, quote_currency: "USD",
        rate_ppm: ppm, rate_on: Rates::SNAPSHOT_DATE)
    end

    levels.each do |level|
      currencies.each do |country, currency|
        PayBand.create!(job_level: level, country_code: country, currency: currency,
          min_cents: 8_000_000, mid_cents: 10_000_000, max_cents: 12_000_000)
      end
    end

    employees = Array.new(HEADCOUNT) do |i|
      country = currencies.keys[i % 3]

      {
        employee_code: format("PERF-%06d", i),
        first_name: "Perf", last_name: "Employee#{i}",
        email: "perf#{i}@example.com",
        country_code: country,
        department_id: departments[i % 8].id,
        job_level_id: levels[i % 6].id,
        employment_type: "full_time",
        status: "active",
        hired_on: today - rng.rand(90..3650),
        created_at: now, updated_at: now
      }
    end
    employees.each_slice(1_000) { |slice| Employee.insert_all(slice) }

    # Three salary rows each, so the timeline has real history to fold.
    rows = []
    Employee.pluck(:id, :country_code, :hired_on).each do |id, country, hired_on|
      currency = currencies[country]
      3.times do |n|
        from = hired_on + (n * 400)
        next if from > today

        rows << {
          employee_id: id,
          amount_cents: 9_000_000 + (n * 500_000) + rng.rand(1_000_000),
          currency: currency,
          effective_from: from,
          effective_to: (n < 2 && (hired_on + ((n + 1) * 400)) <= today) ? hired_on + ((n + 1) * 400) - 1 : nil,
          change_reason: n.zero? ? "hire" : "merit",
          created_at: now, updated_at: now
        }
      end
    end
    rows.each_slice(1_000) { |slice| Salary.insert_all(slice) }

    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      UPDATE employees SET current_salary_id = (
        SELECT s.id FROM salaries s
        WHERE s.employee_id = employees.id
        ORDER BY s.effective_from DESC LIMIT 1
      )
    SQL
  end

  def measure
    Rails.cache.clear
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)
  end

  before(:all) do
    # This spec needs real volume, so it opts out of the transactional
    # rollback the rest of the suite uses and cleans up after itself.
    self.class.build_organisation
  end

  after(:all) { self.class.clear_organisation }

  let!(:user) { create(:user, password: "compensation2026", password_confirmation: "compensation2026") }

  before do
    post "/api/v1/session",
      params: { email_address: user.email_address, password: "compensation2026" }
  end

  it "has actually built ten thousand employees" do
    expect(Employee.count).to be >= HEADCOUNT
    expect(Salary.count).to be > HEADCOUNT
  end

  # The headline assertion from docs/build-plan.md step 23.
  it "returns the compensation overview within the budget" do
    elapsed = measure { get "/api/v1/analytics/overview" }

    puts "\n    overview (cold):      #{elapsed} ms against #{Employee.count} employees"

    expect(response).to have_http_status(:ok)
    expect(elapsed).to be < BUDGET_MS
  end

  it "serves the overview far faster once cached" do
    get "/api/v1/analytics/overview"

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    get "/api/v1/analytics/overview"
    cached = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(1)

    puts "    overview (cached):    #{cached} ms"

    expect(cached).to be < BUDGET_MS / 3
  end

  it "returns the distribution within the budget" do
    elapsed = measure { get "/api/v1/analytics/distribution", params: { group_by: "job_level" } }

    puts "    distribution:         #{elapsed} ms"

    expect(response).to have_http_status(:ok)
    expect(elapsed).to be < BUDGET_MS
  end

  it "returns 24 months of payroll trend within the budget" do
    elapsed = measure { get "/api/v1/analytics/payroll_trend" }

    puts "    payroll trend (24m):  #{elapsed} ms"

    expect(response).to have_http_status(:ok)
    expect(elapsed).to be < BUDGET_MS
  end

  it "returns the outlier report within the budget" do
    elapsed = measure { get "/api/v1/analytics/outliers" }

    puts "    outliers:             #{elapsed} ms"

    expect(response).to have_http_status(:ok)
    expect(elapsed).to be < BUDGET_MS
  end

  it "returns a directory page within the budget" do
    elapsed = measure { get "/api/v1/employees", params: { per_page: 50 } }

    puts "    directory page:       #{elapsed} ms"

    expect(response).to have_http_status(:ok)
    expect(elapsed).to be < BUDGET_MS
  end

  it "returns a deep directory page as fast as a shallow one" do
    elapsed = measure { get "/api/v1/employees", params: { per_page: 50, page: 150 } }

    puts "    directory page 150:   #{elapsed} ms"

    expect(elapsed).to be < BUDGET_MS
  end
end
