require "rails_helper"

RSpec.describe "Api::V1::Analytics" do
  let(:engineering) { create(:department, name: "Engineering") }
  let(:sales) { create(:department, name: "Sales") }
  let(:l1) { create(:job_level, name: "L1", rank: 1) }
  let(:l2) { create(:job_level, name: "L2", rank: 2) }

  def json = JSON.parse(response.body)

  def pay(employee, cents, currency = "USD")
    Salaries::RecordChange.new(employee: employee, amount_cents: cents, currency: currency,
      effective_from: 1.year.ago.to_date, change_reason: "hire").call
  end

  before do
    create(:exchange_rate, :identity, rate_on: Rates::SNAPSHOT_DATE)
    create(:exchange_rate, base_currency: "EUR", quote_currency: "USD",
      rate_ppm: 1_080_000, rate_on: Rates::SNAPSHOT_DATE)
  end

  describe "authentication" do
    it "refuses the overview" do
      get "/api/v1/analytics/overview"
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses the distribution" do
      get "/api/v1/analytics/distribution"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/analytics/overview" do
    before { sign_in }

    # Four salaries: 100k, 200k, 300k, 400k. Every figure below is
    # checkable by hand.
    before do
      pay(create(:employee, department: engineering, job_level: l1, country_code: "US"), 10_000_000)
      pay(create(:employee, department: engineering, job_level: l2, country_code: "US"), 20_000_000)
      pay(create(:employee, department: sales, job_level: l1, country_code: "GB"), 30_000_000)
      pay(create(:employee, department: sales, job_level: l2, country_code: "GB"), 40_000_000)
    end

    it "reports headcount and total annual payroll" do
      get "/api/v1/analytics/overview"

      expect(response).to have_http_status(:ok)
      expect(json["headcount"]).to eq(4)
      expect(json["total_annual_cents"]).to eq(100_000_000)
    end

    it "states the currency and the snapshot date it converted at" do
      get "/api/v1/analytics/overview"

      expect(json["currency"]).to eq("USD")
      expect(json["as_of"]).to eq(Rates::SNAPSHOT_DATE.to_s)
    end

    it "reports mean and median" do
      get "/api/v1/analytics/overview"

      expect(json.dig("salary", "mean")).to eq(25_000_000)
      expect(json.dig("salary", "p50")).to eq(25_000_000)
    end

    it "reports the interquartile spread" do
      get "/api/v1/analytics/overview"

      expect(json.dig("salary", "p25")).to eq(17_500_000)
      expect(json.dig("salary", "p75")).to eq(32_500_000)
    end

    # Question 1 in docs/requirements.md.
    it "splits payroll by department" do
      get "/api/v1/analytics/overview"

      split = json.dig("splits", "department")
      expect(split.map { |g| g["group"] }).to eq([ "Engineering", "Sales" ])
      expect(split.find { |g| g["group"] == "Engineering" }["total_annual_cents"]).to eq(30_000_000)
      expect(split.find { |g| g["group"] == "Sales" }["total_annual_cents"]).to eq(70_000_000)
    end

    it "splits payroll by country" do
      get "/api/v1/analytics/overview"

      split = json.dig("splits", "country")
      expect(split.find { |g| g["group"] == "US" }["total_annual_cents"]).to eq(30_000_000)
      expect(split.find { |g| g["group"] == "GB" }["total_annual_cents"]).to eq(70_000_000)
    end

    it "splits payroll by level, ordered by seniority" do
      get "/api/v1/analytics/overview"

      expect(json.dig("splits", "job_level").map { |g| g["group"] }).to eq([ "L1", "L2" ])
    end

    it "converts foreign currency before totalling" do
      pay(create(:employee, department: sales, job_level: l1), 10_000_000, "EUR")

      get "/api/v1/analytics/overview"

      # 100,000,000 + (10,000,000 x 1.08)
      expect(json["total_annual_cents"]).to eq(110_800_000)
    end

    it "excludes terminated employees" do
      pay(create(:employee, :terminated, department: sales, job_level: l1), 99_000_000)

      get "/api/v1/analytics/overview"

      expect(json["headcount"]).to eq(4)
    end

    it "honours a department filter" do
      get "/api/v1/analytics/overview", params: { department_id: engineering.id }

      expect(json["headcount"]).to eq(2)
      expect(json["total_annual_cents"]).to eq(30_000_000)
    end

    it "reports nil statistics rather than zeroes for an empty population" do
      get "/api/v1/analytics/overview", params: { country_code: "BR" }

      expect(json["headcount"]).to eq(0)
      expect(json.dig("salary", "p50")).to be_nil
      expect(json.dig("salary", "mean")).to be_nil
    end

    it "returns every money figure as an integer" do
      get "/api/v1/analytics/overview"

      expect(json["total_annual_cents"]).to be_an(Integer)
      expect(json.dig("salary", "p50")).to be_an(Integer)
    end
  end

  describe "GET /api/v1/analytics/distribution" do
    before { sign_in }

    before do
      pay(create(:employee, department: engineering, job_level: l1), 10_000_000)
      pay(create(:employee, department: engineering, job_level: l1), 20_000_000)
      pay(create(:employee, department: engineering, job_level: l2), 30_000_000)
      pay(create(:employee, department: sales, job_level: l2), 40_000_000)
    end

    it "defaults to grouping by department" do
      get "/api/v1/analytics/distribution"

      expect(json["group_by"]).to eq("department")
      expect(json["groups"].map { |g| g["group"] }).to eq([ "Engineering", "Sales" ])
    end

    # Question 2: the median and spread at each level.
    it "reports median and quartiles per group" do
      get "/api/v1/analytics/distribution", params: { group_by: "job_level" }

      l1_group = json["groups"].find { |g| g["group"] == "L1" }
      expect(l1_group["count"]).to eq(2)
      expect(l1_group["p50"]).to eq(15_000_000)
      expect(l1_group["min"]).to eq(10_000_000)
      expect(l1_group["max"]).to eq(20_000_000)
    end

    it "includes the interquartile range for the band on the chart" do
      get "/api/v1/analytics/distribution", params: { group_by: "job_level" }

      expect(json["groups"].first).to have_key("interquartile_range")
    end

    it "groups by country" do
      get "/api/v1/analytics/distribution", params: { group_by: "country" }

      expect(json["group_by"]).to eq("country")
    end

    # Question 6: for the same level, how does pay differ between
    # departments? Filter to a level, group by department.
    it "answers how one level differs across departments" do
      get "/api/v1/analytics/distribution",
        params: { group_by: "department", job_level_id: l2.id }

      expect(json["groups"].find { |g| g["group"] == "Engineering" }["p50"]).to eq(30_000_000)
      expect(json["groups"].find { |g| g["group"] == "Sales" }["p50"]).to eq(40_000_000)
    end

    it "rejects an arbitrary group_by with 400" do
      get "/api/v1/analytics/distribution", params: { group_by: "password_digest" }

      expect(response).to have_http_status(:bad_request)
      expect(json.dig("error", "code")).to eq("invalid_parameter")
    end

    it "returns an empty group list rather than failing when nothing matches" do
      get "/api/v1/analytics/distribution", params: { country_code: "BR" }

      expect(response).to have_http_status(:ok)
      expect(json["groups"]).to eq([])
    end
  end
end
