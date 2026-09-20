# The salary range for one level in one country.
#
# This is the table that makes "are we paying this person fairly?" answerable
# at all. Without it the analytics can only compare people to each other,
# which says nothing about whether the whole population is mispaid.
class PayBand < ApplicationRecord
  belongs_to :job_level

  normalizes :country_code, with: ->(value) { value.strip.upcase }
  normalizes :currency, with: ->(value) { value.strip.upcase }

  validates :country_code,
    presence: true,
    length: { is: 2 },
    uniqueness: { scope: :job_level_id, case_sensitive: false }
  validates :currency, presence: true, length: { is: 3 }
  validates :min_cents, :mid_cents, :max_cents,
    presence: true,
    numericality: { only_integer: true, greater_than: 0 }

  validate :bounds_must_be_ordered

  scope :in_country, ->(code) { where(country_code: code.to_s.upcase) }

  # Where an amount sits relative to this band. The three return values are
  # the three categories the outlier view reports.
  def position_of(amount_cents)
    return :below if amount_cents < min_cents
    return :above if amount_cents > max_cents

    :within
  end

  # Pay as a proportion of the band midpoint. 1.0 means paid exactly at mid;
  # 0.85 means 15% under it. This is the standard compensation measure and is
  # what the employee detail view shows.
  #
  # A ratio is not money, so a float is correct here. The underlying amounts
  # stay integers, per CLAUDE.md non-negotiable 1.
  def compa_ratio(amount_cents)
    return nil if mid_cents.to_i.zero?

    (amount_cents.to_f / mid_cents).round(4)
  end

  def includes?(amount_cents)
    position_of(amount_cents) == :within
  end

  private

  # Mirrors the pay_bands_ordered_bounds check constraint. The database is
  # the real guarantee; this exists so the failure arrives as a validation
  # error rather than a StatementInvalid.
  def bounds_must_be_ordered
    return if min_cents.blank? || mid_cents.blank? || max_cents.blank?

    errors.add(:mid_cents, "must be greater than or equal to min_cents") if mid_cents < min_cents
    errors.add(:max_cents, "must be greater than or equal to mid_cents") if max_cents < mid_cents
  end
end
