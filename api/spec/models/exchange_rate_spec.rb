require "rails_helper"

RSpec.describe ExchangeRate do
  subject { build(:exchange_rate) }

  it "is valid with the factory defaults" do
    expect(subject).to be_valid
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:base_currency) }
    it { is_expected.to validate_presence_of(:quote_currency) }
    it { is_expected.to validate_presence_of(:rate_on) }
    it { is_expected.to validate_length_of(:base_currency).is_equal_to(3) }
    it { is_expected.to validate_length_of(:quote_currency).is_equal_to(3) }
    it { is_expected.to validate_numericality_of(:rate_ppm).only_integer.is_greater_than(0) }

    it "allows only one rate per pair per date" do
      existing = create(:exchange_rate)
      duplicate = build(:exchange_rate,
        base_currency: existing.base_currency,
        quote_currency: existing.quote_currency,
        rate_on: existing.rate_on)

      expect(duplicate).not_to be_valid
    end

    it "allows the same pair on a different date" do
      existing = create(:exchange_rate)
      later = build(:exchange_rate,
        base_currency: existing.base_currency,
        quote_currency: existing.quote_currency,
        rate_on: existing.rate_on + 1.day)

      expect(later).to be_valid
    end

    # Storing USD -> USD at 1_000_000 keeps the identity case out of the
    # conversion code and out of every caller.
    it "permits an identity rate" do
      expect(build(:exchange_rate, :identity)).to be_valid
    end

    it "is refused by the database when the rate is not positive" do
      rate = build(:exchange_rate, rate_ppm: 0)

      expect { rate.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /exchange_rates_positive_rate/)
    end
  end

  describe "normalisation" do
    it "upcases both currencies" do
      rate = create(:exchange_rate, base_currency: "eur", quote_currency: "usd")

      expect(rate.base_currency).to eq("EUR")
      expect(rate.quote_currency).to eq("USD")
    end
  end

  describe "#rate" do
    it "converts parts per million back to a decimal for display" do
      expect(build(:exchange_rate, rate_ppm: 1_100_000).rate).to eq(1.1)
    end

    it "is 1.0 for an identity rate" do
      expect(build(:exchange_rate, :identity).rate).to eq(1.0)
    end
  end

  describe ".for_pair" do
    it "finds a rate regardless of the case of the arguments" do
      rate = create(:exchange_rate, base_currency: "EUR", quote_currency: "USD")

      expect(described_class.for_pair("eur", "usd")).to contain_exactly(rate)
    end
  end
end
