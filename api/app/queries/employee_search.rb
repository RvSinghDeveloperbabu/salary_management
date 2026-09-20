# Filter, sort and paginate the employee directory.
#
# The allow-list below is the security boundary CLAUDE.md non-negotiable 4
# describes: Rails quotes *values*, not *identifiers*, so `order(params[:sort])`
# interpolates whatever arrives straight into SQL. Nothing here ever reaches
# ORDER BY except by being a key of SORTABLE.
class EmployeeSearch
  # Incoming key => the column it is permitted to mean. Frozen, because a
  # mutable allow-list is not one.
  SORTABLE = {
    "name" => "employees.last_name",
    "hired_on" => "employees.hired_on",
    "salary" => "salaries.amount_cents",
    "department" => "departments.name",
    "level" => "job_levels.rank"
  }.freeze

  # Sorting on an associated column needs that association joined. preload
  # cannot serve ORDER BY, because it loads associations in separate
  # queries rather than joining them.
  SORT_JOINS = {
    "salary" => :current_salary,
    "department" => :department,
    "level" => :job_level
  }.freeze

  DIRECTIONS = %w[asc desc].freeze

  DEFAULT_SORT = "name"
  DEFAULT_DIRECTION = "asc"
  DEFAULT_PER_PAGE = 50
  MAX_PER_PAGE = 100

  Result = Data.define(:records, :page, :per_page, :total_count, :total_pages)

  def initialize(params = {})
    @params = (params || {}).to_h.with_indifferent_access
  end

  def call
    scope = filtered
    total = scope.count(:all)
    pages = Pagy::Offset.new(count: total, page: page, limit: per_page)

    Result.new(
      records: ordered(scope).offset(pages.offset).limit(pages.limit),
      page: pages.page,
      per_page: pages.limit,
      total_count: total,
      total_pages: pages.last
    )
  end

  private

  attr_reader :params

  def filtered
    scope = Employee.with_directory_associations
    scope = scope.where(status: status) if status
    scope = scope.in_department(params[:department_id]) if params[:department_id].present?
    scope = scope.at_level(params[:job_level_id]) if params[:job_level_id].present?
    scope = scope.in_country(params[:country_code]) if params[:country_code].present?
    scope = scope.where(employment_type: employment_type) if employment_type
    scope = apply_search(scope)
    scope
  end

  # Matches the things an HR manager would actually type: a name, an email,
  # or an employee code read off another system.
  def apply_search(scope)
    term = params[:q].to_s.strip
    return scope if term.blank?

    # sanitize_sql_like escapes % and _ so a user searching for "100%"
    # does not get a wildcard.
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term.downcase)}%"

    scope.where(
      "LOWER(employees.first_name) LIKE :pattern OR " \
      "LOWER(employees.last_name) LIKE :pattern OR " \
      "LOWER(employees.email) LIKE :pattern OR " \
      "LOWER(employees.employee_code) LIKE :pattern",
      pattern: pattern
    )
  end

  def ordered(scope)
    join = SORT_JOINS[sort]
    scope = scope.left_joins(join) if join

    # employees.id is always the final term. Without a unique tiebreaker,
    # rows with equal sort values can come back in a different order on
    # each query, so page 2 may repeat or skip a row that page 1 already
    # showed. Offset pagination is only correct over a total order.
    scope.order(Arel.sql("#{SORTABLE.fetch(sort)} #{direction}"), id: :asc)
  end

  def sort
    @sort ||= permitted(params[:sort].presence || DEFAULT_SORT, SORTABLE.keys, :sort)
  end

  def direction
    @direction ||= permitted(
      params[:direction].to_s.downcase.presence || DEFAULT_DIRECTION, DIRECTIONS, :direction
    )
  end

  def status
    return if params[:status].blank?

    permitted(params[:status], Employee::STATUSES, :status)
  end

  def employment_type
    return if params[:employment_type].blank?

    permitted(params[:employment_type], Employee::EMPLOYMENT_TYPES, :employment_type)
  end

  # The single gate. Anything not in the allow-list raises, and the
  # controller turns that into 400 rather than passing it to the database.
  def permitted(value, allowed, parameter)
    return value.to_s if allowed.include?(value.to_s)

    raise InvalidQueryParameter.new(parameter: parameter, value: value, allowed: allowed)
  end

  def page
    [ params[:page].to_i, 1 ].max
  end

  # Clamped so a client cannot ask for the whole table in one request and
  # instantiate 10,000 models (CLAUDE.md non-negotiable 5).
  def per_page
    requested = params[:per_page].to_i
    return DEFAULT_PER_PAGE if requested <= 0

    requested.clamp(1, MAX_PER_PAGE)
  end
end
