# Build plan

Execute in order. Commit at every numbered step. Do not skip ahead — the commit
sequence is itself a graded artifact.

Times are a budget for a single working day, roughly 11 hours. If a phase
overruns, take the cut list from `CLAUDE.md` rather than dropping tests.

---

## Phase 0 — Documentation first (0:00–0:30)

Nothing in `api/` or `web/` exists yet. This is deliberate.

1. `git init`. Add `README.md` (placeholder), `CLAUDE.md`, and the four files in
   `docs/`.
   → `docs: define goal, scope, and non-goals`
2. Add `docs/decisions.md` and `docs/architecture.md` if not already in step 1.
   → `docs: record architecture and key decisions`

**Check:** `git log --reverse | head` shows a `docs:` commit before any code.

---

## Phase 1 — Rails skeleton and CI (0:30–1:30)

3. `rails new api --api --skip-test --database=sqlite3`. Add rspec-rails,
   factory_bot_rails, faker, shoulda-matchers, simplecov, pagy, alba,
   bundler-audit. `rails generate rspec:install`.
   → `chore(api): scaffold rails 8.1 api application`
4. Configure RuboCop (rails-omakase), SimpleCov with an 80% floor, and
   `.rspec` with `--require spec_helper`. Set specs to run serially.
   → `chore(api): configure rubocop, simplecov, rspec`
5. GitHub Actions workflow running `rspec`, `rubocop`, `brakeman`, and
   `bundler-audit` on push.
   → `chore(ci): run specs, lint, and security scans`

**Check:** CI green on an empty suite.

---

## Phase 2 — Domain model (1:30–3:00)

6. Migrations for `departments`, `job_levels`, `pay_bands`, `exchange_rates`.
   Models with validations. Model specs.
   → `feat(domain): add organisation reference data`
7. Migration for `employees` with all indexes from `docs/architecture.md`.
   Model, validations, associations, scopes (`active`, `in_department`,
   `in_country`). Model specs.
   → `feat(domain): add employee records`
8. Migration for `salaries` including the unique index on
   `(employee_id, effective_from)`. Model with an overlap validation and a
   guard rejecting `effective_from` in the future. Add
   `employees.current_salary_id`. Model specs covering overlap rejection,
   future-date rejection, and append-only behaviour.
   → `feat(domain): add effective-dated salary history`
9. `Money` value object and `Rates` module: integer conversion,
   `SNAPSHOT_DATE`, rounding. Unit specs with hand-computed expectations for
   USD, EUR, and INR.
   → `feat(domain): add integer money and fx conversion`
10. `Salaries::RecordChange` service: inside one transaction, close the prior
    row's `effective_to`, insert the new row, update `current_salary_id`, write
    an audit event. Service specs.
    → `feat(domain): add salary change service`

**Check:** `rspec` green, all model-level. No controllers exist yet.

---

## Phase 3 — Seed data (3:00–3:45)

11. `db/seeds.rb` producing: 8 departments, 6 job levels, 6 countries
    (US/USD, BE/EUR, IN/INR, GB/GBP, PL/PLN, BR/BRL), pay bands per
    level × country, FX rates at the snapshot date, one HR-manager user, and
    10,000 employees.

    Requirements:
    - `Faker::Config.random = Random.new(42)` at the top. The dataset must be
      identical on every run.
    - `insert_all` in batches of 1,000. Not `create!` in a loop.
    - Level pyramid, not a uniform distribution: roughly 30/25/20/13/8/4
      across L1–L6.
    - 2–5 salary rows per employee representing hire plus raises, with
      effective dates spread over tenure.
    - ~8% terminated.
    - ~40 deliberate band outliers, split between below-minimum and
      above-maximum, so the outlier view has real findings.
    - Print elapsed time at the end.

    → `feat(seeds): generate deterministic 10k employee organisation`

**Check:** `rails db:seed` completes in under 20 seconds. Record the measured
number in `docs/architecture.md` under Performance.

---

## Phase 4 — Authentication (3:45–4:30)

12. `bin/rails generate authentication`. Adapt for API-only: JSON session
    create/destroy, `/api/v1/me`. Seed one HR manager.
    → `feat(auth): add session-based hr manager login`
13. Request specs: valid login, invalid password, unauthenticated request to a
    protected endpoint returns 401.
    → `test(auth): cover login and unauthorised access`

---

## Phase 5 — Employees API (4:30–6:00)

14. `Queries::EmployeeSearch`: filters, the frozen `SORTABLE` allow-list,
    direction validation, Pagy pagination, `includes` for the associations.
    Query specs including a spec asserting an arbitrary sort key is rejected.
    → `feat(api): add employee search query with sort allow-list`
15. `Api::V1::EmployeesController#index` and `#show` with Alba serializers.
    Show includes full salary history. Request specs.
    → `feat(api): add employee directory endpoints`
