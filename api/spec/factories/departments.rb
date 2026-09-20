FactoryBot.define do
  factory :department do
    # Sequences rather than Faker here: these columns are uniquely indexed,
    # and Faker's company names collide often enough to make a suite flaky.
    sequence(:name) { |n| "Department #{n}" }
    sequence(:cost_centre) { |n| format("CC-%04d", n) }
  end
end
