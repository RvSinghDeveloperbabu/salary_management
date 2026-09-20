class CreateExchangeRates < ActiveRecord::Migration[8.1]
  def change
    create_table :exchange_rates do |t|
      t.string :base_currency, null: false, limit: 3
      t.string :quote_currency, null: false, limit: 3

      # Rate x 1,000,000 as an integer, per CLAUDE.md non-negotiable 2.
      # bigint rather than integer: USD->IDR would be 15,000,000,000 ppm,
      # which overflows a 32-bit integer. None of the six seeded currencies
      # go near that, but the column should not be the reason it breaks.
      t.bigint :rate_ppm, null: false

      # Rates are dated even though docs/decisions.md 5 converts everything
      # at one snapshot. Storing the date is what lets as-of-date conversion
      # be added later without a migration.
      t.date :rate_on, null: false

      t.timestamps
    end

    add_index :exchange_rates, [ :base_currency, :quote_currency, :rate_on ],
      unique: true, name: "index_exchange_rates_on_pair_and_date"

    add_check_constraint :exchange_rates, "rate_ppm > 0", name: "exchange_rates_positive_rate"
  end
end
