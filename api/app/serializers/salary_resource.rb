class SalaryResource
  include Alba::Resource

  attributes :id, :amount_cents, :currency, :effective_from, :effective_to, :change_reason

  # True for the row in force today. The client uses it to mark the current
  # entry in the history timeline without re-deriving it from the dates.
  attribute :current do |salary|
    salary.effective_to.nil?
  end

  # The same amount in USD at the snapshot rate, so figures from different
  # countries can be compared without the client knowing about FX.
  # Null when no rate is seeded for the currency — a visible gap rather
  # than a silently wrong number.
  attribute :amount_base_cents do |salary|
    rate_ppm = (params[:rates] || {})[salary.currency]
    rate_ppm && Rates.convert(salary.amount_cents, rate_ppm)
  end
end
