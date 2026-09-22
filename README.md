# Salary Management

Compensation management and analytics for an HR manager at a
10,000-employee, multi-country organisation.

The brief's central requirement is being able to **answer questions about how
the organisation pays people**. A searchable employee table is the baseline;
the analytics layer is the point, and it is where most of the effort went.

---

## Running it

Everything runs in Docker. Nothing is installed on your machine — no Ruby, no
Node, no database server.

```sh
docker compose up
docker compose exec api bin/rails db:prepare db:seed
```

Then open **http://localhost:5173** and sign in:

| | |
| --- | --- |
| Email | `hr@example.com` |
| Password | `compensation2026` |

The seed builds 10,000 employees with ~29,000 salary rows in about six
seconds. It is deterministic: three consecutive runs produce byte-identical
data, primary keys included.

### The two ports

| URL | What it is |
| --- | --- |
| `:5173` | Vite dev server, with hot reload. Proxies `/api` to Rails. |
| `:3000` | Rails. Serves the API, and the built bundle once you run a build. |

In development use `:5173`. To see the single-deployment setup — Rails
serving both the API and the React bundle from one origin — run
`docker compose run --rm web npm run build` and use `:3000`.

---

## Tests

```sh
docker compose run --rm -e RAILS_ENV=test api bundle exec rspec       # 491 examples
docker compose run --rm web npm test                                  # 30 tests
docker compose run --rm -e RAILS_ENV=test api bundle exec rubocop
docker compose run --rm -e RAILS_ENV=test api bundle exec brakeman --no-pager
```

The performance suite is excluded from the default run because it builds its
own 10,000-employee dataset:

```sh
docker compose run --rm -e RAILS_ENV=test api bundle exec rspec --tag perf
```

Backend coverage is 99% of `app/`. Tests are deterministic by construction:
the clock is frozen, Faker is seeded per example, and nothing touches the
network.

---

## The six questions it answers

| Question | Where |
| --- | --- |
| What do we spend on salaries, split by country, department and level? | Dashboard → overview tiles and country split |
| What is the median and spread (p25–p75) at each level? | Dashboard → pay distribution, grouped by Level |
| Who is paid below the minimum or above the maximum of their band? | Pay review → Below band / Above band |
| How has total payroll moved over the last 24 months? | Dashboard → payroll trend |
| Who has not had a salary change in over 18 months? | Pay review → third tab |
| For the same level, how does pay differ between departments? | Dashboard → distribution grouped by Department, filtered to a level |

---

## How it is built

```
Browser ─▶ Rails (Puma)
             ├── /            → React bundle from public/
             └── /api/v1/*    → controllers → queries/services → SQLite
```

- **Rails 8.1** in `--api` mode, Ruby 3.4, SQLite.
- **React 19** + TypeScript via Vite, Mantine, TanStack Query, Recharts.
- `web/README.md` explains every frontend library, the problem it solves, and
  the plain-React equivalent.

### Decisions worth knowing before reading the code

**Salary history is append-only and effective-dated.** A raise is an INSERT;
nothing is ever overwritten. It is the only way to answer "what were we
paying this person in March", and every historical figure — the payroll
trend, the stale-raise report — is derived from it. The single write path is
`Salaries::RecordChange`, which closes the outgoing period, inserts the new
row and repoints the denormalised `current_salary_id` in one transaction.

**Money is integers everywhere.** `amount_cents` as bigint, FX rates as
`rate_ppm` (rate × 1,000,000). No float represents money at any point,
including over the wire and including the form input — `parseFloat("19.99") *
100` is 1998.9999999999998, and that penny is exactly what this discipline
exists to protect.

**Cross-country comparison converts at one fixed FX date.** Converting a
trend at moving rates mixes two signals; an HR manager reading "payroll rose
6%" needs that to mean the organisation decided to pay more, not that the
dollar moved. Sorting the directory by salary normalises too — otherwise
₹2,400,000 outranks $100,000 because its integer is larger.

**Sort and filter parameters are allow-listed.** Rails quotes values, not
identifiers, so `order(params[:sort])` is a SQL injection. Anything not in a
frozen hash returns 400 without reaching the database.

**Analytics never instantiate models.** Queries pluck and fold in Ruby. A
spec asserts `Employee.instantiate` is never called, because at 10,000
employees that is the difference between milliseconds and seconds.

**Percentiles are computed in Ruby, not SQL.** SQLite has no
`percentile_cont`. The Ruby version is a pure function over an array, tested
against values worked out by hand, and matches `percentile_cont` semantics so
the numbers do not move if the database is swapped.

### Measured against the 10,000-employee dataset

```
overview (cold)    188 ms      overview (cached)     7 ms
distribution        52 ms      payroll trend (24m) 188 ms
outliers           233 ms      directory page       34 ms
seed               5.7 s       full backend suite   ~8 s
```

Analytics responses are cached against a data watermark — the most recent
write across salaries and employees — rather than a clock, so the cache is
invalidated by a change and by nothing else.

---

## Not built, and why

- **Deployment.** No hosting account was created. The application runs as a
  single container serving both API and bundle, so deploying it is a
  configuration step rather than a code change.
- **Future-dated salary changes.** `effective_from` must be today or earlier.
  Supporting scheduled raises needs either a daily job or a date-parameterised
  view, both of which complicate the current-salary denormalisation for a
  feature nobody asked for. It is refused explicitly rather than left as a
  latent bug.
- **Bonus, equity, benefits; payroll execution; multi-role permissions;
  approval workflows; a live FX feed.** Each adds breadth without adding an
  engineering decision the rest of the build does not already demonstrate.
