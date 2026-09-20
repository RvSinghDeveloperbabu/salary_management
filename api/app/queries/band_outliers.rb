# The people worth looking at: paid below their band, paid above it, or not
# given a raise in a long time.
#
# Answers questions 3 and 5 in docs/requirements.md. This is the view that
# turns the pay_bands table from reference data into something actionable —
# without it, the application can only say what people are paid, never
# whether that is right.
class BandOutliers
  STALE_MONTHS = 18

  Finding = Data.define(
    :employee_id, :employee_code, :full_name, :department, :job_level, :country_code,
    :amount_cents, :currency, :amount_base_cents, :effective_from, :months_since_change,
    :band_min_cents, :band_mid_cents, :band_max_cents, :compa_ratio, :shortfall_cents
  )

  def initialize(filters = {})
    @filters = (filters || {}).to_h.with_indifferent_access
  end

  def below_band
    classified[:below]
  end

  def above_band
    classified[:above]
  end

  # Not a band question, but the same population and the same query, and it
  # belongs on the same screen: an HR manager reviewing pay wants everyone
  # who needs attention in one place.
  def stale
    classified[:stale]
  end

  def to_h
    { below_band: below_band, above_band: above_band, stale: stale }
  end

  private

  attr_reader :filters

  # Comparison happens in local currency, because a band is defined in the
  # employee's own currency. Converting first would compare a Polish salary
  # to a Polish band through two FX conversions for no gain.
  def classified
    @classified ||= begin
      below = []
      above = []
      stale = []
      # Compared as an ISO-8601 string against the stored value. See #rows.
      cutoff = (Date.current << STALE_MONTHS).to_s

      amount_at = IDX[:amount_cents]
      min_at = IDX[:band_min_cents]
      max_at = IDX[:band_max_cents]
      from_at = IDX[:effective_from]

      rows.each do |row|
        # Test against the raw row before building anything. Most people
        # are paid correctly, so constructing a Finding for all 9,000-odd
        # of them to discard 98% is most of the work this query does.
        amount = row[amount_at]
        min = row[min_at]

        is_below = min && amount < min
        is_above = min && amount > row[max_at]
        is_stale = row[from_at].to_s <= cutoff

        next unless is_below || is_above || is_stale

        finding = build_finding(row)

        below << finding if is_below
        above << finding if is_above
        stale << finding if is_stale
      end

      {
        # Worst first: the person furthest outside their band is the one to
        # deal with today.
        below: below.sort_by { |f| f.compa_ratio || 0 },
        above: above.sort_by { |f| -(f.compa_ratio || 0) },
        stale: stale.sort_by(&:effective_from)
      }
    end
  end

  COLUMNS = {
    employee_id: "employees.id",
    employee_code: "employees.employee_code",
    first_name: "employees.first_name",
    last_name: "employees.last_name",
    country_code: "employees.country_code",
    department: "departments.name",
    job_level: "job_levels.name",
    rank: "job_levels.rank",
    amount_cents: "salaries.amount_cents",
    currency: "salaries.currency",
    effective_from: "salaries.effective_from",
    band_min_cents: "pay_bands.min_cents",
    band_mid_cents: "pay_bands.mid_cents",
    band_max_cents: "pay_bands.max_cents"
  }.freeze

  # Positions within a plucked row, so the hot loop can index directly.
  # Building a Hash per row allocated 9,000 of them to inspect three fields.
  IDX = COLUMNS.keys.each_with_index.to_h.freeze

  # select_rows rather than pluck, for the same reason as PayrollTimeline:
  # pluck type-casts every value, and this scans every active employee to
  # find the few percent worth reporting. effective_from comes back as an
  # ISO-8601 string, where lexicographic order is chronological order.
  def rows
    Employee.connection.select_rows(scope.select(*COLUMNS.values).to_sql)
  end

  # LEFT JOIN on pay_bands, not INNER: an employee in a country with no
  # band defined still needs to appear in the stale report. Dropping them
  # would hide a person behind a gap in reference data.
  def scope
    relation = Employee
      .active
      .joins(:current_salary, :department, :job_level)
      .joins(band_join)

    relation = relation.in_department(filters[:department_id]) if filters[:department_id].present?
    relation = relation.at_level(filters[:job_level_id]) if filters[:job_level_id].present?
    relation = relation.in_country(filters[:country_code]) if filters[:country_code].present?
    relation
  end

  # A band is per level *per country*, so the join needs both. There is no
  # association that expresses a two-column match, and no request parameter
  # reaches this string.
  def band_join
    <<~SQL.squish
      LEFT JOIN pay_bands
        ON pay_bands.job_level_id = employees.job_level_id
       AND pay_bands.country_code = employees.country_code
    SQL
  end

  def build_finding(row)
    values = IDX.transform_values { |index| row[index] }

    amount = values[:amount_cents]
    mid = values[:band_mid_cents]
    min = values[:band_min_cents]
    max = values[:band_max_cents]
    rate_ppm = rates[values[:currency]]
    effective_from = values[:effective_from].to_date

    Finding.new(
      employee_id: values[:employee_id],
      employee_code: values[:employee_code],
      full_name: "#{values[:first_name]} #{values[:last_name]}",
      department: values[:department],
      job_level: values[:job_level],
      country_code: values[:country_code],
      amount_cents: amount,
      currency: values[:currency],
      amount_base_cents: rate_ppm && Rates.convert(amount, rate_ppm),
      effective_from: effective_from,
      months_since_change: months_between(effective_from, Date.current),
      band_min_cents: min,
      band_mid_cents: mid,
      band_max_cents: max,
      compa_ratio: mid && mid.positive? ? (amount.to_f / mid).round(4) : nil,
      # How far out of band, in money. "12% under" is a ratio; "8,400 short"
      # is a budget line, and the second is what gets a raise approved.
      shortfall_cents: shortfall(amount, min, max)
    )
  end

  def shortfall(amount, min, max)
    return nil if min.nil?
    return min - amount if amount < min
    return amount - max if amount > max

    0
  end

  def months_between(from, to)
    ((to.year * 12) + to.month) - ((from.year * 12) + from.month)
  end

  def rates
    @rates ||= Rates.table
  end
end
