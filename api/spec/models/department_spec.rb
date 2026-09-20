require "rails_helper"

RSpec.describe Department do
  subject { build(:department) }

  it "is valid with the factory defaults" do
    expect(subject).to be_valid
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:cost_centre) }
    it { is_expected.to validate_uniqueness_of(:name).case_insensitive }
    # Cost centres are normalised to upper case on write, so case is not a
    # meaningful axis for the uniqueness check.
    it { is_expected.to validate_uniqueness_of(:cost_centre).ignoring_case_sensitivity }
  end

  describe "normalisation" do
    it "strips surrounding whitespace from the name" do
      department = create(:department, name: "  Engineering  ")

      expect(department.name).to eq("Engineering")
    end

    it "upcases the cost centre" do
      department = create(:department, cost_centre: "cc-0001")

      expect(department.cost_centre).to eq("CC-0001")
    end
  end

  describe ".alphabetical" do
    it "orders by name" do
      create(:department, name: "Sales")
      create(:department, name: "Engineering")
      create(:department, name: "Marketing")

      expect(described_class.alphabetical.pluck(:name))
        .to eq([ "Engineering", "Marketing", "Sales" ])
    end
  end
end
