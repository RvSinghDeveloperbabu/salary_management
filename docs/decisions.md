# Decisions

Short-form ADRs. Each records what was decided, what it cost, and what would
change the answer.

---

## 1. Salary history is append-only and effective-dated

**Context.** The obvious model is a `salary` column on `employees`, updated when
someone gets a raise.

**Decision.** Salaries live in their own table with `effective_from` /
`effective_to`. A raise is an INSERT. Nothing is ever overwritten.

**Why.** Compensation data has legal and audit weight. "What were we paying this
person in March?" is a question an HR manager will be asked, and a mutable
column cannot answer it. It is also the only way to build a payroll trend at
all — every historical number in this application is derived from this table.

**Cost.** Every read of "current salary" needs resolution. Mitigated by
denormalising `current_salary_id` onto `employees`.

**Would change if.** Never. This is the correct shape for this domain.

---

## 2. SQLite, not PostgreSQL

**Context.** The brief permits any relational database and names SQLite
explicitly. Rails 8 ships SQLite as a production-capable default.

**Decision.** SQLite, with WAL mode and the Rails 8 defaults.

**Why.** It removes an entire class of deployment work — no managed database,
no connection string, no separate service to provision — on a one-day budget.
The dataset is 10,000 employees and 40,000 salary rows, comfortably within what
SQLite handles without noticing.

**Cost.** No `percentile_cont`, no `ILIKE`, no native JSON operators, and a
single writer. The percentile cost is handled in decision 3. The single writer
is irrelevant for a single-HR-manager tool.

**Would change if.** Concurrent writers, or a dataset past a few hundred
thousand salary rows. Both would point at Postgres, and the migration is a
`database.yml` change plus reworking the percentile computation back into SQL.

---

## 3. Percentiles are computed in Ruby, not SQL

**Context.** SQLite has no ordered-set aggregates. The options were emulating
`percentile_cont` with window functions, or pulling the values out.

**Decision.** One query plucks `[group, amount]` pairs; `Stats::Distribution`
folds them in memory using linear interpolation between order statistics.

**Why.** The window-function emulation is ten lines of subtle SQL that is hard
to read and harder to test. The Ruby version is a pure function over an array —
testable against values computed by hand, with no database, in microseconds.
Given that "meaningful tests that are fast and easy to understand" is an
explicit grading criterion, testability won.

**Cost.** ~10k integers cross the boundary per distribution request. Measured
at roughly 15ms end to end, cached thereafter.

**Would change if.** The population passed a few hundred thousand. The answer
then is a nightly rollup table, not smarter SQL.

---

## 4. Money and FX rates are integers

**Context.** Multi-currency salaries need arithmetic that does not drift.

**Decision.** `amount_cents` as `bigint`; FX rates as `rate_ppm`, an integer
equal to the rate times one million.

**Why.** Floating-point money is a defect waiting for a large enough dataset.
SQLite makes this worse than usual: a `DECIMAL` column with a fractional value
is stored as REAL, so declaring the column decimal does not protect you the way
it would in Postgres. Integers sidestep the whole question.

**Cost.** Explicit conversion at every boundary, and rounding has to be decided
deliberately rather than by accident.

---

## 5. Normalisation uses a single FX snapshot date

**Context.** Converting each month's payroll at that month's rate is the
"correct" accounting answer.

**Decision.** All comparison and all trend data convert at one fixed snapshot
date.

**Why.** A trend converted at moving rates mixes two signals. An HR manager
reading "payroll rose 6%" needs that to mean the organisation decided to pay
more, not that the dollar moved against the rupee. Holding FX constant isolates
the compensation decision, which is the thing the persona can act on.

**Cost.** The numbers are not what finance would book. That is acceptable —
this is a compensation-management tool, not a ledger, and the distinction is
stated in the UI.

**Would change if.** Finance became a user. The `rate_on` column already
supports as-of-date conversion without a migration.

---

## 6. One deployment, Rails serves the React bundle

**Context.** The conventional split is Rails on one host, the SPA on a static
host.

**Decision.** Vite builds into `api/public/`. Rails serves it with a catch-all
route. One process, one URL.

**Why.** On a one-day budget the split costs a second hosting account, CORS
configuration, cookie `SameSite` handling across origins, and a second set of
environment variables. None of that demonstrates anything the reviewer is
grading. It also means the demo video has one URL in it.

**Cost.** The frontend cannot be deployed independently of the backend, and
there is no CDN in front of the assets. Both are irrelevant at this scale.

---

## 7. Future-dated salary changes are not supported

**Context.** `effective_from` is a date, so nothing structurally prevents
scheduling a raise for next quarter.

**Decision.** `effective_from` must be today or earlier. Validated.

**Why.** `current_salary_id` is denormalised and maintained on write. A
future-dated row would make that field silently wrong the day it became
effective, and fixing it properly requires either a daily job or a
date-parameterised view — the latter making tests non-deterministic, which
conflicts with an explicit grading criterion.

**Cost.** A real feature is missing. It is listed in the requirements document
as a stated non-goal rather than left as a lurking bug.
