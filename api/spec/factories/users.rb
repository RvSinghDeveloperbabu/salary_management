FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "hr#{n}@example.com" }
    password { "compensation2026" }
    password_confirmation { "compensation2026" }
  end
end
