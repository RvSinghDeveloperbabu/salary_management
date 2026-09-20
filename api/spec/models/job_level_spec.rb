require "rails_helper"

RSpec.describe JobLevel do
  subject { build(:job_level) }

  it "is valid with the factory defaults" do
    expect(subject).to be_valid
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    # Level names are normalised to upper case on write, so "l1" and "L1"
    # are the same name by construction.
    it { is_expected.to validate_uniqueness_of(:name).ignoring_case_sensitivity }
    it { is_expected.to validate_presence_of(:rank) }
    it { is_expected.to validate_uniqueness_of(:rank) }
    it { is_expected.to validate_numericality_of(:rank).only_integer.is_greater_than(0) }
  end

  describe "associations" do
    it { is_expected.to have_many(:pay_bands).dependent(:destroy) }
  end

  describe ".in_rank_order" do
    # The reason rank exists as a column. Ordering on the name would place
    # L10 between L1 and L2, which is wrong everywhere it is displayed.
    it "orders by rank, not by name" do
      create(:job_level, name: "L10", rank: 10)
      create(:job_level, name: "L2", rank: 2)
      create(:job_level, name: "L1", rank: 1)

      expect(described_class.in_rank_order.pluck(:name)).to eq([ "L1", "L2", "L10" ])
    end
  end

  describe "#band_for" do
    let(:level) { create(:job_level) }

    it "returns the band for the given country" do
      us_band = create(:pay_band, job_level: level, country_code: "US")
      create(:pay_band, :poland, job_level: level)

      expect(level.band_for("US")).to eq(us_band)
    end

    it "is case insensitive about the country code" do
      us_band = create(:pay_band, job_level: level, country_code: "US")

      expect(level.band_for("us")).to eq(us_band)
    end

    it "returns nil where no band is defined for that country" do
      expect(level.band_for("BR")).to be_nil
    end
  end
end
