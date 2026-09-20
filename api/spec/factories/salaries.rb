FactoryBot.define do
  factory :salary do
    employee

    # 100k, matching the pay_band factory midpoint so band arithmetic in
    # specs can be checked by hand.
    amount_cents { 10_000_000 }
    currency { "USD" }
    effective_from { 3.years.ago.to_date }
    change_reason { "hire" }

    trait :closed do
      effective_to { 1.year.ago.to_date }
    end

    trait :merit_raise do
      change_reason { "merit" }
      effective_from { 1.year.ago.to_date }
      amount_cents { 11_000_000 }
    end

    trait :below_band do
      amount_cents { 7_000_000 }
    end

    trait :above_band do
      amount_cents { 15_000_000 }
    end
  end
end
