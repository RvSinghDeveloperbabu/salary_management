require "rails_helper"

RSpec.describe Salary do
  subject { build(:salary) }

  it "is valid with the factory defaults" do
    expect(subject).to be_valid
  end

  describe "associations" do
    it { is_expected.to belong_to(:employee) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:effective_from) }
    it { is_expected.to validate_length_of(:currency).is_equal_to(3) }
    it { is_expected.to validate_numericality_of(:amount_cents).only_integer.is_greater_than(0) }

    it "rejects an unknown change reason" do
      expect(build(:salary, change_reason: "vibes")).not_to be_valid
    end

    it "accepts every documented change reason" do
      described_class::CHANGE_REASONS.each do |reason|
        expect(build(:salary, change_reason: reason)).to be_valid, "expected #{reason} to be valid"
      end
    end

    it "rejects an end date before the start date" do
      salary = build(:salary,
        effective_from: 1.year.ago.to_date,
        effective_to: 2.years.ago.to_date)

      expect(salary).not_to be_valid
      expect(salary.errors[:effective_to]).to be_present
    end

    it "is refused by the database when the amount is not positive" do
      expect { build(:salary, amount_cents: 0).save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /salaries_positive_amount/)
    end
  end

  # docs/decisions.md 7. current_salary_id is maintained on write, so a
  # future-dated row would make it silently wrong the day it took effect.
  describe "future effective dates" do
    let(:employee) { create(:employee) }

    it "rejects a start date in the future" do
      salary = build(:salary, employee: employee, effective_from: Date.current + 1)

      expect(salary).not_to be_valid
      expect(salary.errors[:effective_from]).to include("cannot be in the future")
    end

    it "accepts a start date of today" do
      expect(build(:salary, employee: employee, effective_from: Date.current)).to be_valid
    end
  end

  describe "overlapping periods" do
    let(:employee) { create(:employee) }

    # Existing period: 3 years ago until 1 year ago.
    let!(:existing) do
      create(:salary, :closed,
        employee: employee,
        effective_from: 3.years.ago.to_date,
        effective_to: 1.year.ago.to_date)
    end

    it "rejects a period starting inside the existing one" do
      overlapping = build(:salary, employee: employee, effective_from: 2.years.ago.to_date)

      expect(overlapping).not_to be_valid
      expect(overlapping.errors[:base]).to include("salary period overlaps an existing one")
    end

    it "rejects a period that fully contains the existing one" do
      overlapping = build(:salary,
        employee: employee,
        effective_from: 4.years.ago.to_date,
        effective_to: Date.current)

      expect(overlapping).not_to be_valid
    end

    it "rejects a period starting on the existing end date" do
      # The existing row still covers that day, so this is a genuine overlap.
      overlapping = build(:salary, employee: employee, effective_from: 1.year.ago.to_date)

      expect(overlapping).not_to be_valid
    end

    it "accepts a period starting the day after the existing one ends" do
      successor = build(:salary,
        employee: employee,
        effective_from: 1.year.ago.to_date + 1)

      expect(successor).to be_valid
    end

    it "does not consider another employee's salary an overlap" do
      other = build(:salary, employee: create(:employee), effective_from: 2.years.ago.to_date)

      expect(other).to be_valid
    end

    it "does not treat a record as overlapping itself when reopened" do
      existing.effective_to = 6.months.ago.to_date

      expect(existing).to be_valid
    end

    it "is refused by the unique index when two rows share a start date" do
      duplicate = build(:salary, employee: employee, effective_from: existing.effective_from)

      expect { duplicate.save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  # CLAUDE.md non-negotiable 3.
  describe "append-only enforcement" do
    let(:salary) { create(:salary) }

    it "refuses to change the amount" do
      salary.amount_cents = 99_999_999

      expect { salary.save! }
        .to raise_error(ActiveRecord::ReadOnlyRecord, /append-only/)
    end

    it "refuses to change the currency" do
      salary.currency = "EUR"

      expect { salary.save! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "refuses to change the effective start date" do
      salary.effective_from = 2.years.ago.to_date

      expect { salary.save! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "refuses to move the row to a different employee" do
      salary.employee = create(:employee)

      expect { salary.save! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "names the offending attributes in the error" do
      salary.amount_cents = 1

      expect { salary.save! }.to raise_error(/amount_cents/)
    end

    # The one permitted update: closing a period when a newer row
    # supersedes it. Salaries::RecordChange depends on this.
    it "allows the end date to be set" do
      expect { salary.update!(effective_to: Date.current) }.not_to raise_error
      expect(salary.reload.effective_to).to eq(Date.current)
    end
  end

  describe "scopes" do
    let(:employee) { create(:employee) }
    let!(:old_salary) do
      create(:salary, :closed,
        employee: employee,
        effective_from: 3.years.ago.to_date,
        effective_to: 1.year.ago.to_date)
    end
    let!(:current_salary) do
      create(:salary, employee: employee, effective_from: 1.year.ago.to_date + 1)
    end

    it "open_ended returns only the row with no end date" do
      expect(described_class.open_ended).to contain_exactly(current_salary)
    end

    it "chronological orders oldest first" do
      expect(described_class.chronological).to eq([ old_salary, current_salary ])
    end

    it "most_recent_first orders newest first" do
      expect(described_class.most_recent_first).to eq([ current_salary, old_salary ])
    end

    describe ".effective_on" do
      it "finds the row covering a past date" do
        expect(described_class.effective_on(2.years.ago.to_date))
          .to contain_exactly(old_salary)
      end

      it "finds the open-ended row for today" do
        expect(described_class.effective_on(Date.current))
          .to contain_exactly(current_salary)
      end

      it "includes the row on its own start date" do
        expect(described_class.effective_on(old_salary.effective_from))
          .to contain_exactly(old_salary)
      end

      it "includes the row on its own end date" do
        expect(described_class.effective_on(old_salary.effective_to))
          .to contain_exactly(old_salary)
      end

      it "returns nothing for a date before anyone was paid" do
        expect(described_class.effective_on(10.years.ago.to_date)).to be_empty
      end
    end
  end

  describe "#open_ended?" do
    it "is true when there is no end date" do
      expect(build(:salary).open_ended?).to be(true)
    end

    it "is false once the period is closed" do
      expect(build(:salary, :closed).open_ended?).to be(false)
    end
  end
end
