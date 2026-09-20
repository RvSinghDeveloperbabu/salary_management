require "rails_helper"

RSpec.describe PayrollTimeline do
  before do
    create(:exchange_rate, :identity, rate_on: Rates::SNAPSHOT_DATE)
    create(:exchange_rate, base_currency: "EUR", quote_currency: "USD",
      rate_ppm: 1_080_000, rate_on: Rates::SNAPSHOT_DATE)
  end

  # The clock is frozen at 2026-06-15 (see rails_helper), so every date
  # below is fixed and every expectation can be worked out by hand.
  def salary_for(employee, cents:, from:, to: nil, currency: "USD")
    create(:salary, employee: employee, amount_cents: cents, currency: currency,
      effective_from: from, effective_to: to, change_reason: "hire")
  end

  def month(points, label) = points.find { |p| p.month == label }

  describe "#call" do
    it "returns one point per month, oldest first" do
      points = described_class.new(months: 3).call

      expect(points.map(&:month)).to eq([ "2026-04", "2026-05", "2026-06" ])
    end

    it "defaults to 24 months" do
      expect(described_class.new.call.size).to eq(24)
    end

    it "returns zeroes rather than nothing when there is no payroll at all" do
      points = described_class.new(months: 2).call

      expect(points.map(&:total_cents)).to eq([ 0, 0 ])
      expect(points.map(&:headcount)).to eq([ 0, 0 ])
    end

    # A five-employee fixture with hand-computed monthly totals, as
    # docs/build-plan.md step 21 specifies.
    describe "a five-employee organisation" do
      let!(:points) do
        # Employed throughout at 100k.
        salary_for(create(:employee, hired_on: Date.new(2024, 1, 1)),
          cents: 10_000_000, from: Date.new(2024, 1, 1))

        # Hired 2026-05-01 at 60k, so absent from April.
        salary_for(create(:employee, hired_on: Date.new(2026, 5, 1)),
          cents: 6_000_000, from: Date.new(2026, 5, 1))

        # A raise on 2026-06-01: 80k until May, 90k from June.
        riser = create(:employee, hired_on: Date.new(2025, 1, 1))
        salary_for(riser, cents: 8_000_000, from: Date.new(2025, 1, 1), to: Date.new(2026, 5, 31))
        salary_for(riser, cents: 9_000_000, from: Date.new(2026, 6, 1))

        # Left on 2026-05-15, so counted in April but not in May.
        leaver = create(:employee, :terminated,
          hired_on: Date.new(2024, 1, 1), terminated_on: Date.new(2026, 5, 15))
        salary_for(leaver, cents: 5_000_000,
          from: Date.new(2024, 1, 1), to: Date.new(2026, 5, 15))

        # Paid in euros: 100,000 EUR x 1.08 = 108,000 USD.
        salary_for(create(:employee, hired_on: Date.new(2024, 1, 1)),
          cents: 10_000_000, from: Date.new(2024, 1, 1), currency: "EUR")

        described_class.new(months: 3).call
      end

      # 100k + 80k + 50k + 108k = 338k. The May hire is not yet employed.
      it "totals April correctly" do
        expect(month(points, "2026-04").total_cents).to eq(33_800_000)
        expect(month(points, "2026-04").headcount).to eq(4)
      end

      # 100k + 60k + 80k + 108k = 348k. The leaver has gone.
      it "totals May correctly, excluding the leaver" do
        expect(month(points, "2026-05").total_cents).to eq(34_800_000)
        expect(month(points, "2026-05").headcount).to eq(4)
      end

      # 100k + 60k + 90k + 108k = 358k. The raise has taken effect.
      it "totals June correctly, with the raise applied" do
        expect(month(points, "2026-06").total_cents).to eq(35_800_000)
        expect(month(points, "2026-06").headcount).to eq(4)
      end

      it "shows payroll rising across the three months" do
        expect(points.map(&:total_cents)).to eq([ 33_800_000, 34_800_000, 35_800_000 ])
      end
    end

    describe "boundary handling" do
      let!(:employee) { create(:employee, hired_on: Date.new(2026, 1, 1)) }

      it "counts a salary effective exactly on the month end" do
        salary_for(employee, cents: 10_000_000, from: Date.new(2026, 4, 30))

        expect(month(described_class.new(months: 3).call, "2026-04").total_cents)
          .to eq(10_000_000)
      end

      it "does not count a salary starting the day after the month end" do
        salary_for(employee, cents: 10_000_000, from: Date.new(2026, 5, 1))

        expect(month(described_class.new(months: 3).call, "2026-04").total_cents).to eq(0)
      end

      it "counts a salary closing exactly on the month end" do
        salary_for(employee, cents: 10_000_000,
          from: Date.new(2026, 1, 1), to: Date.new(2026, 4, 30))

        expect(month(described_class.new(months: 3).call, "2026-04").total_cents)
          .to eq(10_000_000)
      end

      it "does not count a salary that closed the day before the month end" do
        salary_for(employee, cents: 10_000_000,
          from: Date.new(2026, 1, 1), to: Date.new(2026, 4, 29))

        expect(month(described_class.new(months: 3).call, "2026-04").total_cents).to eq(0)
      end

      # Projecting to 2026-06-30 would report a figure for days that have
      # not happened, which reads as a forecast rather than a fact.
      it "clamps the most recent boundary to today rather than projecting" do
        expect(described_class.new(months: 1).call.first.as_of).to eq(Date.new(2026, 6, 15))
      end
    end

    describe "filtering" do
      let(:engineering) { create(:department, name: "Engineering") }
      let(:sales) { create(:department, name: "Sales") }

      before do
        salary_for(create(:employee, department: engineering, hired_on: Date.new(2024, 1, 1)),
          cents: 10_000_000, from: Date.new(2024, 1, 1))
        salary_for(create(:employee, department: sales, hired_on: Date.new(2024, 1, 1)),
          cents: 20_000_000, from: Date.new(2024, 1, 1))
      end

      it "filters by department" do
        points = described_class.new(months: 1, filters: { department_id: engineering.id }).call

        expect(points.first.total_cents).to eq(10_000_000)
      end

      it "filters by country" do
        points = described_class.new(months: 1, filters: { country_code: "us" }).call

        expect(points.first.headcount).to eq(2)
      end
    end

    describe "months parameter" do
      it "clamps to a maximum" do
        expect(described_class.new(months: 10_000).call.size).to eq(described_class::MAX_MONTHS)
      end

      it "falls back to the default for zero or nonsense" do
        expect(described_class.new(months: 0).call.size).to eq(24)
        expect(described_class.new(months: "many").call.size).to eq(24)
      end
    end

    # CLAUDE.md non-negotiable 5 and docs/architecture.md: one query, folded
    # in Ruby. Not one query per month, and certainly not one per employee.
    describe "query discipline" do
      before do
        3.times do
          salary_for(create(:employee, hired_on: Date.new(2024, 1, 1)),
            cents: 10_000_000, from: Date.new(2024, 1, 1))
        end
      end

      it "reads the whole history in a single query regardless of month count" do
        queries = 0
        sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
          queries += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
        end

        described_class.new(months: 24).call

        ActiveSupport::Notifications.unsubscribe(sub)

        # One for the salary rows, one for the rate table.
        expect(queries).to eq(2)
      end
    end
  end
end
