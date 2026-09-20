# Deterministic seed: 10,000 employees across 6 countries, 8 departments and
# 6 levels, with effective-dated salary history.
#
# Two constraints shape this file.
#
# Reproducibility. Every random choice comes from a seeded generator, so the
# dataset is byte-identical on every run. A demo where the numbers move
# between runs is not a demo of anything.
#
# Bulk inserts. 10,000 employees and ~35,000 salary rows through create! is
# 45,000 individual INSERTs and takes minutes. insert_all in batches of 1,000
# is what keeps this inside the 20-second budget in docs/requirements.md.
# The cost is that validations and callbacks do not run, so this file is
# responsible for producing rows the model would have accepted.

# Monotonic clock rather than Benchmark: benchmark leaves Ruby's default
# gems in 4.0 and warns on load, and this needs one number.
def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

# Separate generators so that changing how names are produced does not shift
# the structural choices, and vice versa.
Faker::Config.random = Random.new(42)
RNG = Random.new(1337)

BATCH_SIZE = 1_000
TODAY = Date.current
NOW = Time.current

# --------------------------------------------------------------------------
# Reference data
# --------------------------------------------------------------------------

DEPARTMENTS = [
  [ "Engineering",      "CC-1000", 30 ],
  [ "Product",          "CC-2000",  8 ],
  [ "Design",           "CC-2100",  6 ],
  [ "Sales",            "CC-3000", 18 ],
  [ "Marketing",        "CC-3100",  9 ],
  [ "Customer Success", "CC-4000", 15 ],
  [ "Finance",          "CC-5000",  7 ],
  [ "People",           "CC-6000",  7 ]
].freeze

# name, rank, share of headcount. A pyramid, not a uniform distribution:
# organisations have more juniors than principals.
LEVELS = [
  [ "L1", 1, 30 ],
  [ "L2", 2, 25 ],
  [ "L3", 3, 20 ],
  [ "L4", 4, 13 ],
  [ "L5", 5,  8 ],
  [ "L6", 6,  4 ]
].freeze

# code, currency, rate to USD in ppm, share of headcount, labour-cost
# multiplier against the US band.
COUNTRIES = [
  [ "US", "USD", 1_000_000, 35, 1.00 ],
  [ "IN", "INR",    12_000, 25, 0.30 ],
  [ "PL", "PLN",   250_000, 15, 0.45 ],
  [ "GB", "GBP", 1_270_000, 10, 0.85 ],
  [ "BE", "EUR", 1_080_000,  8, 0.80 ],
  [ "BR", "BRL",   185_000,  7, 0.35 ]
].freeze

# US annual bands in cents, by level rank: min / mid / max.
US_BANDS = {
  1 => [  6_000_000,  7_500_000,  9_000_000 ],
  2 => [  8_500_000, 10_500_000, 12_500_000 ],
  3 => [ 11_500_000, 14_000_000, 16_500_000 ],
  4 => [ 15_000_000, 18_500_000, 22_000_000 ],
  5 => [ 20_000_000, 25_000_000, 30_000_000 ],
  6 => [ 28_000_000, 35_000_000, 42_000_000 ]
}.freeze

EMPLOYMENT_TYPES = [ [ "full_time", 88 ], [ "part_time", 7 ], [ "contract", 5 ] ].freeze
RAISE_REASONS = %w[merit merit merit promotion market_adjustment].freeze

HR_MANAGER_EMAIL = "hr@example.com".freeze
HR_MANAGER_PASSWORD = "compensation2026".freeze

TERMINATED_SHARE = 0.08
OUTLIERS_BELOW = 22
OUTLIERS_ABOVE = 20

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

# Pick from [[value, weight], ...] using the seeded generator.
def weighted_pick(pairs, rng)
  total = pairs.sum { |(_, weight)| weight }
  roll = rng.rand(total)
  pairs.each do |value, weight|
    return value if roll < weight

    roll -= weight
  end
  pairs.last.first
end

# Convert a US band figure into local currency, integer arithmetic only.
#
#   local = usd_cents * multiplier / (rate_ppm / 1_000_000)
#
# Rounded to a whole local unit so seeded bands look like numbers a
# compensation team would actually publish.
def to_local_cents(usd_cents, multiplier, rate_ppm)
  adjusted = (usd_cents * (multiplier * 1000).round) / 1000
  local = adjusted * Rates::PPM / rate_ppm
  (local / 100.0).round * 100
end

def counts_for(shares, total)
  counts = shares.map { |share| (total * share / 100.0).floor }
  counts[0] += total - counts.sum
  counts
end

started_at = monotonic

