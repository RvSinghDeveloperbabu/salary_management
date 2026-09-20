class JobLevel < ApplicationRecord
  has_many :pay_bands, dependent: :destroy

  normalizes :name, with: ->(value) { value.strip.upcase }

  validates :name, presence: true, uniqueness: true
  validates :rank,
    presence: true,
    uniqueness: true,
    numericality: { only_integer: true, greater_than: 0 }

  # Levels are always presented seniority-ascending. Ordering on name would
  # put L10 between L1 and L2, which is why rank exists.
  scope :in_rank_order, -> { order(:rank) }

  # The band for this level in a given country, or nil where none is defined.
  def band_for(country_code)
    pay_bands.find_by(country_code: country_code.to_s.upcase)
  end
end
