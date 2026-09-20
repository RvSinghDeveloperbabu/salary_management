FactoryBot.define do
  factory :pay_band do
    job_level
    country_code { "US" }
    currency { "USD" }

    # Round numbers so expectations in specs can be checked by hand, per
    # CLAUDE.md testing rules. 80k / 100k / 120k.
    min_cents { 8_000_000 }
    mid_cents { 10_000_000 }
    max_cents { 12_000_000 }

    trait :poland do
      country_code { "PL" }
      currency { "PLN" }
      min_cents { 12_000_000 }
      mid_cents { 15_000_000 }
      max_cents { 18_000_000 }
    end

    trait :india do
      country_code { "IN" }
      currency { "INR" }
      min_cents { 180_000_000 }
      mid_cents { 240_000_000 }
      max_cents { 300_000_000 }
    end
  end
end
