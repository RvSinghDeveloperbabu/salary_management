# A dated conversion rate between two currencies, stored as parts per
# million so no float ever touches money. See CLAUDE.md non-negotiable 2.
#
# Identity rows (USD -> USD at 1_000_000) are allowed and are seeded. Letting
# the table answer every pair, including the trivial one, keeps the special
# case out of Rates and out of every caller.
class ExchangeRate < ApplicationRecord
  PPM = 1_000_000

  normalizes :base_currency, with: ->(value) { value.strip.upcase }
  normalizes :quote_currency, with: ->(value) { value.strip.upcase }

  validates :base_currency, presence: true, length: { is: 3 }
  validates :quote_currency, presence: true, length: { is: 3 }
  validates :rate_ppm,
    presence: true,
    numericality: { only_integer: true, greater_than: 0 }
  validates :rate_on, presence: true
  validates :base_currency,
    uniqueness: {
      scope: [ :quote_currency, :rate_on ],
      case_sensitive: false,
      message: "already has a rate for that currency and date"
    }

  scope :on_date, ->(date) { where(rate_on: date) }
  scope :for_pair, ->(base, quote) {
    where(base_currency: base.to_s.upcase, quote_currency: quote.to_s.upcase)
  }

  # The rate as a decimal, for display only. Arithmetic uses rate_ppm.
  def rate
    rate_ppm.fdiv(PPM)
  end
end
