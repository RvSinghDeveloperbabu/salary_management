FactoryBot.define do
  factory :job_level do
    # Starts at 100 so an implicitly-created level never collides with the
    # explicit L1..L6 that specs about ordering and pay bands rely on.
    # rank is uniquely indexed, so a collision is a hard failure in an
    # unrelated spec rather than a visible problem here.
    sequence(:rank, 100) { |n| n }
    name { "L#{rank}" }
  end
end