ActiveRecord::Base.transaction do
  puts "Clearing existing data..."
  # Order matters: children before parents, and the denormalised pointer
  # has to be dropped before the salaries it references.
  Employee.update_all(current_salary_id: nil)
  AuditEvent.delete_all
  Salary.delete_all
  Employee.delete_all
  PayBand.delete_all
  ExchangeRate.delete_all
  JobLevel.delete_all
  Department.delete_all
  Session.delete_all
  User.delete_all

  # Rails declares primary keys as INTEGER PRIMARY KEY AUTOINCREMENT, and
  # SQLite keeps that counter in sqlite_sequence across a DELETE. Without
  # this reset the rows are identical run to run but their ids are not,
  # so anything quoting an id — a bookmarked URL, a screenshot in the
  # demo, a fixture — breaks on the next reseed.
  ActiveRecord::Base.connection.execute("DELETE FROM sqlite_sequence")

  # ----------------------------------------------------------------------
  # Reference data
  # ----------------------------------------------------------------------

  puts "Creating reference data..."

  # The demo login. Credentials are printed at the end rather than hidden,
  # because this is a seeded demo account in a throwaway database, not a
  # secret. Nothing here goes near config/credentials.
  hr_manager = User.create!(
    email_address: HR_MANAGER_EMAIL,
    password: HR_MANAGER_PASSWORD,
    password_confirmation: HR_MANAGER_PASSWORD
  )

  departments = DEPARTMENTS.map do |name, cost_centre, _share|
    Department.create!(name: name, cost_centre: cost_centre)
  end
  department_weights = DEPARTMENTS.each_with_index.map { |(_, _, share), i| [ departments[i], share ] }

  levels = LEVELS.map { |name, rank, _share| JobLevel.create!(name: name, rank: rank) }

  COUNTRIES.each do |_code, currency, rate_ppm, _share, _multiplier|
    ExchangeRate.create!(
      base_currency: currency,
      quote_currency: Rates::BASE_CURRENCY,
      rate_ppm: rate_ppm,
      rate_on: Rates::SNAPSHOT_DATE
    )
  end

  # bands[level_id][country_code] => PayBand
  bands = {}
  levels.each do |level|
    bands[level.id] = {}
    min, mid, max = US_BANDS.fetch(level.rank)

    COUNTRIES.each do |code, currency, rate_ppm, _share, multiplier|
      bands[level.id][code] = PayBand.create!(
        job_level: level,
        country_code: code,
        currency: currency,
        min_cents: to_local_cents(min, multiplier, rate_ppm),
        mid_cents: to_local_cents(mid, multiplier, rate_ppm),
        max_cents: to_local_cents(max, multiplier, rate_ppm)
      )
    end
  end

  # ----------------------------------------------------------------------
  # Employees
  # ----------------------------------------------------------------------

  puts "Building 10,000 employees..."

  total = 10_000
  level_counts = counts_for(LEVELS.map { |(_, _, share)| share }, total)

  # Each employee is planned in full before anything is written, so the
  # org chart can be built from the highest level downwards.
  plans = []
  LEVELS.each_with_index do |(_name, _rank, _share), index|
    level = levels[index]

    level_counts[index].times do
      country = weighted_pick(COUNTRIES.map { |c| [ c, c[3] ] }, RNG)
      code, currency, = country

      # Tenure: senior people have been here longer.
      max_years = [ 2 + (level.rank * 2), 12 ].min
      tenure_days = RNG.rand(30..(max_years * 365))
      hired_on = TODAY - tenure_days

      # Only people with enough tenure to have left. Someone hired three
      # weeks ago who already resigned is noise, not signal.
      terminated = tenure_days > 120 && RNG.rand < TERMINATED_SHARE
      terminated_on = terminated ? hired_on + RNG.rand(90..tenure_days) : nil

      plans << {
        level: level,
        department: weighted_pick(department_weights, RNG),
        country_code: code,
        currency: currency,
        employment_type: weighted_pick(EMPLOYMENT_TYPES, RNG),
        hired_on: hired_on,
        terminated_on: terminated_on,
        status: terminated ? "terminated" : "active"
      }
    end
  end

  # Deliberate band outliers, so the outlier view has real findings rather
  # than an empty state. Only active employees, so they show up in the
  # default filter.
  active_indices = plans.each_index.select { |i| plans[i][:status] == "active" }
  outlier_pool = active_indices.sample(OUTLIERS_BELOW + OUTLIERS_ABOVE, random: RNG)
  outlier_pool.first(OUTLIERS_BELOW).each { |i| plans[i][:outlier] = :below }
  outlier_pool.last(OUTLIERS_ABOVE).each { |i| plans[i][:outlier] = :above }

  # Insert highest level first so that when a level is written, the level
  # above it already has ids to be managed by.
  managers_by_department = Hash.new { |h, k| h[k] = [] }
  employee_number = 0

  plans.group_by { |plan| plan[:level].rank }.sort.reverse_each do |rank, group|
    rows = group.map do |plan|
      employee_number += 1
      first_name = Faker::Name.first_name
      last_name = Faker::Name.last_name

      pool = managers_by_department[plan[:department].id]
      plan[:manager_id] = pool.empty? ? nil : pool.sample(random: RNG)

      {
        employee_code: format("EMP-%05d", employee_number),
        first_name: first_name,
        last_name: last_name,
        email: "#{first_name}.#{last_name}.#{employee_number}".downcase.gsub(/[^a-z0-9.]/, "") + "@example.com",
        country_code: plan[:country_code],
        department_id: plan[:department].id,
        job_level_id: plan[:level].id,
        manager_id: plan[:manager_id],
        employment_type: plan[:employment_type],
        status: plan[:status],
        hired_on: plan[:hired_on],
        terminated_on: plan[:terminated_on],
        created_at: NOW,
        updated_at: NOW
      }
    end

    inserted = []
    rows.each_slice(BATCH_SIZE) do |slice|
      result = Employee.insert_all(slice, returning: [ :id ])
      inserted.concat(result.rows.flatten)
    end

    group.each_with_index { |plan, i| plan[:id] = inserted[i] }

    # Everyone at this level becomes a candidate manager for the level
    # below, within their own department.
    next if rank == 1

    group.each { |plan| managers_by_department[plan[:department].id] << plan[:id] }
  end

  # ----------------------------------------------------------------------
  # Salary history
  # ----------------------------------------------------------------------

  puts "Building salary history..."

  salary_rows = []

  plans.each do |plan|
    band = bands[plan[:level].id][plan[:country_code]]

    # Decide where this person sits today, then work backwards. Choosing
    # the endpoint first is what makes deliberate outliers possible
    # without rewriting history to reach them.
    target =
      case plan[:outlier]
      when :below then (band.min_cents * RNG.rand(0.72..0.88)).round
      when :above then (band.max_cents * RNG.rand(1.10..1.28)).round
      else
        spread = band.max_cents - band.min_cents
        # Centred near the midpoint, most people inside the band.
        band.min_cents + (spread * RNG.rand(0.15..0.92)).round
      end

    last_day = plan[:terminated_on] || TODAY
    tenure_days = (last_day - plan[:hired_on]).to_i

    rows_count =
      if tenure_days < 400 then 1
      elsif tenure_days < 1_100 then RNG.rand(2..3)
      else RNG.rand(3..5)
      end

    # Raise dates, spread across tenure with jitter, oldest first.
    dates = [ plan[:hired_on] ]
    (rows_count - 1).times do |i|
      fraction = (i + 1).to_f / rows_count
      offset = (tenure_days * fraction).round + RNG.rand(-45..45)
      candidate = plan[:hired_on] + offset.clamp(60, tenure_days)
      dates << candidate
    end
    dates = dates.uniq.sort

    # Work backwards from today's figure, undoing a raise each step.
    amounts = [ target ]
    (dates.length - 1).times do
      factor = 1.0 + RNG.rand(0.03..0.12)
      amounts.unshift((amounts.first / factor).round)
    end

    dates.each_with_index do |from, i|
      to =
        if i < dates.length - 1
          dates[i + 1] - 1
        else
          plan[:terminated_on]
        end

      salary_rows << {
        employee_id: plan[:id],
        amount_cents: [ amounts[i], 1 ].max,
        currency: plan[:currency],
        effective_from: from,
        effective_to: to,
        change_reason: i.zero? ? "hire" : RAISE_REASONS.sample(random: RNG),
        recorded_by_id: hr_manager.id,
        created_at: NOW,
        updated_at: NOW
      }
    end
  end

  salary_rows.each_slice(BATCH_SIZE) { |slice| Salary.insert_all(slice) }

  # ----------------------------------------------------------------------
  # Denormalised current salary pointer
  # ----------------------------------------------------------------------

  puts "Linking current salaries..."

  # One statement rather than 10,000. The subquery is correlated, but it
  # runs once over the whole table against an index on
  # (employee_id, effective_from).
  ActiveRecord::Base.connection.execute(<<~SQL.squish)
    UPDATE employees
    SET current_salary_id = (
      SELECT s.id
      FROM salaries s
      WHERE s.employee_id = employees.id
      ORDER BY s.effective_from DESC
      LIMIT 1
    )
  SQL
end

elapsed = monotonic - started_at

puts
puts "Seeded in #{elapsed.round(2)}s"
puts "  departments    #{Department.count}"
puts "  job levels     #{JobLevel.count}"
puts "  pay bands      #{PayBand.count}"
puts "  exchange rates #{ExchangeRate.count}"
puts "  employees      #{Employee.count} (#{Employee.active.count} active)"
puts "  salaries       #{Salary.count}"
puts
puts "Sign in with:"
puts "  #{HR_MANAGER_EMAIL}"
puts "  #{HR_MANAGER_PASSWORD}"
