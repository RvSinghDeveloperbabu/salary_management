require "rails_helper"

RSpec.describe "Api::V1::Analytics outliers" do
  let(:level) { create(:job_level, name: "L3", rank: 3) }
  let!(:band) { create(:pay_band, job_level: level, country_code: "US") }

  def json = JSON.parse(response.body)

  def employee_paid(cents, from: 1.month.ago.to_date)
    employee = create(:employee, job_level: level, country_code: "US",
      hired_on: 5.years.ago.to_date)
    salary = create(:salary, employee: employee, amount_cents: cents, currency: "USD",
      effective_from: from, change_reason: "hire")
    employee.update_column(:current_salary_id, salary.id)
    employee
  end

  before { create(:exchange_rate, :identity, rate_on: Rates::SNAPSHOT_DATE) }

  it "returns 401 when not signed in" do
    get "/api/v1/analytics/outliers"

    expect(response).to have_http_status(:unauthorized)
  end

  describe "GET /api/v1/analytics/outliers" do
    before { sign_in }

    it "returns all three categories with counts" do
      employee_paid(7_000_000)
      employee_paid(15_000_000)
      employee_paid(10_000_000, from: 30.months.ago.to_date)

      get "/api/v1/analytics/outliers"

      expect(response).to have_http_status(:ok)
      expect(json["counts"]).to eq("below_band" => 1, "above_band" => 1, "stale" => 1)
    end

    it "states the staleness threshold rather than leaving it implicit" do
      get "/api/v1/analytics/outliers"

      expect(json["stale_after_months"]).to eq(18)
    end

    it "gives each finding enough to explain itself" do
      employee = employee_paid(7_000_000)

      get "/api/v1/analytics/outliers"

      finding = json["below_band"].first
      expect(finding["employee_id"]).to eq(employee.id)
      expect(finding["full_name"]).to be_present
      expect(finding["amount_cents"]).to eq(7_000_000)
      expect(finding["band_min_cents"]).to eq(8_000_000)
      expect(finding["shortfall_cents"]).to eq(1_000_000)
      expect(finding["compa_ratio"]).to eq(0.7)
    end

    it "links each finding to the employee record" do
      employee = employee_paid(15_000_000)

      get "/api/v1/analytics/outliers"

      expect(json["above_band"].first["employee_id"]).to eq(employee.id)
    end

    it "returns empty lists rather than failing when nothing is wrong" do
      employee_paid(10_000_000)

      get "/api/v1/analytics/outliers"

      expect(json["below_band"]).to eq([])
      expect(json["above_band"]).to eq([])
      expect(json["counts"]).to eq("below_band" => 0, "above_band" => 0, "stale" => 0)
    end

    it "honours a country filter" do
      employee_paid(7_000_000)

      get "/api/v1/analytics/outliers", params: { country_code: "PL" }

      expect(json["counts"]["below_band"]).to eq(0)
    end
  end
end
