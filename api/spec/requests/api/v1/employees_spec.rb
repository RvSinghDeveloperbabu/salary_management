require "rails_helper"

RSpec.describe "Api::V1::Employees" do
  let(:engineering) { create(:department, name: "Engineering") }
  let(:level) { create(:job_level, name: "L3", rank: 3) }

  def json = JSON.parse(response.body)

  describe "authentication" do
    # CLAUDE.md testing rules: unauthenticated request -> 401. Salary data
    # is the most sensitive thing here; every route is covered, not just one.
    it "refuses the directory" do
      get "/api/v1/employees"
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses an employee detail" do
      get "/api/v1/employees/#{create(:employee).id}"
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses creating an employee" do
      post "/api/v1/employees", params: { employee: { first_name: "A" } }
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses updating an employee" do
      patch "/api/v1/employees/#{create(:employee).id}", params: { employee: { first_name: "A" } }
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses recording a salary" do
      post "/api/v1/employees/#{create(:employee).id}/salaries", params: { salary: {} }
      expect(response).to have_http_status(:unauthorized)
    end

    it "leaks nothing about whether a record exists" do
      get "/api/v1/employees/999999"

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include("not found")
    end
  end

  describe "GET /api/v1/employees" do
    before { sign_in }

    let!(:ada) do
      create(:employee, first_name: "Ada", last_name: "Lovelace",
        department: engineering, job_level: level, country_code: "GB")
    end
    let!(:grace) { create(:employee, first_name: "Grace", last_name: "Hopper") }

    it "returns the directory" do
      get "/api/v1/employees"

      expect(response).to have_http_status(:ok)
      expect(json["employees"].size).to eq(2)
    end

    it "includes pagination metadata" do
      get "/api/v1/employees", params: { per_page: 1 }

      expect(json["pagination"]).to include(
        "page" => 1, "per_page" => 1, "total_count" => 2, "total_pages" => 2
      )
    end

    it "includes the department and level without an extra request" do
      get "/api/v1/employees"

      row = json["employees"].find { |e| e["first_name"] == "Ada" }
      expect(row.dig("department", "name")).to eq("Engineering")
      expect(row.dig("job_level", "name")).to eq("L3")
    end

    it "filters by search term" do
      get "/api/v1/employees", params: { q: "lovelace" }

      expect(json["employees"].map { |e| e["first_name"] }).to eq([ "Ada" ])
    end

    it "filters by department" do
      get "/api/v1/employees", params: { department_id: engineering.id }

      expect(json["employees"].size).to eq(1)
    end

    # CLAUDE.md testing rules: ?sort= with an arbitrary column -> 400, not a
    # query.
    it "rejects an arbitrary sort key with 400" do
      get "/api/v1/employees", params: { sort: "password_digest" }

      expect(response).to have_http_status(:bad_request)
      expect(json.dig("error", "code")).to eq("invalid_parameter")
    end

    it "rejects a SQL fragment in sort with 400 and runs no query" do
      get "/api/v1/employees", params: { sort: "id; DROP TABLE employees" }

      expect(response).to have_http_status(:bad_request)
      expect(Employee.count).to eq(2)
    end

    it "tells the client which sort keys are permitted" do
      get "/api/v1/employees", params: { sort: "nope" }

      expect(json.dig("error", "details", "sort").first).to include("name")
    end

    it "rejects an unknown status filter with 400" do
      get "/api/v1/employees", params: { status: "on_holiday" }

      expect(response).to have_http_status(:bad_request)
    end

    it "reports salary in cents with its currency, never a float" do
      Salaries::RecordChange.new(employee: ada, amount_cents: 10_000_000, currency: "GBP",
        effective_from: 1.year.ago.to_date, change_reason: "hire").call

      get "/api/v1/employees", params: { q: "lovelace" }

      salary = json["employees"].first["current_salary"]
      expect(salary["amount_cents"]).to eq(10_000_000)
      expect(salary["currency"]).to eq("GBP")
      expect(salary["amount_cents"]).to be_an(Integer)
    end

    it "returns a null current salary rather than omitting the key" do
      get "/api/v1/employees", params: { q: "hopper" }

      expect(json["employees"].first).to have_key("current_salary")
      expect(json["employees"].first["current_salary"]).to be_nil
    end
  end

  describe "GET /api/v1/employees/:id" do
    before { sign_in }

    let!(:employee) { create(:employee, department: engineering, job_level: level, country_code: "US") }
    let!(:band) { create(:pay_band, job_level: level, country_code: "US") }

    before do
      Salaries::RecordChange.new(employee: employee, amount_cents: 9_000_000, currency: "USD",
        effective_from: 3.years.ago.to_date, change_reason: "hire").call
      Salaries::RecordChange.new(employee: employee, amount_cents: 10_000_000, currency: "USD",
        effective_from: 1.year.ago.to_date, change_reason: "merit").call
    end

    it "returns the employee" do
      get "/api/v1/employees/#{employee.id}"

      expect(response).to have_http_status(:ok)
      expect(json.dig("employee", "id")).to eq(employee.id)
    end

    it "includes the full salary history, newest first" do
      get "/api/v1/employees/#{employee.id}"

      history = json.dig("employee", "salaries")
      expect(history.size).to eq(2)
      expect(history.first["amount_cents"]).to eq(10_000_000)
      expect(history.first["current"]).to be(true)
      expect(history.last["current"]).to be(false)
    end

    it "includes the pay band" do
      get "/api/v1/employees/#{employee.id}"

      expect(json.dig("employee", "pay_band", "mid_cents")).to eq(band.mid_cents)
    end

    # Band midpoint is 100k and the salary is 100k, so the ratio is exactly 1.
    it "includes the compa-ratio against the band" do
      get "/api/v1/employees/#{employee.id}"

      expect(json.dig("employee", "band_position", "compa_ratio")).to eq(1.0)
      expect(json.dig("employee", "band_position", "position")).to eq("within")
    end

    it "reports months since the last salary change" do
      get "/api/v1/employees/#{employee.id}"

      expect(json.dig("employee", "months_since_last_change")).to eq(12)
    end

    it "returns null band_position when no band exists for that country" do
      other = create(:employee, country_code: "BR", job_level: level)

      get "/api/v1/employees/#{other.id}"

      expect(json.dig("employee", "band_position")).to be_nil
    end

    it "returns 404 for an unknown id" do
      get "/api/v1/employees/999999"

      expect(response).to have_http_status(:not_found)
      expect(json.dig("error", "code")).to eq("not_found")
    end
  end

  describe "POST /api/v1/employees" do
    before { sign_in }

    let(:valid_params) do
      {
        employee: {
          first_name: "Katherine", last_name: "Johnson",
          email: "katherine@example.com", country_code: "US",
          department_id: engineering.id, job_level_id: level.id,
          employment_type: "full_time", status: "active",
          hired_on: 1.month.ago.to_date.to_s
        }
      }
    end

    it "creates an employee" do
      expect { post "/api/v1/employees", params: valid_params }
        .to change(Employee, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    it "assigns the employee code rather than accepting one" do
      post "/api/v1/employees", params: valid_params

      expect(json.dig("employee", "employee_code")).to match(/\AEMP-\d{5}\z/)
    end

    # CLAUDE.md testing rules: mass-assignment of employee_code and
    # current_salary_id must be rejected.
    it "ignores a supplied employee_code" do
      post "/api/v1/employees",
        params: { employee: valid_params[:employee].merge(employee_code: "HACKED-001") }

      expect(Employee.find(json.dig("employee", "id")).employee_code).not_to eq("HACKED-001")
    end

    it "ignores a supplied current_salary_id" do
      victim = create(:employee)
      salary = create(:salary, employee: victim)

      post "/api/v1/employees",
        params: { employee: valid_params[:employee].merge(current_salary_id: salary.id) }

      expect(Employee.find(json.dig("employee", "id")).current_salary_id).to be_nil
    end

    it "returns 422 with per-field detail for invalid input" do
      post "/api/v1/employees", params: { employee: valid_params[:employee].merge(email: "nope") }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("validation_failed")
      expect(json.dig("error", "details")).to have_key("email")
    end

    it "returns 400 when the employee key is missing entirely" do
      post "/api/v1/employees", params: { first_name: "Loose" }

      expect(response).to have_http_status(:bad_request)
    end

    it "writes an audit event" do
      expect { post "/api/v1/employees", params: valid_params }
        .to change { AuditEvent.where(action: "employee_created").count }.by(1)
    end
  end

  describe "PATCH /api/v1/employees/:id" do
    before { sign_in }

    let!(:employee) { create(:employee, first_name: "Ada", department: engineering, job_level: level) }

    it "updates permitted fields" do
      patch "/api/v1/employees/#{employee.id}", params: { employee: { first_name: "Augusta" } }

      expect(response).to have_http_status(:ok)
      expect(employee.reload.first_name).to eq("Augusta")
    end

    it "refuses to change the employee code" do
      original = employee.employee_code

      patch "/api/v1/employees/#{employee.id}", params: { employee: { employee_code: "HACKED" } }

      expect(employee.reload.employee_code).to eq(original)
    end

    # Repointing this directly would let the denormalised pointer disagree
    # with the salary history, and every analytics figure reads one or the
    # other.
    it "refuses to repoint the current salary" do
      salary = create(:salary, employee: create(:employee))

      patch "/api/v1/employees/#{employee.id}", params: { employee: { current_salary_id: salary.id } }

      expect(employee.reload.current_salary_id).to be_nil
    end

    it "returns 422 for an invalid change" do
      patch "/api/v1/employees/#{employee.id}", params: { employee: { email: "nope" } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 404 for an unknown employee" do
      patch "/api/v1/employees/999999", params: { employee: { first_name: "X" } }

      expect(response).to have_http_status(:not_found)
    end

    it "records which fields changed" do
      patch "/api/v1/employees/#{employee.id}", params: { employee: { first_name: "Augusta" } }

      expect(AuditEvent.where(action: "employee_updated").last.metadata["changed"])
        .to include("first_name")
    end
  end
end
