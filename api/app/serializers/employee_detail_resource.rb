# The employee detail view: everything in a directory row, plus the full
# salary history and the band the person is measured against.
#
# The band comparison is the point. "What do we pay them" is answerable from
# a spreadsheet; "is that the right amount for their level in their country"
# is what this application exists to answer.
class EmployeeDetailResource
  include Alba::Resource

  attributes :id, :employee_code, :first_name, :last_name, :email,
             :country_code, :employment_type, :status, :hired_on, :terminated_on

  attribute :full_name, &:full_name

  one :department, resource: DepartmentResource
  one :job_level, resource: JobLevelResource
  one :pay_band, resource: PayBandResource

  # Identity only. The manager's own compensation is reachable through
  # their own record, so there is no reason to carry it here.
  attribute :manager do |employee|
    manager = employee.manager

    { id: manager.id, full_name: manager.full_name, employee_code: manager.employee_code } if manager
  end

  # Newest first, which comes from the association's own order rather than
  # a block here: Alba silently ignores an association block when
  # `resource:` is also given, so ordering written there would look correct
  # and do nothing.
  many :salaries, resource: SalaryResource

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

  # Where this person sits in their band. Null when either the salary or
  # the band is missing, rather than a fabricated 1.0.
  attribute :band_position do |employee|
    band = employee.pay_band
    salary = employee.current_salary

    if band && salary
      {
        position: band.position_of(salary.amount_cents),
        compa_ratio: band.compa_ratio(salary.amount_cents)
      }
    end
  end

  # Months since the last salary change. The stale-raise report uses 18 as
  # its threshold; exposing the number lets the detail view explain why
  # someone appears in it.
  attribute :months_since_last_change do |employee|
    salary = employee.current_salary

    if salary
      ((Date.current.year * 12 + Date.current.month) -
        (salary.effective_from.year * 12 + salary.effective_from.month))
    end
  end
end
