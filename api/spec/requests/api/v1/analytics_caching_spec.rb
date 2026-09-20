require "rails_helper"

RSpec.describe "Analytics caching" do
  let(:level) { create(:job_level, name: "L3", rank: 3) }
  let!(:employee) { create(:employee, job_level: level, country_code: "US") }

  def json = JSON.parse(response.body)

  def count_queries
    queries = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
      queries += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
    end
    yield
    ActiveSupport::Notifications.unsubscribe(sub)
    queries
  end

  before do
    create(:exchange_rate, :identity, rate_on: Rates::SNAPSHOT_DATE)
    Salaries::RecordChange.new(employee: employee, amount_cents: 10_000_000, currency: "USD",
      effective_from: 1.year.ago.to_date, change_reason: "hire").call
    sign_in
  end

  it "serves a repeated request from cache" do
    get "/api/v1/analytics/overview"
    first = json

    repeat_queries = count_queries { get "/api/v1/analytics/overview" }

    expect(json).to eq(first)
    # Only the session lookup and the two watermark reads.
    expect(repeat_queries).to be <= 3
  end

  it "does no aggregation work on a cache hit" do
    get "/api/v1/analytics/overview"

    expect(CompensationSnapshot).not_to receive(:new)

    get "/api/v1/analytics/overview"
  end

  # The cache must be exact: invalidated by a change and by nothing else.
  #
  # The suite freezes the clock, so updated_at would not move on a write and
  # a timestamp-only watermark could not notice. Advancing a second before
  # each mutation is what actually happens in production, and it keeps these
  # specs testing invalidation rather than testing the frozen clock.
  describe "invalidation" do
    it "recomputes after a salary is recorded" do
      get "/api/v1/analytics/overview"
      expect(json["total_annual_cents"]).to eq(10_000_000)

      travel 1.second
      other = create(:employee, job_level: level)
      Salaries::RecordChange.new(employee: other, amount_cents: 5_000_000, currency: "USD",
        effective_from: 1.month.ago.to_date, change_reason: "hire").call

      get "/api/v1/analytics/overview"

      expect(json["total_annual_cents"]).to eq(15_000_000)
    end

    # docs/architecture.md specifies the watermark as the salaries table
    # alone. Terminating someone changes headcount and payroll without
    # touching a salary row, so a salary-only watermark would keep serving
    # the old figure until somebody happened to record an unrelated raise.
    it "recomputes after an employee is terminated" do
      get "/api/v1/analytics/overview"
      expect(json["headcount"]).to eq(1)

      travel 1.second
      employee.update!(status: "terminated", terminated_on: Date.current)

      get "/api/v1/analytics/overview"

      expect(json["headcount"]).to eq(0)
    end

    it "recomputes after an employee moves department" do
      get "/api/v1/analytics/overview"
      before_move = json.dig("splits", "department").first["group"]

      travel 1.second
      employee.update!(department: create(:department, name: "Relocated"))

      get "/api/v1/analytics/overview"

      expect(json.dig("splits", "department").first["group"]).not_to eq(before_move)
    end
  end

  describe "key separation" do
    let!(:sales) { create(:department, name: "Sales") }

    it "does not serve one filter's answer for another" do
      get "/api/v1/analytics/overview"
      unfiltered = json["headcount"]

      get "/api/v1/analytics/overview", params: { department_id: sales.id }

      expect(json["headcount"]).to eq(0)
      expect(unfiltered).to eq(1)
    end

    it "keeps distribution group_by variants separate" do
      get "/api/v1/analytics/distribution", params: { group_by: "department" }
      expect(json["group_by"]).to eq("department")

      get "/api/v1/analytics/distribution", params: { group_by: "country" }
      expect(json["group_by"]).to eq("country")
    end

    it "keeps payroll trend month counts separate" do
      get "/api/v1/analytics/payroll_trend", params: { months: 3 }
      expect(json["points"].size).to eq(3)

      get "/api/v1/analytics/payroll_trend", params: { months: 6 }
      expect(json["points"].size).to eq(6)
    end

    it "caches each analytics endpoint under its own key" do
      get "/api/v1/analytics/overview"
      get "/api/v1/analytics/outliers"

      expect(json).to have_key("below_band")
    end
  end
end
