require "rails_helper"

RSpec.describe PayBand do
  subject { build(:pay_band) }

  it "is valid with the factory defaults" do
    expect(subject).to be_valid
  end

  describe "validations" do
    it { is_expected.to belong_to(:job_level) }
    it { is_expected.to validate_presence_of(:country_code) }
    it { is_expected.to validate_length_of(:country_code).is_equal_to(2) }
    it { is_expected.to validate_length_of(:currency).is_equal_to(3) }
    it { is_expected.to validate_numericality_of(:min_cents).only_integer.is_greater_than(0) }

    it "allows only one band per level per country" do
      existing = create(:pay_band)
      duplicate = build(:pay_band,
        job_level: existing.job_level,
        country_code: existing.country_code)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:country_code]).to be_present
    end

    it "allows the same level in a different country" do
      existing = create(:pay_band, country_code: "US")
      other = build(:pay_band, :poland, job_level: existing.job_level)

      expect(other).to be_valid
    end

    it "rejects a midpoint below the minimum" do
      band = build(:pay_band, min_cents: 10_000_000, mid_cents: 9_000_000, max_cents: 12_000_000)

      expect(band).not_to be_valid
      expect(band.errors[:mid_cents]).to be_present
    end

    it "rejects a maximum below the midpoint" do
      band = build(:pay_band, min_cents: 8_000_000, mid_cents: 10_000_000, max_cents: 9_000_000)

      expect(band).not_to be_valid
      expect(band.errors[:max_cents]).to be_present
    end

    # The validation is a convenience. The database is the actual guarantee,
    # because analytics read rows the application did not necessarily write.
    it "is refused by the database even when validations are skipped" do
      band = build(:pay_band, min_cents: 10_000_000, mid_cents: 9_000_000, max_cents: 12_000_000)

      expect { band.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /pay_bands_ordered_bounds/)
    end
  end

  describe "normalisation" do
    it "upcases the country code and currency" do
      band = create(:pay_band, country_code: "pl", currency: "pln")

      expect(band.country_code).to eq("PL")
      expect(band.currency).to eq("PLN")
    end
  end

  # Band is 80k / 100k / 120k in the factory.
  describe "#position_of" do
    let(:band) { build(:pay_band) }

    it "reports below for an amount under the minimum" do
      expect(band.position_of(7_999_999)).to eq(:below)
    end

    it "reports within at exactly the minimum" do
      expect(band.position_of(8_000_000)).to eq(:within)
    end

    it "reports within at exactly the maximum" do
      expect(band.position_of(12_000_000)).to eq(:within)
    end

    it "reports above for an amount over the maximum" do
      expect(band.position_of(12_000_001)).to eq(:above)
    end
  end

  describe "#compa_ratio" do
    let(:band) { build(:pay_band) }

    it "is 1.0 at the midpoint" do
      expect(band.compa_ratio(10_000_000)).to eq(1.0)
    end

    it "is 0.8 at 80% of the midpoint" do
      expect(band.compa_ratio(8_000_000)).to eq(0.8)
    end

    it "is 1.25 at 125% of the midpoint" do
      expect(band.compa_ratio(12_500_000)).to eq(1.25)
    end

    it "rounds to four decimal places" do
      # 9_999_999 / 10_000_000 = 0.9999999
      expect(band.compa_ratio(9_999_999)).to eq(1.0)
    end
  end

  describe "#includes?" do
    let(:band) { build(:pay_band) }

    it "is true inside the band" do
      expect(band.includes?(10_000_000)).to be(true)
    end

    it "is false outside the band" do
      expect(band.includes?(20_000_000)).to be(false)
    end
  end
end