16. `#create` and `#update` with strong parameters excluding `employee_code`
    and `current_salary_id`. Request specs covering the mass-assignment
    rejection.
    → `feat(api): add employee create and update`
17. `POST /employees/:id/salaries` calling `Salaries::RecordChange`. Request
    specs covering success, overlap → 422, future date → 422.
    → `feat(api): add salary change endpoint`
18. `GET /reference` returning departments, levels, countries, currencies in
    one payload.
    → `feat(api): add reference data endpoint`

**Check:** the directory endpoint against the 10k seed returns a 50-row page in
under 100ms, and the query log shows a handful of queries, not hundreds.

---

## Phase 6 — Analytics API (6:00–7:30)

19. `Stats::Percentile` and `Stats::Distribution` as pure functions. Unit specs
    against hand-computed values on small arrays, including the interpolation
    cases and the single-element and empty cases.
    → `feat(stats): add distribution and percentile calculations`
20. `Queries::CompensationSnapshot`: current salaries for the filtered
    population, normalised to USD, plucked as pairs.
    `GET /analytics/overview` and `GET /analytics/distribution`.
    → `feat(api): add compensation overview and distribution`
21. `Queries::PayrollTimeline`: one pluck, folded across month boundaries.
    `GET /analytics/payroll_trend`. Specs on a five-employee fixture with
    hand-computed monthly totals.
    → `feat(api): add payroll trend endpoint`
22. `Queries::BandOutliers`: below band minimum, above band maximum, and no
    salary change in 18 months. `GET /analytics/outliers`.
    → `feat(api): add pay band outlier detection`
23. Cache analytics responses keyed on `Salary.maximum(:updated_at)`. Add the
    `:perf` tagged spec asserting the overview endpoint stays under 300ms
    against 10k.
    → `perf(api): cache analytics on salary watermark`

---

## Phase 7 — React directory (7:30–9:00)

24. `npm create vite@latest web -- --template react-ts`. Mantine, TanStack
    Query, TanStack Table, React Router, Recharts, Vitest, RTL, MSW. Vite
    proxy for `/api` in dev, build output to `../api/public`.
    → `chore(web): scaffold vite react 19 application`
25. API client with typed responses, app shell with Mantine `AppShell`, login
    page, auth guard, session handling.
    → `feat(web): add app shell and authentication`
26. Employee directory: TanStack Table with server-side pagination, sorting,
    debounced search, and filter selects populated from `/reference`. Loading
    and empty states.
    → `feat(web): add employee directory`
27. Employee detail drawer: profile, current salary with compa-ratio against
    the band, salary history timeline, and a form to record a change.
    → `feat(web): add employee detail and salary change form`
28. Component specs for the directory filters and the salary form, with MSW
    mocking the API.
    → `test(web): cover directory filters and salary form`

---

## Phase 8 — Dashboard (9:00–10:00)

29. Overview cards: headcount, total annual payroll, average and median salary,
    outlier count.
    → `feat(web): add compensation overview`
30. Distribution chart with a group-by toggle (department / country / level),
    showing median with a p25–p75 band. Payroll trend line over 24 months.
    → `feat(web): add distribution and trend charts`
31. Outliers table with the three categories, each row linking to the employee.
    → `feat(web): add pay band outlier view`

---

## Phase 9 — Ship (10:00–11:00)

32. Build the frontend into `api/public/`, add the Rails catch-all route,
    verify the SPA serves and `/api/v1` still routes correctly.
    → `build: serve react bundle from rails`
33. Deploy. Fly.io with a 1GB volume mounted at `/rails/storage` so the SQLite
    file survives redeploys. Run seeds once on first boot.
    **Ask the user before creating any hosting account or running deploy.**
    → `chore(deploy): add fly.io configuration`
34. `README.md`: what it is, how to run it locally, how to run the tests, the
    deployed URL, the demo login, and a short tour of the architecture with
    links into `docs/`.
    → `docs: add readme with setup and deployment notes`
35. Record the demo video. Five minutes, following the six questions from
    `docs/requirements.md` in order. Link it in the README.
    → `docs: link demo video`
36. Final pass on `docs/ai-usage.md`, and move any features that were cut into
    the out-of-scope section of `docs/requirements.md` with a reason.
    → `docs: record ai usage and final scope`

---

## Acceptance checklist before sending the link

- [ ] `rspec` green, under 30 seconds, run three times with the same result
- [ ] `rubocop`, `brakeman`, `bundler-audit` clean
- [ ] `rails db:reset` from scratch produces a working 10k dataset
- [ ] Deployed URL loads, login works, all six questions answerable
- [ ] `config/master.key` and any `.env` are gitignored and absent from
      `git log -p`
- [ ] Commit history reads as a sequence of decisions, with `docs:` first
- [ ] README links the deployed URL, the demo video, and the docs
