# CLAUDE.md

Operating instructions for this repository. Read this fully before writing code.

## What this is

Salary management software for an HR manager at a 10,000-employee, multi-country
organisation. Built as a timed engineering assessment. The brief is graded on
engineering judgement, not feature count.

The single most important line in the brief: *"be able to answer questions about
how the org pays people."* A CRUD table is the baseline. The analytics layer is
the differentiator. Weight your effort accordingly.

## Stack (pinned)

| Layer | Choice | Version |
|---|---|---|
| API | Rails, `--api` mode | 8.1.x |
| Language | Ruby | 3.4.x |
| Database | SQLite | bundled `sqlite3` gem |
| Auth | Rails 8 built-in `bin/rails generate authentication` | — |
| Serialization | Alba | latest |
| Pagination | Pagy | latest |
| Test | RSpec, FactoryBot, Faker, SimpleCov | latest |
| Lint | rubocop-rails-omakase, Brakeman, bundler-audit | latest |
| Frontend | React + TypeScript via Vite | React 19.x |
| UI kit | Mantine | latest |
| Data fetching | TanStack Query | latest |
| Table | TanStack Table (server-side pagination) | latest |
| Charts | Recharts | latest |
| FE test | Vitest, React Testing Library, MSW | latest |

Do **not** add Devise, GraphQL, Redis, Sidekiq, Docker Compose, or a second
database. Every one of those costs time the schedule does not have.

## Repo layout

```
salary-management/
├── CLAUDE.md
├── README.md              # setup, run, test, deploy — write this last
├── docs/
│   ├── requirements.md    # the one-page deliverable
│   ├── architecture.md
│   ├── decisions.md       # ADR-lite
│   ├── build-plan.md      # the phase list you execute
│   └── ai-usage.md        # append to this as you go
├── api/                   # Rails 8.1
└── web/                   # Vite + React 19
```

## Non-negotiables

These are the things a reviewer will actually check. Violating any of them
undermines the whole submission.

1. **Money is integers.** `amount_cents` as `bigint`, always paired with a
   `currency` column. No floats, no `BigDecimal` in the schema, no
   `t.decimal` for money. SQLite stores REAL for fractional NUMERIC values and
   you will lose pennies.

2. **FX rates are integers too.** Store `rate_ppm` (parts per million, i.e.
   rate × 1,000,000) as an integer. Conversion is
   `base_cents = amount_cents * rate_ppm / 1_000_000` with explicit rounding.

3. **`salaries` is append-only.** A raise is an INSERT, never an UPDATE. There
   is no code path that mutates `amount_cents` on an existing row. Corrections
   are new rows with `change_reason: :correction`.

4. **Sort and filter parameters are allow-listed.** Rails quotes *values*, not
   *identifiers*. `order(params[:sort])` is a SQL injection. Map incoming sort
   keys against a frozen hash and reject anything unknown with a 400.

5. **Aggregate in SQL, or pluck and fold in Ruby. Never instantiate 10k
   models.** `Employee.all.map(&:current_salary)` is the failure mode this
   assessment is looking for.

6. **Tests are deterministic.** Fixed Faker seed, `travel_to` a frozen date,
   no `rand`, no `sleep`, no network. A spec that passes on Tuesday and fails
   on Wednesday is worse than no spec.

7. **Never commit secrets.** Use Rails encrypted credentials. `config/master.key`
   is in `.gitignore`. If you generate any `.env`, gitignore it in the same
   commit.

## Commit discipline

The brief explicitly grades commit history. Follow this exactly.

- Conventional Commits: `feat(api): record effective-dated salary changes`
- One logical change per commit. No "wip", no "fixes", no 40-file commits.
- Tests land in the same commit as the code they cover.
- The `docs:` commit for `docs/requirements.md` must be the **first commit in
  the repository**, before `rails new`. The brief asks for a requirements
  document written before building, and commit order is the proof.
- Commit after each numbered step in `docs/build-plan.md`. Roughly 25–30
  commits total.

## Testing rules

- Unit and request specs run against ~30 hand-built factory records, never the
  10k seed. Percentile assertions must be checkable by hand.
- Run specs **serially**. SQLite write-locking makes parallel RSpec workers
  flaky; set `parallelize(workers: 1)` or leave parallelism off.
- Security paths get their own specs, not just happy paths:
  - unauthenticated request → 401
  - `?sort=` with an arbitrary column name → 400, not a query
  - mass-assignment of `employee_code` / `current_salary_id` → rejected
  - overlapping `effective_from` on the same employee → 422
- One performance spec, tagged `:perf` and excluded from the default run,
  seeds 10k and asserts the analytics overview endpoint returns in under 300ms.
- Target ~85% line coverage on `app/`. Do not chase 100%.

## Code structure

- Controllers are thin. They authenticate, permit params, call one object,
  render. No business logic, no queries.
- Queries live in `app/queries/` as POROs returning relations or plucked arrays.
- Writes live in `app/services/` as POROs with a single `call`.
- Statistics live in `app/lib/stats/` as pure functions over arrays. No
  ActiveRecord dependency, so they are fast to test.
- Serializers live in `app/serializers/` (Alba resources).

## What to do when you are running out of time

Cut in this order. Do not silently skip; record the cut in
`docs/requirements.md` under out-of-scope with a one-line reason.

1. CSV export
2. Audit log table
3. Employee create/update (keep read + salary change)
4. The outliers view
5. The payroll trend chart

Never cut: the seed script, the analytics overview, tests, the deployed URL.

## Permissions

Before running anything that mutates state outside the repo — deploying,
installing global tooling, `git push`, creating a hosting account — stop and
ask the user. Reading, building, testing, and committing locally are fine.
