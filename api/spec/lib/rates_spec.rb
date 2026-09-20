require "rails_helper"

RSpec.describe Rates do
  # Rates chosen so every expectation below can be checked by hand:
  #   1 EUR = 1.08 USD
  #   1 INR = 0.012 USD
  #   1 USD = 1 USD
  let!(:usd) { create(:exchange_rate, :identity, rate_on: described_class::SNAPSHOT_DATE) }
  let!(:eur) do
    create(:exchange_rate,
      base_currency: "EUR", quote_currency: "USD",
      rate_ppm: 1_080_000, rate_on: described_class::SNAPSHOT_DATE)
  end
  let!(:inr) do
    create(:exchange_rate,
      base_currency: "INR", quote_currency: "USD",
      rate_ppm: 12_000, rate_on: described_class::SNAPSHOT_DATE)
  end

  describe ".convert" do
    it "returns the amount unchanged at an identity rate" do
      expect(described_class.convert(10_000_000, 1_000_000)).to eq(10_000_000)
    end

    # 100,000.00 EUR x 1.08 = 108,000.00 USD
    it "converts euros by hand-checkable arithmetic" do
      expect(described_class.convert(10_000_000, 1_080_000)).to eq(10_800_000)
    end

    # 2,400,000.00 INR x 0.012 = 28,800.00 USD
    it "converts rupees by hand-checkable arithmetic" do
      expect(described_class.convert(240_000_000, 12_000)).to eq(2_880_000)
    end

    describe "rounding" do
      it "rounds a half up, away from zero" do
        # 1 x 0.5 = 0.5 -> 1
        expect(described_class.convert(1, 500_000)).to eq(1)
      end

      it "rounds 1.5 to 2" do
        expect(described_class.convert(3, 500_000)).to eq(2)
      end

      it "rounds below a half down" do
        # 1 x 0.4 = 0.4 -> 0
        expect(described_class.convert(1, 400_000)).to eq(0)
      end

      it "rounds negatives away from zero" do
        expect(described_class.convert(-1, 500_000)).to eq(-1)
      end
    end

    # docs/architecture.md documents this conversion as
    # (amount_cents * rate_ppm).fdiv(1_000_000).round, which is wrong: the
    # product exceeds the 53-bit float mantissa for realistic inputs and
    # loses a cent. This is the exact case that diverges.
    it "stays exact where the documented float formula does not" do
      cents = 400_029_407
      ppm = 83_123_457

      float_result = (cents * ppm).fdiv(1_000_000).round

      expect(described_class.convert(cents, ppm)).to eq(33_251_827_211)
      expect(float_result).to eq(33_251_827_212)
    end

    it "never returns a float" do
      expect(described_class.convert(10_000_000, 1_080_000)).to be_a(Integer)
    end
  end

  describe ".to_base" do
    it "converts euros to USD cents" do
      expect(described_class.to_base(10_000_000, "EUR")).to eq(10_800_000)
    end

    it "converts rupees to USD cents" do
      expect(described_class.to_base(240_000_000, "INR")).to eq(2_880_000)
    end

    it "leaves USD untouched via the identity row" do
      expect(described_class.to_base(10_000_000, "USD")).to eq(10_000_000)
    end

    it "is case insensitive" do
      expect(described_class.to_base(10_000_000, "eur")).to eq(10_800_000)
    end

    it "raises a clear error for a currency with no rate" do
      expect { described_class.to_base(1_000, "JPY") }
        .to raise_error(described_class::MissingRate, /no JPY -> USD rate/)
    end
  end

  describe ".table" do
    it "returns every currency for the snapshot date" do
      expect(described_class.table).to eq(
        "USD" => 1_000_000,
        "EUR" => 1_080_000,
        "INR" => 12_000
      )
    end

    it "is frozen, so callers cannot corrupt a shared lookup" do
      expect(described_class.table).to be_frozen
    end

    it "excludes rates for other dates" do
      create(:exchange_rate,
        base_currency: "GBP", quote_currency: "USD",
        rate_ppm: 1_270_000, rate_on: described_class::SNAPSHOT_DATE + 1)

      expect(described_class.table).not_to have_key("GBP")
    end

    it "returns an empty hash when nothing is seeded for that date" do
      expect(described_class.table(on: Date.new(1999, 1, 1))).to eq({})
    end
  end

  describe ".base?" do
    it "recognises the base currency in any case" do
      expect(described_class.base?("usd")).to be(true)
    end

    it "rejects other currencies" do
      expect(described_class.base?("EUR")).to be(false)
    end
  end

  describe "SNAPSHOT_DATE" do
    # docs/decisions.md 5: a fixed date is what keeps a payroll trend
    # showing compensation decisions rather than currency movement.
    it "is a fixed date, not today" do
      expect(described_class::SNAPSHOT_DATE).to eq(Date.new(2026, 1, 1))
      expect(described_class::SNAPSHOT_DATE).to be_frozen
    end
  end
end
