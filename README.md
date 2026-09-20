# Salary Management

Salary management and compensation analytics for an HR manager at a
10,000-employee, multi-country organisation.

Built as a timed engineering assessment. The brief's central requirement is
being able to *answer questions about how the organisation pays people* — a
searchable employee table is the baseline; the analytics layer is the point.

> **Placeholder.** This file is written last. It will cover setup, how to run
> the application and its tests, the demo login, and a tour of the
> architecture.

## What it does

| Question | Where it is answered |
| --- | --- |
| What do we spend on salaries, split by country, department and level? | `GET /api/v1/analytics/overview` |
| What is the median and spread (p25–p75) at each level? | `GET /api/v1/analytics/distribution` |
| Who is paid below the minimum or above the maximum of their band? | `GET /api/v1/analytics/outliers` |
| How has total payroll moved over the last 24 months? | `GET /api/v1/analytics/payroll_trend` |
| Who has not had a salary change in over 18 months? | `GET /api/v1/analytics/outliers` |
| For the same level, how does pay differ between departments? | `GET /api/v1/analytics/distribution?group_by=department&job_level_id=…` |

## Engineering notes

A few decisions that shaped the rest of the build:

- **Salary history is append-only and effective-dated.** A raise is an
  INSERT, never an UPDATE. It is the only way to answer "what were we paying
  this person in March", and every historical figure derives from it.
- **Money is integers throughout** — `amount_cents` as bigint, FX rates as
  `rate_ppm` (rate × 1,000,000). No float ever represents money, including
  over the wire.
- **Cross-country comparison converts at a single fixed FX date,** so a
  payroll trend shows compensation decisions rather than currency movement.
- **Sort and filter parameters are allow-listed.** Rails quotes values, not
  identifiers, so `order(params[:sort])` would be a SQL injection.
- **Analytics never instantiate models.** Queries pluck and fold, which is
  the difference between milliseconds and seconds at 10,000 employees.

Design notes and decision records are kept outside version control.

## Running it

Everything runs in Docker; nothing is installed on the host.

```sh
docker compose up              # http://localhost:3000
docker compose run --rm api bin/rails db:prepare db:seed
docker compose run --rm -e RAILS_ENV=test api bundle exec rspec
```
