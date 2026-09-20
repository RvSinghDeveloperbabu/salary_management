# One row per salary an employee has held, with the dates it applied.
#
# Append-only: a raise is an INSERT. The only UPDATE ever performed on this
# table is closing effective_to on the row being superseded, and that happens
# inside Salaries::RecordChange, in the same transaction as the insert.
#
# Amounts are annual, in the employee's local currency.
class Salary < ApplicationRecord
  CHANGE_REASONS = %w[hire merit promotion market_adjustment correction].freeze

  # Stand-in for "no end date" when comparing periods in SQL. COALESCE to
  # this is far easier to read than branching on NULL in every clause.
  OPEN_ENDED = Date.new(9999, 12, 31).freeze

  # The attributes that record what was paid. Changing any of them rewrites
  # history, which is the single thing this table exists to prevent.
  # effective_to is absent deliberately: closing a period is how a row is
  # superseded, and that is a legitimate write.
  IMMUTABLE_ATTRIBUTES = %w[
    employee_id amount_cents currency effective_from change_reason recorded_by_id
  ].freeze

  belongs_to :employee

  enum :change_reason, CHANGE_REASONS.index_by(&:itself), validate: true

  normalizes :currency, with: ->(value) { value.strip.upcase }

  validates :amount_cents,
    presence: true,
    numericality: { only_integer: true, greater_than: 0 }
  validates :currency, presence: true, length: { is: 3 }
  validates :effective_from,
    presence: true,
    uniqueness: { scope: :employee_id, message: "already has a salary starting on that date" }

  validate :effective_from_must_not_be_in_the_future
  validate :period_must_be_ordered
  validate :must_not_overlap_an_existing_period

  before_update :reject_history_rewrite

  scope :open_ended, -> { where(effective_to: nil) }
  scope :chronological, -> { order(:effective_from) }
  scope :most_recent_first, -> { order(effective_from: :desc) }

  # The row in force on a given date. Used to reconstruct payroll as of any
  # past month end.
  scope :effective_on, ->(date) {
    where(effective_from: ..date)
      .where("COALESCE(effective_to, :open) >= :date", open: OPEN_ENDED, date: date)
  }

  def open_ended?
    effective_to.nil?
  end

  private

  # docs/decisions.md 7. current_salary_id is maintained on write, so a
  # future-dated row would make it silently wrong on the day it took effect.
  def effective_from_must_not_be_in_the_future
    return if effective_from.blank?

    errors.add(:effective_from, "cannot be in the future") if effective_from > Date.current
  end

  def period_must_be_ordered
    return if effective_from.blank? || effective_to.blank?

    errors.add(:effective_to, "cannot be before the start date") if effective_to < effective_from
  end

  # Two salaries covering the same day means every historical query has two
  # answers. The unique index catches identical start dates; this catches
  # periods that straddle each other.
  def must_not_overlap_an_existing_period
    return if employee_id.blank? || effective_from.blank?

    siblings = Salary.where(employee_id: employee_id)
    siblings = siblings.where.not(id: id) if persisted?

    overlapping = siblings.where(
      "effective_from <= :self_to AND COALESCE(effective_to, :open) >= :self_from",
      self_to: effective_to || OPEN_ENDED,
      self_from: effective_from,
      open: OPEN_ENDED
    )

    errors.add(:base, "salary period overlaps an existing one") if overlapping.exists?
  end

  # CLAUDE.md non-negotiable 3. Corrections are new rows with
  # change_reason: :correction, never edits to an existing one.
  def reject_history_rewrite
    rewritten = changed & IMMUTABLE_ATTRIBUTES
    return if rewritten.empty?

    raise ActiveRecord::ReadOnlyRecord,
      "salaries are append-only; #{rewritten.join(', ')} cannot be changed. " \
      "Record a new salary with change_reason: :correction instead."
  end
end
