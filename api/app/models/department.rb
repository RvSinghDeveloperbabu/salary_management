class Department < ApplicationRecord
  # restrict rather than destroy: deleting a department must never delete
  # the compensation history of the people in it.
  has_many :employees, dependent: :restrict_with_error

  normalizes :name, with: ->(value) { value.strip }
  normalizes :cost_centre, with: ->(value) { value.strip.upcase }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :cost_centre, presence: true, uniqueness: true

  scope :alphabetical, -> { order(:name) }
end
