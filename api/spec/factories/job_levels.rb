FactoryBot.define do
  factory :job_level do
    sequence(:rank) { |n| n }
    name { "L#{rank}" }
  end
end
