# What the organisation pays right now, normalised to one currency.
#
# One query returns the whole filtered population as
# [group, amount_cents, currency] triples; conversion and statistics happen
# in memory. No endpoint built on this instantiates a single Employee
# (CLAUDE.md non-negotiable 5) — at 10,000 people that is the difference
# between 8ms and several seconds.
class CompensationSnapshot
  # Incoming group_by => the column it is permitted to mean. Same
  # allow-list discipline as EmployeeSearch::SORTABLE, for the same reason.
  GROUPINGS = {
    "department" => "departments.name",
    "country" => "employees.country_code",
    "job_level" => "job_levels.name"
  }.freeze

  GROUP_JOINS = {
    "department" => :department,
    "job_level" => :job_level
  }.freeze

  # Levels order by seniority, not alphabetically: L10 must not sit between
  # L1 and L2 on a chart.
  GROUP_ORDER = {
    "department" => "departments.name",
    "country" => "employees.country_code",
    "job_level" => "job_levels.rank"
  }.freeze

  def initialize(filters = {})
    @filters = (filters || {}).to_h.with_indifferent_access
  end

  # Every current salary in the filtered population, in USD cents.
  def amounts
    @amounts ||= to_base(scope.pluck(:amount_cents, :currency))
  end

  # { "Engineering" => [cents, cents, ...], ... }, ordered sensibly for
  # display. One query regardless of how many groups come back.
  def grouped_amounts(group_by)
    column = GROUPINGS.fetch(group_by) { raise_invalid(group_by) }
    relation = scope
    relation = relation.joins(GROUP_JOINS[group_by]) if GROUP_JOINS[group_by]

    rows = relation
      .order(Arel.sql(GROUP_ORDER.fetch(group_by)))
      .pluck(Arel.sql(column), :amount_cents, :currency)

    rows.each_with_object({}) do |(group, cents, currency), acc|
      converted = convert(cents, currency)
      (acc[group] ||= []) << converted if converted
    end
  end

  def headcount
    @headcount ||= scope.count
  end

  def total_base_cents
    amounts.sum
  end

  private

  attr_reader :filters

  # INNER JOIN through the denormalised pointer: someone with no salary on
  # file cannot contribute to a payroll figure, and counting them would
  # drag every average down.
  def scope
    relation = Employee.joins(:current_salary)
    relation = relation.where(status: status)
    relation = relation.in_department(filters[:department_id]) if filters[:department_id].present?
    relation = relation.at_level(filters[:job_level_id]) if filters[:job_level_id].present?
    relation = relation.in_country(filters[:country_code]) if filters[:country_code].present?
    relation
  end

  # Active by default. "What do we spend on salaries" means the people
  # currently being paid; including leavers would inflate every figure.
  def status
    return "active" if filters[:status].blank?
    return filters[:status] if Employee::STATUSES.include?(filters[:status].to_s)

    raise InvalidQueryParameter.new(
      parameter: :status, value: filters[:status], allowed: Employee::STATUSES
    )
  end

  def rates
    @rates ||= Rates.table
  end

  def to_base(rows)
    rows.filter_map { |cents, currency| convert(cents, currency) }
  end

  # Nil, not zero, when a currency has no seeded rate. A missing rate is a
  # data gap: dropping the row understates payroll, but counting it as zero
  # understates it too while looking deliberate.
  def convert(cents, currency)
    rate_ppm = rates[currency]

    rate_ppm && Rates.convert(cents, rate_ppm)
  end

  def raise_invalid(value)
    raise InvalidQueryParameter.new(
      parameter: :group_by, value: value, allowed: GROUPINGS.keys
    )
  end
end
