require "rails_helper"

RSpec.describe "Api::V1::Salaries" do
  let!(:employee) { create(:employee, hired_on: 4.years.ago.to_date) }

  def json = JSON.parse(response.body)

  def record(**overrides)
    post "/api/v1/employees/#{employee.id}/salaries", params: {
      salary: {
        amount_cents: 11_000_000,
        currency: "USD",
        effective_from: 1.year.ago.to_date.to_s,
        change_reason: "merit"
      }.merge(overrides)
    }
  end

  describe "POST /api/v1/employees/:employee_id/salaries" do
    context "when signed in" do
      before { sign_in }

      it "records the first salary" do
        expect { record }.to change(Salary, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(json.dig("salary", "amount_cents")).to eq(11_000_000)
      end

      it "points the employee at the new salary" do
        record

        expect(employee.reload.current_salary_id).to eq(json.dig("salary", "id"))
      end

      it "attributes the change to the signed-in user" do
        user = sign_in
        record

        expect(Salary.last.recorded_by_id).to eq(user.id)
      end

      it "writes an audit event" do
        expect { record }.to change { AuditEvent.where(action: "salary_recorded").count }.by(1)
      end

      context "with an existing salary" do
        let!(:original) do
          Salaries::RecordChange.new(employee: employee, amount_cents: 10_000_000,
            currency: "USD", effective_from: 3.years.ago.to_date, change_reason: "hire").call.salary
        end

        it "closes the previous period" do
          new_start = 1.year.ago.to_date
          record(effective_from: new_start.to_s)

          expect(original.reload.effective_to).to eq(new_start - 1)
        end

        it "reports which salary was superseded" do
          record

          expect(json["previous_salary_id"]).to eq(original.id)
        end

        it "leaves the superseded amount untouched, because history is append-only" do
          record

          expect(original.reload.amount_cents).to eq(10_000_000)
        end

        # CLAUDE.md testing rules: overlapping effective_from -> 422.
        it "returns 422 for a date inside the existing period" do
          record(effective_from: 4.years.ago.to_date.to_s)

          expect(response).to have_http_status(:unprocessable_content)
        end

        it "returns 422 for a date equal to the current salary's start" do
          record(effective_from: original.effective_from.to_s)

          expect(response).to have_http_status(:unprocessable_content)
          expect(json.dig("error", "message")).to match(/not after the current salary/)
        end

        it "writes nothing when the change is rejected" do
          expect { record(effective_from: original.effective_from.to_s) }
            .not_to change(Salary, :count)

          expect(original.reload.effective_to).to be_nil
        end
      end

      # CLAUDE.md testing rules and docs/decisions.md 7: future date -> 422.
      it "returns 422 for a future effective date" do
        record(effective_from: (Date.current + 1).to_s)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("validation_failed")
        expect(json.dig("error", "details")).to have_key("effective_from")
      end

      it "accepts an effective date of today" do
        record(effective_from: Date.current.to_s)

        expect(response).to have_http_status(:created)
      end

      it "returns 422 for a non-positive amount" do
        record(amount_cents: 0)

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 422 for an unknown change reason" do
        record(change_reason: "vibes")

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 422 for an effective date that is not a date" do
        record(effective_from: "not-a-date")

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "message")).to match(/is not a date/)
      end

      it "returns 400 when the salary key is missing" do
        post "/api/v1/employees/#{employee.id}/salaries", params: { amount_cents: 100 }

        expect(response).to have_http_status(:bad_request)
      end

      it "returns 404 for an unknown employee" do
        post "/api/v1/employees/999999/salaries",
          params: { salary: { amount_cents: 1, currency: "USD",
                              effective_from: Date.current.to_s, change_reason: "merit" } }

        expect(response).to have_http_status(:not_found)
      end

      it "returns the amount as an integer, never a float" do
        record

        expect(json.dig("salary", "amount_cents")).to be_an(Integer)
      end
    end

    it "returns 401 when not signed in" do
      expect { record }.not_to change(Salary, :count)

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
