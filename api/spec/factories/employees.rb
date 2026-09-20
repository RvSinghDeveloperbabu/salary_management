FactoryBot.define do
  factory :employee do
    department
    job_level

    sequence(:employee_code) { |n| format("EMP-%05d", n) }
    sequence(:last_name) { |n| "Employee#{n}" }
    sequence(:email) { |n| "employee#{n}@example.com" }
    first_name { "Ada" }

    country_code { "US" }
    employment_type { "full_time" }
    status { "active" }

    # Relative to the frozen clock in rails_helper, so tenure arithmetic is
    # the same on every run.
    hired_on { 3.years.ago.to_date }

    trait :terminated do
      status { "terminated" }
      terminated_on { 1.month.ago.to_date }
    end

    trait :in_poland do
      country_code { "PL" }
    end

    trait :in_india do
      country_code { "IN" }
    end

    trait :contractor do
      employment_type { "contract" }
    end

    trait :recently_hired do
      hired_on { 2.months.ago.to_date }
    end
  end
end
