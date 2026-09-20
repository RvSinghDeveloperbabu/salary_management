# Append-only, effective-dated salary history. See docs/decisions.md 1.
#
# Every historical number in this application is derived from this table: the
# payroll trend, "what were we paying them in March", and the stale-raise
# report all read it. A mutable amount column could answer none of them.
class CreateSalaries < ActiveRecord::Migration[8.1]
  def change
    create_table :salaries do |t|
      t.references :employee, null: false, foreign_key: true

      # Integer cents, per CLAUDE.md non-negotiable 1. bigint because an
      # annual salary in INR or IDR exceeds a 32-bit integer.
      t.bigint :amount_cents, null: false

      # The employee's local currency. Always stored next to the amount so a
      # bare integer can never be read in the wrong currency.
      t.string :currency, null: false, limit: 3

      t.date :effective_from, null: false

      # Null means "current". Closed by Salaries::RecordChange when a newer
      # row supersedes this one, inside the same transaction.
      t.date :effective_to

      t.string :change_reason, null: false

      # The user who recorded the change. The users table does not exist
      # until build-plan phase 4, so the foreign key is added there rather
      # than here. Nullable because seeded history has no human author.
      t.bigint :recorded_by_id

      t.timestamps
    end

    # One salary per employee per start date. This is what makes an
    # overlapping raise a database error rather than a reporting anomaly.
    add_index :salaries, [ :employee_id, :effective_from ], unique: true

    # docs/architecture.md also lists a (employee_id, effective_from DESC)
    # index. It is not created: SQLite scans an ordered index backwards at
    # the same cost, so a second copy would be redundant storage on the
    # largest table here. See the commit message.

    add_index :salaries, :recorded_by_id

    # Used by the analytics cache watermark, which keys on the most recent
    # salary write (build-plan step 23).
    add_index :salaries, :updated_at

    add_check_constraint :salaries, "amount_cents > 0", name: "salaries_positive_amount"

    add_check_constraint :salaries,
      "effective_to IS NULL OR effective_to >= effective_from",
      name: "salaries_period_ordered"

    add_check_constraint :salaries,
      "change_reason IN ('hire', 'merit', 'promotion', 'market_adjustment', 'correction')",
      name: "salaries_known_change_reason"
  end
end
