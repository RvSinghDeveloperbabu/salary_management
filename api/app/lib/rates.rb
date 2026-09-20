# Currency normalisation for cross-country comparison.
#
# Everything converts to USD at a single snapshot date, not at each salary's
# own effective date. See docs/decisions.md 5: converting a trend at moving
# rates mixes two signals, and an HR manager reading "payroll rose 6%" needs
# that to mean the organisation decided to pay more, not that the dollar
# moved against the rupee.
module Rates
  BASE_CURRENCY = "USD"
  PPM = 1_000_000
  HALF_PPM = PPM / 2

  # The one date all comparison converts at. Fixed rather than "today" so
  # analytics are reproducible and specs are deterministic.
  SNAPSHOT_DATE = Date.new(2026, 1, 1).freeze

  class MissingRate < StandardError; end

  class << self
    # Convert an integer amount into integer USD cents.
    #
    # docs/architecture.md documents this as:
    #
    #   (amount_cents * rate_ppm).fdiv(1_000_000).round
    #
    # That formula is wrong and this deliberately differs from it. fdiv
    # returns a Float, and the product overflows the 53-bit mantissa for
    # realistic inputs: 400029407 cents at 83123457 ppm yields 33251827212
    # through fdiv and 33251827211 through integer arithmetic. Losing a cent
    # per conversion across 10,000 employees is precisely the failure
    # CLAUDE.md non-negotiable 1 exists to prevent, so the float never
    # happens. The arithmetic below is integer end to end.
    def convert(amount_cents, rate_ppm)
      product = amount_cents * rate_ppm

      # Round half away from zero, without leaving the integers.
      if product.negative?
        -((-product + HALF_PPM) / PPM)
      else
        (product + HALF_PPM) / PPM
      end
    end

    # Convert a single amount to USD cents.
    #
    # Callers converting many rows should fetch `table` once and fold with
    # it rather than calling this per row, which would be a query per
    # employee (CLAUDE.md non-negotiable 5).
    def to_base(amount_cents, currency, on: SNAPSHOT_DATE)
      convert(amount_cents, ppm_for(currency, on: on))
    end

    # { "EUR" => 1_080_000, "USD" => 1_000_000, ... } for one date.
    #
    # Six rows. Fetched once per request and folded over in memory, which is
    # what keeps the analytics endpoints to a single query each.
    def table(on: SNAPSHOT_DATE)
      ExchangeRate
        .where(quote_currency: BASE_CURRENCY, rate_on: on)
        .pluck(:base_currency, :rate_ppm)
        .to_h
        .freeze
    end

    def ppm_for(currency, on: SNAPSHOT_DATE)
      code = currency.to_s.upcase
      rate = table(on: on)[code]

      raise MissingRate, "no #{code} -> #{BASE_CURRENCY} rate on #{on}" if rate.nil?

      rate
    end

    def base?(currency)
      currency.to_s.upcase == BASE_CURRENCY
    end
  end
end
