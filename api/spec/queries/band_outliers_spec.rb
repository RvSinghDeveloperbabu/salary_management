require "rails_helper"

RSpec.describe BandOutliers do
  let(:level) { create(:job_level, name: "L3", rank: 3) }
  let(:engineering) { create(:department, name: "Engineering") }

  # Band is 80k / 100k / 120k in USD.
  let!(:band) { create(:pay_band, job_level: level, country_code: "US") }

  before { create(:exchange_rate, :identity, rate_on: Rates::SNAPSHOT_DATE) }

  def employee_paid(cents, from: 1.month.ago.to_date, **overrides)
    employee = create(:employee, {
      job_level: level, department: engineering, country_code: "US",
      hired_on: 5.years.ago.to_date
    }.merge(overrides))

    create(:salary, employee: employee, amount_cents: cents, currency: "USD",
      effective_from: from, change_reason: "hire")
    employee.update_column(:current_salary_id, employee.salaries.first.id)
    employee
  end

  describe "#below_band" do
    it "finds someone paid under the minimum" do
      underpaid = employee_paid(7_000_000)

      expect(described_class.new.below_band.map(&:employee_id)).to eq([ underpaid.id ])
    end

    it "ignores someone paid exactly at the minimum" do
      employee_paid(8_000_000)

      expect(described_class.new.below_band).to be_empty
    end

    it "ignores someone inside the band" do
      employee_paid(10_000_000)

      expect(described_class.new.below_band).to be_empty
    end

    # The person furthest below their band is the one to deal with today.
    it "orders worst first" do
      mild = employee_paid(7_900_000)
      severe = employee_paid(5_000_000)

      expect(described_class.new.below_band.map(&:employee_id)).to eq([ severe.id, mild.id ])
    end

    it "reports the shortfall in money, not just a ratio" do
      employee_paid(7_000_000)

      # 8,000,000 minimum - 7,000,000 paid.
      expect(described_class.new.below_band.first.shortfall_cents).to eq(1_000_000)
    end

    it "reports the compa-ratio against the midpoint" do
      employee_paid(7_000_000)

      expect(described_class.new.below_band.first.compa_ratio).to eq(0.7)
    end

    it "includes the band bounds, so a row explains itself" do
      employee_paid(7_000_000)

      finding = described_class.new.below_band.first
      expect(finding.band_min_cents).to eq(8_000_000)
      expect(finding.band_max_cents).to eq(12_000_000)
    end

    it "excludes terminated employees" do
      employee_paid(7_000_000, status: "terminated", terminated_on: 1.week.ago.to_date)

      expect(described_class.new.below_band).to be_empty
    end
  end

  describe "#above_band" do
    it "finds someone paid over the maximum" do
      overpaid = employee_paid(15_000_000)

      expect(described_class.new.above_band.map(&:employee_id)).to eq([ overpaid.id ])
    end

    it "ignores someone paid exactly at the maximum" do
      employee_paid(12_000_000)

      expect(described_class.new.above_band).to be_empty
    end

    it "orders furthest above first" do
      mild = employee_paid(12_500_000)
      extreme = employee_paid(20_000_000)

      expect(described_class.new.above_band.map(&:employee_id)).to eq([ extreme.id, mild.id ])
    end

    it "reports the excess as a positive shortfall figure" do
      employee_paid(15_000_000)

      expect(described_class.new.above_band.first.shortfall_cents).to eq(3_000_000)
    end
  end

  describe "#stale" do
    it "finds someone with no change in more than 18 months" do
      forgotten = employee_paid(10_000_000, from: 24.months.ago.to_date)

      expect(described_class.new.stale.map(&:employee_id)).to eq([ forgotten.id ])
    end

    it "ignores someone whose salary changed recently" do
      employee_paid(10_000_000, from: 3.months.ago.to_date)

      expect(described_class.new.stale).to be_empty
    end

    it "includes someone exactly at the threshold" do
      employee_paid(10_000_000, from: (Date.current << 18))

      expect(described_class.new.stale.size).to eq(1)
    end

    it "excludes someone one day inside the threshold" do
      employee_paid(10_000_000, from: (Date.current << 18) + 1)

      expect(described_class.new.stale).to be_empty
    end

    it "orders longest-waiting first" do
      recent = employee_paid(10_000_000, from: 19.months.ago.to_date)
      ancient = employee_paid(10_000_000, from: 48.months.ago.to_date)

      expect(described_class.new.stale.map(&:employee_id)).to eq([ ancient.id, recent.id ])
    end

    it "reports how many months it has been" do
      employee_paid(10_000_000, from: 24.months.ago.to_date)

      expect(described_class.new.stale.first.months_since_change).to eq(24)
    end

    # A stale salary is a stale salary whether or not the country has a
    # band defined. Requiring one would hide people behind a reference-data
    # gap.
    it "finds someone in a country with no band at all" do
      employee_paid(10_000_000, from: 24.months.ago.to_date, country_code: "BR")

      expect(described_class.new.stale.size).to eq(1)
      expect(described_class.new.stale.first.band_min_cents).to be_nil
    end
  end

  describe "overlap between categories" do
    it "reports someone both underpaid and stale in both lists" do
      employee = employee_paid(7_000_000, from: 30.months.ago.to_date)

      result = described_class.new

      expect(result.below_band.map(&:employee_id)).to eq([ employee.id ])
      expect(result.stale.map(&:employee_id)).to eq([ employee.id ])
    end
  end

  describe "band matching" do
    # A band is per level per country. Matching on level alone would
    # measure a Polish salary against a US band and flag the entire country.
    it "measures against the band for the employee's own country" do
      create(:pay_band, :poland, job_level: level)
      polish = employee_paid(13_000_000, country_code: "PL")
      Salary.find_by(employee_id: polish.id).update_column(:currency, "PLN")

      # Polish band is 120k/150k/180k, so 130k is inside it, while the US
      # band would call it above maximum.
      expect(described_class.new.above_band).to be_empty
    end

    it "does not match a band from a different level" do
      other_level = create(:job_level, name: "L6", rank: 6)
      create(:pay_band, job_level: other_level, country_code: "US",
        min_cents: 30_000_000, mid_cents: 35_000_000, max_cents: 40_000_000)

      employee_paid(10_000_000)

      expect(described_class.new.below_band).to be_empty
    end
  end

  describe "filtering" do
    let(:sales) { create(:department, name: "Sales") }

    before do
      employee_paid(7_000_000)
      employee_paid(7_000_000, department: sales)
    end

    it "filters by department" do
      expect(described_class.new(department_id: engineering.id).below_band.size).to eq(1)
    end

    it "filters by country" do
      expect(described_class.new(country_code: "US").below_band.size).to eq(2)
      expect(described_class.new(country_code: "PL").below_band).to be_empty
    end
  end

  describe "query discipline" do
    before { 5.times { employee_paid(7_000_000) } }

    it "answers all three questions from one population query" do
      queries = 0
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
        queries += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
      end

      result = described_class.new
      result.below_band
      result.above_band
      result.stale

      ActiveSupport::Notifications.unsubscribe(sub)

      # One for the population, one for the rate table.
      expect(queries).to eq(2)
    end

    it "instantiates no Employee objects" do
      allow(Employee).to receive(:instantiate).and_call_original

      described_class.new.below_band

      expect(Employee).not_to have_received(:instantiate)
    end
  end
end
