FactoryBot.define do
  factory :exchange_rate do
    base_currency { "EUR" }
    quote_currency { "USD" }
    rate_ppm { 1_100_000 }
    rate_on { SPEC_FROZEN_TIME.to_date }

    trait :identity do
      base_currency { "USD" }
      quote_currency { "USD" }
      rate_ppm { ExchangeRate::PPM }
    end
  end
end
