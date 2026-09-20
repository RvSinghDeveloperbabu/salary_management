# Total payroll at each of the last N month ends.
#
# This is the question only an effective-dated table can answer, and the
# reason docs/decisions.md 1 refused a mutable salary column: a spreadsheet
# with today's figure in it cannot say what March cost.
#
# One query returns every salary row for the population; the fold walks each
# employee's history once against the month boundaries. Querying per month
# would be 24 round trips, and querying per employee per month would be
# 240,000.
class PayrollTimeline
  DEFAULT_MONTHS = 24
  MAX_MONTHS = 120

  Point = Data.define(:month, :as_of, :total_cents, :headcount)

  def initialize(months: DEFAULT_MONTHS, filters: {})
    @months = clamp_months(months)
    @filters = (filters || {}).to_h.with_indifferent_access
  end

  def call
    boundaries = month_boundaries
    totals = Array.new(boundaries.size, 0)
    counts = Array.new(boundaries.size, 0)

    histories.each_value do |rows|
      boundaries.each_with_index do |boundary, index|
        row = effective_at(rows, boundary)
        next if row.nil?

        cents = convert(row[2], row[3])
        next if cents.nil?

        totals[index] += cents
        counts[index] += 1
      end
    end

    boundaries.each_with_index.map do |boundary, index|
      Point.new(
        month: boundary.strftime("%Y-%m"),
        as_of: boundary,
        total_cents: totals[index],
        headcount: counts[index]
      )
    end
  end

  private

  attr_reader :months, :filters

  # Month ends, oldest first. The most recent boundary is clamped to today:
  # projecting to the end of the current month would show a figure for days
  # that have not happened, which reads as a forecast rather than a fact.
  def month_boundaries
    today = Date.current

    (0...months)
      .map { |ago| (today << ago).end_of_month }
      .map { |boundary| [ boundary, today ].min }
      .reverse
  end

  # { employee_id => [[from, to, cents, currency], ...] }, each sorted
  # oldest first.
  def histories
    @histories ||= begin
      rows = scope.pluck(
        "salaries.employee_id",
        "salaries.effective_from",
        "salaries.effective_to",
        "salaries.amount_cents",
        "salaries.currency"
      )

      rows.group_by(&:first).transform_values do |employee_rows|
        employee_rows.map { |row| row.drop(1) }.sort_by!(&:first)
      end
    end
  end

  # The row covering a boundary, or nil where the person was not employed
  # then. Searched newest first because later boundaries are usually served
  # by later rows.
  def effective_at(rows, boundary)
    rows.reverse_each.find do |from, to, _cents, _currency|
      from <= boundary && (to.nil? || to >= boundary)
    end
  end

  # Every salary row, current and historical, for the filtered population.
  # Status is deliberately not filtered: a leaver counted towards payroll
  # for the months they were actually paid, and excluding them would make
  # last year's total shrink every time someone resigns.
  def scope
    relation = Salary.joins(:employee)
    relation = relation.where(employees: { department_id: filters[:department_id] }) if filters[:department_id].present?
    relation = relation.where(employees: { job_level_id: filters[:job_level_id] }) if filters[:job_level_id].present?
    relation = relation.where(employees: { country_code: filters[:country_code].to_s.upcase }) if filters[:country_code].present?
    relation
  end

  def rates
    @rates ||= Rates.table
  end

  def convert(cents, currency)
    rate_ppm = rates[currency]

    rate_ppm && Rates.convert(cents, rate_ppm)
  end

  def clamp_months(value)
    requested = value.to_i

    return DEFAULT_MONTHS if requested <= 0

    requested.clamp(1, MAX_MONTHS)
  end
end
