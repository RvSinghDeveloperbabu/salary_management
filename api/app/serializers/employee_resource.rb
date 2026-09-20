# A directory row. Everything here is already loaded by
# Employee.with_directory_associations, so serialising a 50-row page issues
# no further queries.
class EmployeeResource
  include Alba::Resource

  attributes :id, :employee_code, :first_name, :last_name, :email,
             :country_code, :employment_type, :status, :hired_on, :terminated_on

  attribute :full_name, &:full_name

  one :department, resource: DepartmentResource
  one :job_level, resource: JobLevelResource

  # Inlined rather than a nested resource so a nil current salary is one
  # null in the payload instead of a missing key the client must guard.
  attribute :current_salary do |employee|
    salary = employee.current_salary

    if salary
      rate_ppm = (params[:rates] || {})[salary.currency]

      {
        id: salary.id,
        amount_cents: salary.amount_cents,
        currency: salary.currency,
        amount_base_cents: rate_ppm && Rates.convert(salary.amount_cents, rate_ppm),
        effective_from: salary.effective_from,
        change_reason: salary.change_reason
      }
    end
  end
end
