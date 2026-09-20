class CreatePayBands < ActiveRecord::Migration[8.1]
  def change
    create_table :pay_bands do |t|
      t.references :job_level, null: false, foreign_key: true

      # ISO 3166-1 alpha-2. A band is per level *per country*: an L4 in
      # Poland and an L4 in the United States are not paid the same, and
      # collapsing them is what makes naive salary comparisons wrong.
      t.string :country_code, null: false, limit: 2

      # Integers, per CLAUDE.md non-negotiable 1. bigint because a yearly
      # salary in a weak currency overflows a 32-bit integer: 40,000,000 INR
      # is fine, but the column should not be the thing that decides.
      t.bigint :min_cents, null: false
      t.bigint :mid_cents, null: false
      t.bigint :max_cents, null: false

      # ISO 4217. Stored alongside the amount so a bare integer can never be
      # interpreted in the wrong currency.
      t.string :currency, null: false, limit: 3

      t.timestamps
    end

    add_index :pay_bands, [ :job_level_id, :country_code ], unique: true

    # Compa-ratio and outlier detection both assume min <= mid <= max. A
    # band that violates it produces silently wrong analytics rather than an
    # error, so the database refuses it.
    add_check_constraint :pay_bands,
      "min_cents <= mid_cents AND mid_cents <= max_cents",
      name: "pay_bands_ordered_bounds"

    add_check_constraint :pay_bands, "min_cents > 0", name: "pay_bands_positive_minimum"
  end
end
