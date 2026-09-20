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
    # Compared as ISO-8601 strings against the stored values. See histories.
    keys = boundaries.map(&:to_s)
    totals = Array.new(boundaries.size, 0)
    counts = Array.new(boundaries.size, 0)

    # Both the boundaries and each employee's rows are in ascending date
    # order, so the two can be walked together with a cursor that only ever
    # moves forward. Re-scanning an employee's history for every boundary
    # is O(employees x months x rows); this is O(employees x (months + rows)).
    histories.each_value do |rows|
      cursor = 0
      active = nil

      keys.each_with_index do |boundary, index|
        while cursor < rows.length && rows[cursor][FROM] <= boundary
          active = rows[cursor]
          cursor += 1
        end

        next if active.nil?

        # The person may have left: the last row they held is closed before
        # this boundary.
        closed_on = active[TO]
        next if closed_on && closed_on < boundary

        totals[index] += active[BASE_CENTS]
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

  # Positions within a history row. Plain indices rather than a Hash or a
  # Struct per row: at 30,000 rows the allocation is most of the work.
  FROM = 0
  TO = 1
  BASE_CENTS = 2

  # { employee_id => [[from, to, base_cents], ...] }, each sorted oldest
  # first.
  #
  # Currency conversion happens once per row here, not once per row per
  # boundary. A row active across all 24 months would otherwise be
  # converted 24 times to the same value.
  def histories
    @histories ||= begin
      grouped = Hash.new { |hash, key| hash[key] = [] }

      # select_rows rather than pluck: pluck type-casts every value, which
      # at 30,000 rows means 60,000 Date objects built only to be compared
      # once. Dates are compared as ISO-8601 strings instead, where
      # lexicographic order is chronological order.
      #
      # to_s keeps this adapter-independent: SQLite hands back strings
      # already, and on an adapter that returns Date objects it normalises
      # them to the same form rather than mixing types in a comparison.
      raw_rows.each do |employee_id, from, to, cents, currency|
        base = convert(cents, currency)
        next if base.nil?

        grouped[employee_id] << [ from.to_s, to&.to_s, base ]
      end

      grouped.each_value { |employee_rows| employee_rows.sort_by!(&:first) }
      grouped
    end
  end

  def raw_rows
    sql = scope.select(
      "salaries.employee_id",
      "salaries.effective_from",
      "salaries.effective_to",
      "salaries.amount_cents",
      "salaries.currency"
    ).to_sql

    Salary.connection.select_rows(sql)
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
