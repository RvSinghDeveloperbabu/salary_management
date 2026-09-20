require "rails_helper"

RSpec.describe Salaries::RecordChange do
  let(:employee) { create(:employee, hired_on: 4.years.ago.to_date) }

  def record(**overrides)
    described_class.new(
      employee: employee,
      amount_cents: 11_000_000,
      currency: "USD",
      effective_from: 1.year.ago.to_date,
      change_reason: "merit",
      **overrides
    ).call
  end

  describe "the first salary for an employee" do
    it "creates the salary" do
      result = record(effective_from: 3.years.ago.to_date, change_reason: "hire")

      expect(result.salary).to be_persisted
      expect(result.salary.amount_cents).to eq(11_000_000)
    end

    it "reports that there was no previous salary" do
      expect(record.first_salary?).to be(true)
    end

    it "leaves the period open" do
      expect(record.salary.effective_to).to be_nil
    end

    it "points the employee at it" do
      result = record

      expect(employee.reload.current_salary_id).to eq(result.salary.id)
    end
  end

  describe "a subsequent raise" do
    let!(:original) do
      described_class.new(
        employee: employee,
        amount_cents: 10_000_000,
        currency: "USD",
        effective_from: 3.years.ago.to_date,
        change_reason: "hire"
      ).call.salary
    end

    it "closes the previous period the day before the new one opens" do
      new_start = 1.year.ago.to_date

      record(effective_from: new_start)

      expect(original.reload.effective_to).to eq(new_start - 1)
    end

    # The two periods must not both cover the same day, or every historical
    # query has two answers for it.
    it "leaves no day covered by both periods" do
      new_start = 1.year.ago.to_date
      result = record(effective_from: new_start)

      expect(original.reload.effective_to).to be < result.salary.effective_from
    end

    it "leaves no gap between the periods" do
      new_start = 1.year.ago.to_date
      result = record(effective_from: new_start)

      expect(result.salary.effective_from - original.reload.effective_to).to eq(1)
    end

    it "repoints the employee at the new salary" do
      result = record

      expect(employee.reload.current_salary_id).to eq(result.salary.id)
    end

    it "returns the superseded salary" do
      result = record

      expect(result.previous).to eq(original)
      expect(result.first_salary?).to be(false)
    end

    it "keeps the old row intact, amount untouched" do
      record

      expect(original.reload.amount_cents).to eq(10_000_000)
    end

    it "leaves exactly one open-ended salary" do
      record

      expect(employee.salaries.open_ended.count).to eq(1)
    end
  end

  describe "ordering" do
    let!(:original) do
      described_class.new(
        employee: employee,
        amount_cents: 10_000_000,
        currency: "USD",
        effective_from: 2.years.ago.to_date,
        change_reason: "hire"
      ).call.salary
    end

    it "refuses to insert history behind the current salary" do
      expect { record(effective_from: 3.years.ago.to_date) }
        .to raise_error(described_class::OutOfOrder, /not after the current salary/)
    end

    it "refuses a change effective on the same day as the current salary" do
      expect { record(effective_from: original.effective_from) }
        .to raise_error(described_class::OutOfOrder)
    end
  end

  describe "validation failures" do
    let!(:original) do
      described_class.new(
        employee: employee,
        amount_cents: 10_000_000,
        currency: "USD",
        effective_from: 2.years.ago.to_date,
        change_reason: "hire"
      ).call.salary
    end

    it "rejects a future effective date" do
      expect { record(effective_from: Date.current + 1) }
        .to raise_error(ActiveRecord::RecordInvalid, /future/)
    end

    it "rejects a non-positive amount" do
      expect { record(amount_cents: 0) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    # enum ... validate: true records a validation error rather than raising
    # on assignment, so this surfaces as a 422 rather than a 500.
    it "rejects an unknown change reason" do
      expect { record(change_reason: "vibes") }
        .to raise_error(ActiveRecord::RecordInvalid, /Change reason/)
    end
  end

  # The reason this is a service and not three controller statements.
  describe "atomicity" do
    let!(:original) do
      described_class.new(
        employee: employee,
        amount_cents: 10_000_000,
        currency: "USD",
        effective_from: 2.years.ago.to_date,
        change_reason: "hire"
      ).call.salary
    end

    it "does not close the previous period when the insert fails" do
      expect { record(effective_from: Date.current + 1) }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(original.reload.effective_to).to be_nil
    end

    it "leaves the current salary pointer unchanged when the insert fails" do
      expect { record(effective_from: Date.current + 1) }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(employee.reload.current_salary_id).to eq(original.id)
    end

    it "writes no salary row when the insert fails" do
      expect { record(effective_from: Date.current + 1) }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(employee.salaries.count).to eq(1)
    end

    it "writes no audit event when the insert fails" do
      expect { record(effective_from: Date.current + 1) }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(AuditEvent.for_subject(employee).where(action: "salary_recorded").count).to eq(1)
    end
  end

  describe "audit trail" do
    it "records an event against the employee" do
      result = record

      event = AuditEvent.for_subject(employee).most_recent_first.first

      expect(event.action).to eq("salary_recorded")
      expect(event.metadata["salary_id"]).to eq(result.salary.id)
      expect(event.metadata["amount_cents"]).to eq(11_000_000)
      expect(event.metadata["change_reason"]).to eq("merit")
    end

    it "captures what the salary superseded" do
      original = described_class.new(
        employee: employee,
        amount_cents: 10_000_000,
        currency: "USD",
        effective_from: 3.years.ago.to_date,
        change_reason: "hire"
      ).call.salary

      record

      event = AuditEvent.for_subject(employee).most_recent_first.first

      expect(event.metadata["previous_salary_id"]).to eq(original.id)
      expect(event.metadata["previous_amount_cents"]).to eq(10_000_000)
    end

    it "leaves the previous fields null for a first salary" do
      record

      event = AuditEvent.for_subject(employee).most_recent_first.first

      expect(event.metadata["previous_salary_id"]).to be_nil
    end
  end
end
