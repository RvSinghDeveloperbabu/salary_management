module Stats
  # Summary statistics over an array of integers, with no database
  # dependency of any kind.
  #
  # That independence is the point. docs/decisions.md 3 chose to fold
  # percentiles in Ruby rather than emulate percentile_cont with window
  # functions, because this is a pure function over an array: it can be
  # tested against values worked out by hand, in microseconds, with no
  # fixtures. The cost is roughly 10k integers crossing the boundary per
  # request, which is measured and cached.
  class Distribution
    P25 = Rational(1, 4)
    P50 = Rational(1, 2)
    P75 = Rational(3, 4)

    Summary = Data.define(:count, :sum, :mean, :min, :p25, :p50, :p75, :max) do
      # The middle half of the population. The single most useful number
      # for "is this level's pay consistent or all over the place".
      def interquartile_range
        return nil if p25.nil? || p75.nil?

        p75 - p25
      end

      def empty?
        count.zero?
      end

      def to_h
        super.merge(interquartile_range: interquartile_range)
      end
    end

    EMPTY = Summary.new(
      count: 0, sum: 0, mean: nil, min: nil, p25: nil, p50: nil, p75: nil, max: nil
    ).freeze

    def self.of(values)
      new(values).summary
    end

    def initialize(values)
      # Sorted once. Every percentile below reads the same ordered array,
      # so seven statistics cost one sort rather than seven.
      @sorted = values.compact.sort
    end

    def summary
      return EMPTY if sorted.empty?

      Summary.new(
        count: sorted.length,
        sum: sorted.sum,
        # Integer division would silently floor every average. Rational
        # keeps it exact until the single rounding at the end.
        mean: Rational(sorted.sum, sorted.length).round,
        min: sorted.first,
        p25: Percentile.integer_of(sorted, P25),
        p50: Percentile.integer_of(sorted, P50),
        p75: Percentile.integer_of(sorted, P75),
        max: sorted.last
      )
    end

    private

    attr_reader :sorted
  end
end
