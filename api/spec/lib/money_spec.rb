require "rails_helper"

RSpec.describe Money do
  describe "construction" do
    it "upcases the currency" do
      expect(described_class.new(cents: 100, currency: "usd").currency).to eq("USD")
    end

    it "accepts positional arguments" do
      expect(described_class.new(100, "USD").cents).to eq(100)
    end

    # The guard that makes CLAUDE.md non-negotiable 1 enforceable rather
    # than aspirational.
    it "refuses a float" do
      expect { described_class.new(cents: 100.5, currency: "USD") }
        .to raise_error(ArgumentError, /integer cents/)
    end

    it "refuses a BigDecimal" do
      expect { described_class.new(cents: BigDecimal("100"), currency: "USD") }
        .to raise_error(ArgumentError, /integer cents/)
    end

    it "refuses a currency that is not three letters" do
      expect { described_class.new(cents: 100, currency: "DOLLARS") }
        .to raise_error(ArgumentError, /3-letter/)
    end

    it "is frozen" do
      expect(described_class.new(cents: 100, currency: "USD")).to be_frozen
    end
  end

  describe "equality" do
    it "is equal by value" do
      expect(described_class.new(100, "USD")).to eq(described_class.new(100, "USD"))
    end

    it "differs when the currency differs" do
      expect(described_class.new(100, "USD")).not_to eq(described_class.new(100, "EUR"))
    end
  end

  describe "arithmetic" do
    let(:hundred) { described_class.new(10_000, "USD") }
    let(:fifty) { described_class.new(5_000, "USD") }

    it "adds within a currency" do
      expect(hundred + fifty).to eq(described_class.new(15_000, "USD"))
    end

    it "subtracts within a currency" do
      expect(hundred - fifty).to eq(described_class.new(5_000, "USD"))
    end

    # Adding PLN to USD is the bug this class exists to make impossible.
    it "refuses to add across currencies" do
      expect { hundred + described_class.new(5_000, "PLN") }
        .to raise_error(ArgumentError, /cannot combine USD with PLN/)
    end

    it "refuses to add a bare integer" do
      expect { hundred + 5_000 }.to raise_error(ArgumentError)
    end
  end

  describe "comparison" do
    it "orders within a currency" do
      expect(described_class.new(10_000, "USD")).to be > described_class.new(5_000, "USD")
    end

    it "is not comparable across currencies" do
      expect(described_class.new(10_000, "USD") <=> described_class.new(5_000, "PLN")).to be_nil
    end
  end

  describe "#zero?" do
    it "is true at zero" do
      expect(described_class.zero("USD")).to be_zero
    end

    it "is false otherwise" do
      expect(described_class.new(1, "USD")).not_to be_zero
    end
  end

  describe "#to_s" do
    it "groups thousands and shows two minor digits" do
      expect(described_class.new(123_456_789, "USD").to_s).to eq("1,234,567.89 USD")
    end

    it "pads a single minor digit" do
      expect(described_class.new(1_005, "EUR").to_s).to eq("10.05 EUR")
    end

    it "handles amounts below one unit" do
      expect(described_class.new(7, "USD").to_s).to eq("0.07 USD")
    end

    it "handles negatives" do
      expect(described_class.new(-123_456, "USD").to_s).to eq("-1,234.56 USD")
    end
  end
end
