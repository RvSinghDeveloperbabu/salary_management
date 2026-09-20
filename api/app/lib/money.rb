# An amount in minor units, tied to its currency.
#
# The point is not convenience, it is that an integer on its own carries no
# currency, and a salary figure without a currency is meaningless in an
# organisation that pays people in six of them. Pairing them makes
# "compare 8_000_000 to 8_000_000" impossible to write by accident when one
# is PLN and the other USD.
#
# Immutable: Data gives value equality and freezing for free.
Money = Data.define(:cents, :currency) do
  def initialize(cents:, currency:)
    unless cents.is_a?(Integer)
      raise ArgumentError, "Money requires integer cents, got #{cents.class}. " \
        "Floats are not permitted anywhere near money."
    end

    normalised = currency.to_s.strip.upcase
    raise ArgumentError, "Money requires a 3-letter currency code" unless normalised.length == 3

    super(cents: cents, currency: normalised)
  end

  def self.zero(currency)
    new(cents: 0, currency: currency)
  end

  def zero?
    cents.zero?
  end

  def +(other)
    assert_same_currency(other)
    with(cents: cents + other.cents)
  end

  def -(other)
    assert_same_currency(other)
    with(cents: cents - other.cents)
  end

  def <=>(other)
    return nil unless other.is_a?(Money) && other.currency == currency

    cents <=> other.cents
  end

  include Comparable

  # Display only. Never feed the result back into arithmetic.
  def to_s
    units, minor = cents.abs.divmod(100)
    sign = cents.negative? ? "-" : ""
    grouped = units.to_s.reverse.scan(/\d{1,3}/).join(",").reverse

    "#{sign}#{grouped}.#{format('%02d', minor)} #{currency}"
  end

  private

  def assert_same_currency(other)
    return if other.is_a?(Money) && other.currency == currency

    raise ArgumentError,
      "cannot combine #{currency} with #{other.is_a?(Money) ? other.currency : other.class}. " \
      "Normalise through Rates first."
  end
end
