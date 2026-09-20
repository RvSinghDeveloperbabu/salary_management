class Department < ApplicationRecord
  normalizes :name, with: ->(value) { value.strip }
  normalizes :cost_centre, with: ->(value) { value.strip.upcase }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :cost_centre, presence: true, uniqueness: true

  scope :alphabetical, -> { order(:name) }
end
