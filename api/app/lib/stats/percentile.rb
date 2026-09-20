module Stats
  # Linear interpolation between order statistics — the same definition as
  # PostgreSQL's percentile_cont, so the numbers do not move if the database
  # is ever swapped. See docs/decisions.md 3 for why this is Ruby and not SQL.
  #
  # Arithmetic is done in Rational, not Float. These are cents, and a median
  # salary that is off by a fraction because of binary floating point is the
  # exact class of defect CLAUDE.md non-negotiable 1 exists to prevent.
  module Percentile
    module_function

    # values must already be sorted ascending. Sorting here would make
    # computing seven statistics cost seven sorts; Distribution sorts once.
    #
    # fraction is in 0..1, as a Rational for exactness.
    def of(sorted_values, fraction)
      return nil if sorted_values.empty?

      fraction = Rational(fraction) unless fraction.is_a?(Rational)
      raise ArgumentError, "fraction must be between 0 and 1" unless fraction.between?(0, 1)

      return sorted_values.first if sorted_values.one?

      # Position in the ordered set, where 0 is the minimum and n-1 the
      # maximum. p50 of [1,2,3,4] is rank 1.5, i.e. halfway between 2 and 3.
      rank = fraction * (sorted_values.length - 1)
      lower = rank.floor
      upper = rank.ceil

      return sorted_values[lower] if lower == upper

      gap = sorted_values[upper] - sorted_values[lower]

      sorted_values[lower] + (gap * (rank - lower))
    end

    # Rounded to whole units, for callers working in cents.
    def integer_of(sorted_values, fraction)
      value = of(sorted_values, fraction)

      value&.round
    end
  end
end
