require "rails_helper"

RSpec.describe Stats::Distribution do
  describe ".of" do
    context "with no values" do
      subject(:summary) { described_class.of([]) }

      it "reports a count of zero" do
        expect(summary.count).to eq(0)
        expect(summary).to be_empty
      end

      # Nil, not zero. "We have no data for Brazil" and "everyone in Brazil
      # is paid nothing" must not look the same on a dashboard.
      it "reports nil statistics rather than zeroes" do
        expect(summary.mean).to be_nil
        expect(summary.p50).to be_nil
        expect(summary.min).to be_nil
        expect(summary.max).to be_nil
      end

      it "reports a sum of zero, which is the one number that is meaningful" do
        expect(summary.sum).to eq(0)
      end
    end

    context "with one value" do
      subject(:summary) { described_class.of([ 10_000_000 ]) }

      it "reports every statistic as that value" do
        expect(summary.count).to eq(1)
        expect(summary.sum).to eq(10_000_000)
        expect(summary.mean).to eq(10_000_000)
        expect(summary.min).to eq(10_000_000)
        expect(summary.p25).to eq(10_000_000)
        expect(summary.p50).to eq(10_000_000)
        expect(summary.p75).to eq(10_000_000)
        expect(summary.max).to eq(10_000_000)
      end

      it "reports a zero interquartile range" do
        expect(summary.interquartile_range).to eq(0)
      end
    end

    # Four salaries chosen so every statistic can be checked by hand:
    # 100k, 200k, 300k, 400k in cents.
    context "with four values" do
      subject(:summary) do
        described_class.of([ 40_000_000, 10_000_000, 30_000_000, 20_000_000 ])
      end

      it "sorts the input, so callers need not" do
        expect(summary.min).to eq(10_000_000)
        expect(summary.max).to eq(40_000_000)
      end

      it "counts and sums" do
        expect(summary.count).to eq(4)
        expect(summary.sum).to eq(100_000_000)
      end

      it "computes the mean" do
        expect(summary.mean).to eq(25_000_000)
      end

      # rank = 0.5 * 3 = 1.5, halfway between 20,000,000 and 30,000,000.
      it "computes the median by interpolation" do
        expect(summary.p50).to eq(25_000_000)
      end

      # rank = 0.25 * 3 = 0.75, three quarters from 10m to 20m.
      it "computes p25" do
        expect(summary.p25).to eq(17_500_000)
      end

      # rank = 0.75 * 3 = 2.25, a quarter from 30m to 40m.
      it "computes p75" do
        expect(summary.p75).to eq(32_500_000)
      end

      it "computes the interquartile range" do
        expect(summary.interquartile_range).to eq(15_000_000)
      end
    end

    describe "integer discipline" do
      # Mean of 1, 2 is 1.5. Integer division would floor it to 1 and every
      # average in the application would drift low.
      it "rounds the mean rather than truncating it" do
        expect(described_class.of([ 1, 2 ]).mean).to eq(2)
      end

      it "returns integers for every money statistic" do
        summary = described_class.of([ 1, 2, 3, 4, 5, 6, 7 ])

        [ summary.mean, summary.min, summary.p25, summary.p50, summary.p75, summary.max ]
          .each { |value| expect(value).to be_an(Integer) }
      end

      it "never produces a Float" do
        summary = described_class.of([ 3, 1, 4, 1, 5, 9, 2, 6 ])

        expect(summary.to_h.values.grep(Float)).to be_empty
      end
    end

    describe "robustness" do
      it "ignores nils rather than raising" do
        expect(described_class.of([ 10, nil, 20, nil ]).count).to eq(2)
      end

      it "handles a large population without error" do
        summary = described_class.of((1..10_000).to_a)

        expect(summary.count).to eq(10_000)
        expect(summary.p50).to eq(5_001) # rank 4999.5 -> between 5000 and 5001
        expect(summary.min).to eq(1)
        expect(summary.max).to eq(10_000)
      end

      it "handles every value being identical" do
        summary = described_class.of([ 10_000_000 ] * 50)

        expect(summary.p25).to eq(10_000_000)
        expect(summary.p75).to eq(10_000_000)
        expect(summary.interquartile_range).to eq(0)
      end
    end

    describe "#to_h" do
      it "includes the interquartile range for the API payload" do
        expect(described_class.of([ 1, 2, 3, 4 ]).to_h).to include(:interquartile_range)
      end
    end
  end
end
