FactoryBot.define do
  factory :audit_event do
    # strategy: :create because subject is polymorphic and needs a persisted
    # id. FactoryBot would otherwise mirror the parent's build strategy and
    # leave subject_id nil.
    association :subject, factory: :employee, strategy: :create
    action { "salary_recorded" }
    metadata { { "amount_cents" => 10_000_000 } }
  end
end
