require "rails_helper"

RSpec.describe Stats::Percentile do
  # Every expectation here is worked out by hand. The definition is
  # PostgreSQL's percentile_cont: rank = fraction * (n - 1), then linear
  # interpolation between the two neighbouring order statistics.
  describe ".of" do
    context "with an empty array" do
      it "is nil rather than zero, because no data is not a salary of zero" do
        expect(described_class.of([], Rational(1, 2))).to be_nil
      end
    end

    context "with one value" do
      it "returns that value for any percentile" do
        expect(described_class.of([ 42 ], Rational(1, 4))).to eq(42)
        expect(described_class.of([ 42 ], Rational(1, 2))).to eq(42)
        expect(described_class.of([ 42 ], Rational(3, 4))).to eq(42)
      end
    end

    context "with two values" do
      let(:values) { [ 10, 20 ] }

      # rank = 0.5 * 1 = 0.5, halfway between 10 and 20.
      it "interpolates the median halfway" do
        expect(described_class.of(values, Rational(1, 2))).to eq(15)
      end

      # rank = 0.25 * 1 = 0.25, a quarter of the way from 10 to 20.
      it "interpolates p25 a quarter of the way" do
        expect(described_class.of(values, Rational(1, 4))).to eq(Rational(25, 2))
      end
    end

    context "with an odd number of values" do
      let(:values) { [ 1, 2, 3, 4, 5 ] }

      # rank = 0.5 * 4 = 2, exactly the third element. No interpolation.
      it "returns the middle element as the median" do
        expect(described_class.of(values, Rational(1, 2))).to eq(3)
      end

      # rank = 0.25 * 4 = 1, exactly the second element.
      it "returns an exact order statistic when the rank is a whole number" do
        expect(described_class.of(values, Rational(1, 4))).to eq(2)
      end

      it "returns the minimum at 0" do
        expect(described_class.of(values, 0)).to eq(1)
      end

      it "returns the maximum at 1" do
        expect(described_class.of(values, 1)).to eq(5)
      end
    end

    context "with an even number of values" do
      let(:values) { [ 1, 2, 3, 4 ] }

      # rank = 0.5 * 3 = 1.5, halfway between 2 and 3.
      it "interpolates between the two middle values" do
        expect(described_class.of(values, Rational(1, 2))).to eq(Rational(5, 2))
      end

      # rank = 0.25 * 3 = 0.75, three quarters from 1 to 2.
      it "interpolates p25" do
        expect(described_class.of(values, Rational(1, 4))).to eq(Rational(7, 4))
      end

      # rank = 0.75 * 3 = 2.25, a quarter of the way from 3 to 4.
      it "interpolates p75" do
        expect(described_class.of(values, Rational(3, 4))).to eq(Rational(13, 4))
      end
    end

    # Floating point would make this 2.9999999999999996 or similar. Money
    # does not get to be approximately right.
    it "stays exact where floating point would not" do
      expect(described_class.of([ 0, 10 ], Rational(3, 10))).to eq(3)
      expect(described_class.of([ 0, 10 ], Rational(3, 10))).to be_a(Rational).or be_a(Integer)
    end

    it "accepts a float fraction for convenience" do
      expect(described_class.of([ 1, 2, 3, 4, 5 ], 0.5)).to eq(3)
    end

    it "rejects a fraction outside 0..1" do
      expect { described_class.of([ 1, 2 ], 1.5) }.to raise_error(ArgumentError)
      expect { described_class.of([ 1, 2 ], -0.1) }.to raise_error(ArgumentError)
    end

    it "handles repeated values" do
      expect(described_class.of([ 5, 5, 5, 5 ], Rational(1, 2))).to eq(5)
    end

    it "handles realistic salary cents" do
      # Five salaries, median is the third.
      salaries = [ 7_500_000, 9_000_000, 10_000_000, 12_500_000, 20_000_000 ]

      expect(described_class.of(salaries, Rational(1, 2))).to eq(10_000_000)
    end
  end

  describe ".integer_of" do
    it "rounds an interpolated value to whole cents" do
      # p25 of [1,2,3,4] is 7/4 = 1.75, which rounds to 2.
      expect(described_class.integer_of([ 1, 2, 3, 4 ], Rational(1, 4))).to eq(2)
    end

    it "returns an Integer, never a Rational or Float" do
      expect(described_class.integer_of([ 1, 2, 3, 4 ], Rational(1, 4))).to be_an(Integer)
    end

    it "is nil for an empty array" do
      expect(described_class.integer_of([], Rational(1, 2))).to be_nil
    end
  end
end
