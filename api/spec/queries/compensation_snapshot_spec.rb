require "rails_helper"

RSpec.describe CompensationSnapshot do
  let(:engineering) { create(:department, name: "Engineering") }
  let(:sales) { create(:department, name: "Sales") }
  let(:l1) { create(:job_level, name: "L1", rank: 1) }
  let(:l2) { create(:job_level, name: "L2", rank: 2) }

  # 1 EUR = 1.08 USD, 1 INR = 0.012 USD.
  before do
    create(:exchange_rate, :identity, rate_on: Rates::SNAPSHOT_DATE)
    create(:exchange_rate, base_currency: "EUR", quote_currency: "USD",
      rate_ppm: 1_080_000, rate_on: Rates::SNAPSHOT_DATE)
    create(:exchange_rate, base_currency: "INR", quote_currency: "USD",
      rate_ppm: 12_000, rate_on: Rates::SNAPSHOT_DATE)
  end

  def pay(employee, cents, currency)
    Salaries::RecordChange.new(employee: employee, amount_cents: cents, currency: currency,
      effective_from: 1.year.ago.to_date, change_reason: "hire").call
  end

  describe "#amounts" do
    it "is empty when nobody has a salary" do
      create(:employee)

      expect(described_class.new.amounts).to be_empty
    end

    it "returns current salaries in USD cents" do
      pay(create(:employee), 10_000_000, "USD")

      expect(described_class.new.amounts).to eq([ 10_000_000 ])
    end

    # The whole reason the exchange_rates table exists: 100,000 EUR and
    # 2,400,000 INR are not comparable until they are the same currency.
    it "normalises every currency to USD" do
      pay(create(:employee), 10_000_000, "USD")
      pay(create(:employee), 10_000_000, "EUR")
      pay(create(:employee), 240_000_000, "INR")

      expect(described_class.new.amounts).to match_array([ 10_000_000, 10_800_000, 2_880_000 ])
    end

    it "excludes terminated employees by default" do
      pay(create(:employee), 10_000_000, "USD")
      pay(create(:employee, :terminated), 99_000_000, "USD")

      expect(described_class.new.amounts).to eq([ 10_000_000 ])
    end

    it "can be asked for terminated employees explicitly" do
      pay(create(:employee, :terminated), 99_000_000, "USD")

      expect(described_class.new(status: "terminated").amounts).to eq([ 99_000_000 ])
    end

    # Someone with no salary on file would otherwise drag every average
    # towards zero.
    it "excludes employees with no salary rather than counting them as zero" do
      pay(create(:employee), 10_000_000, "USD")
      create(:employee)

      expect(described_class.new.amounts).to eq([ 10_000_000 ])
    end

    it "drops rows whose currency has no seeded rate" do
      pay(create(:employee), 10_000_000, "USD")
      pay(create(:employee), 50_000_000, "BRL")

      expect(described_class.new.amounts).to eq([ 10_000_000 ])
    end

    it "rejects an unknown status" do
      expect { described_class.new(status: "sabbatical").amounts }
        .to raise_error(InvalidQueryParameter, /status/)
    end
  end

  describe "filtering" do
    let!(:eng_uk) { create(:employee, department: engineering, job_level: l1, country_code: "GB") }
    let!(:eng_us) { create(:employee, department: engineering, job_level: l2, country_code: "US") }
    let!(:sales_us) { create(:employee, department: sales, job_level: l1, country_code: "US") }

    before do
      pay(eng_uk, 1_000_000, "USD")
      pay(eng_us, 2_000_000, "USD")
      pay(sales_us, 4_000_000, "USD")
    end

    it "filters by department" do
      expect(described_class.new(department_id: engineering.id).amounts)
        .to match_array([ 1_000_000, 2_000_000 ])
    end

    it "filters by country" do
      expect(described_class.new(country_code: "US").amounts)
        .to match_array([ 2_000_000, 4_000_000 ])
    end

    it "filters by job level" do
      expect(described_class.new(job_level_id: l1.id).amounts)
        .to match_array([ 1_000_000, 4_000_000 ])
    end

    it "combines filters" do
      expect(described_class.new(department_id: engineering.id, country_code: "US").amounts)
        .to eq([ 2_000_000 ])
    end

    it "reports headcount for the filtered population" do
      expect(described_class.new(department_id: engineering.id).headcount).to eq(2)
    end

    it "reports the total for the filtered population" do
      expect(described_class.new.total_base_cents).to eq(7_000_000)
    end
  end

  describe "#grouped_amounts" do
    let!(:eng_a) { create(:employee, department: engineering, job_level: l1, country_code: "US") }
    let!(:eng_b) { create(:employee, department: engineering, job_level: l2, country_code: "GB") }
    let!(:sales_a) { create(:employee, department: sales, job_level: l1, country_code: "US") }

    before do
      pay(eng_a, 1_000_000, "USD")
      pay(eng_b, 2_000_000, "USD")
      pay(sales_a, 4_000_000, "USD")
    end

    it "groups by department" do
      expect(described_class.new.grouped_amounts("department")).to eq(
        "Engineering" => [ 1_000_000, 2_000_000 ],
        "Sales" => [ 4_000_000 ]
      )
    end

    it "groups by country" do
      expect(described_class.new.grouped_amounts("country")).to eq(
        "GB" => [ 2_000_000 ],
        "US" => [ 1_000_000, 4_000_000 ]
      )
    end

    it "groups by job level" do
      expect(described_class.new.grouped_amounts("job_level")).to eq(
        "L1" => [ 1_000_000, 4_000_000 ],
        "L2" => [ 2_000_000 ]
      )
    end

    # A chart with L10 between L1 and L2 is wrong, and rank is the column
    # that exists to prevent it.
    it "orders levels by seniority, not alphabetically" do
      l10 = create(:job_level, name: "L10", rank: 10)
      pay(create(:employee, job_level: l10), 9_000_000, "USD")

      expect(described_class.new.grouped_amounts("job_level").keys).to eq([ "L1", "L2", "L10" ])
    end

    it "orders departments alphabetically" do
      expect(described_class.new.grouped_amounts("department").keys).to eq([ "Engineering", "Sales" ])
    end

    it "rejects an arbitrary group_by" do
      expect { described_class.new.grouped_amounts("password_digest") }
        .to raise_error(InvalidQueryParameter, /group_by/)
    end

    it "respects filters" do
      expect(described_class.new(country_code: "US").grouped_amounts("department")).to eq(
        "Engineering" => [ 1_000_000 ],
        "Sales" => [ 4_000_000 ]
      )
    end
  end

  # CLAUDE.md non-negotiable 5: aggregate in SQL, or pluck and fold. Never
  # instantiate 10k models.
  describe "query discipline" do
    before { 5.times { pay(create(:employee), 1_000_000, "USD") } }

    it "instantiates no Employee objects" do
      allow(Employee).to receive(:instantiate).and_call_original

      described_class.new.amounts

      expect(Employee).not_to have_received(:instantiate)
    end

    it "answers a grouped question in two queries" do
      queries = 0
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
        queries += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
      end

      described_class.new.grouped_amounts("department")

      ActiveSupport::Notifications.unsubscribe(sub)

      # One for the population, one for the rate table.
      expect(queries).to eq(2)
    end
  end
end
