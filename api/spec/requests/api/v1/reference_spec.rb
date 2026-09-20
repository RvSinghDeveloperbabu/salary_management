require "rails_helper"

RSpec.describe "Api::V1::Reference" do
  def json = JSON.parse(response.body)

  describe "GET /api/v1/reference" do
    before { sign_in }

    let!(:engineering) { create(:department, name: "Engineering") }
    let!(:design) { create(:department, name: "Design") }
    let!(:l3) { create(:job_level, name: "L3", rank: 3) }
    let!(:l1) { create(:job_level, name: "L1", rank: 1) }

    before do
      # Reuse the departments and levels above rather than letting the
      # factory create more, so the ordering assertions below see exactly
      # the records they set up.
      create(:employee, country_code: "US", department: engineering, job_level: l3)
      create(:employee, country_code: "PL", department: design, job_level: l1)
      create(:exchange_rate, :identity, rate_on: Rates::SNAPSHOT_DATE)
    end

    it "returns every list needed to populate the filter bar" do
      get "/api/v1/reference"

      expect(response).to have_http_status(:ok)
      expect(json.keys).to include(
        "departments", "job_levels", "countries", "currencies",
        "statuses", "employment_types", "change_reasons", "sortable"
      )
    end

    it "orders departments alphabetically" do
      get "/api/v1/reference"

      expect(json["departments"].map { |d| d["name"] }).to eq([ "Design", "Engineering" ])
    end

    it "orders job levels by rank, not name" do
      get "/api/v1/reference"

      expect(json["job_levels"].map { |l| l["name"] }).to eq([ "L1", "L3" ])
    end

    # Derived from the employees on file, so the filter never offers a
    # country with nobody in it.
    it "returns only countries that employees are actually in" do
      get "/api/v1/reference"

      expect(json["countries"]).to eq([ "PL", "US" ])
    end

    it "returns the sortable keys, so the client cannot invent one" do
      get "/api/v1/reference"

      expect(json["sortable"]).to eq(EmployeeSearch::SORTABLE.keys)
    end

    it "returns the change reasons the salary form offers" do
      get "/api/v1/reference"

      expect(json["change_reasons"]).to eq(Salary::CHANGE_REASONS)
    end

    it "answers in a single request, so the filter bar needs no fan-out" do
      queries = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
        queries += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
      end

      get "/api/v1/reference"

      ActiveSupport::Notifications.unsubscribe(subscriber)

      # departments, levels, countries, rates, plus the session lookup.
      expect(queries).to be <= 6
    end
  end

  it "returns 401 when not signed in" do
    get "/api/v1/reference"

    expect(response).to have_http_status(:unauthorized)
  end
end
