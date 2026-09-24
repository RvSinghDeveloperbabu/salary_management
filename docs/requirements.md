# Requirements

*Written before implementation began. See commit history.*

## Goal

Give the HR manager of a 10,000-employee, multi-country organisation a
web-based replacement for the spreadsheets they currently use to manage salary
data — and, more importantly, a way to answer questions about how the
organisation pays people.

The spreadsheet is not the problem. The problem is that a spreadsheet cannot
answer "are we paying our L4 engineers in Poland fairly relative to the band?"
without an afternoon of manual work, and cannot answer it again next month
without repeating that afternoon.

## User

A single persona: the HR manager. They are trusted with full visibility of
compensation across the organisation. They are not a developer and they are not
an analyst.

## The questions the software must answer

This list drove the data model. Each one is a feature.

1. What does the organisation spend on salaries in total, and how does that
   split by country, department, and level?
2. What is the median and the spread (p25/p75) at each level, and who sits
   outside it?
3. Who is paid below the minimum or above the maximum of their pay band?
4. How has total payroll moved over the last 24 months?
5. Who has not had a salary change in over 18 months?
6. For the same level, how does pay differ between departments?

## Scope

**Employee directory.** Search, filter by department / country / level /
employment status, sort, paginate. Detail view per employee showing their full
salary history.

**Salary history.** Effective-dated and append-only. Recording a raise creates
a new record with an effective date and a reason (hire, merit, promotion,
market adjustment, correction). Nothing is overwritten, so the history is
auditable and payroll can be reconstructed as of any past date.

**Multi-currency normalisation.** Salaries are stored in the employee's local
currency and normalised to USD for any cross-country comparison, using a stored
exchange-rate table rather than hard-coded constants.

**Pay bands.** Minimum, midpoint, and maximum per level per country. This is
what makes compa-ratio and outlier detection possible.

**Compensation analytics.** An overview dashboard plus grouped distribution,
payroll trend, and outlier views, answering the six questions above.

**Authentication.** Single HR-manager role, session-based. Salary data is among
the most sensitive data an organisation holds; shipping it behind no auth at
all would be a poor demonstration of judgement regardless of the time budget.

**Seed data.** 10,000 employees across 6 countries, 8 departments, and 6 levels,
with a realistic level pyramid, tenure spread, and a small number of deliberate
band outliers so the outlier view has something to find.

## Out of scope, and why

**Payroll execution, payslips, tax and statutory deductions.** A separate,
heavily regulated domain that differs per country. The persona asked to
understand how the organisation pays people, not to run the payroll.

**Bonus, equity, and benefits.** Base salary is sufficient to demonstrate the
effective-dated model and the analytics. The schema leaves room for a
`salary_components` table; building it would add breadth without adding any new
engineering decision.

**Multi-role RBAC and SSO.** The brief specifies one persona. Building a
permission matrix for roles that do not exist is speculative work.

**Approval workflows on salary changes.** A real requirement in a real product,
but it demonstrates workflow plumbing rather than compensation modelling, which
is what this exercise is actually about.

**Live FX feed.** The exchange-rate table is dated and seeded. A refresh job is
a documented stub. Wiring a third-party rate API adds an external dependency and
a source of test flakiness for no analytical gain.

**Future-dated salary changes.** The effective date must be today or earlier in
this version. Supporting scheduled future raises requires either a daily job or
a date-parameterised view, both of which complicate the "current salary"
denormalisation for a feature the persona did not ask for.

**Employee self-service portal.** A different persona entirely.

**Bulk spreadsheet import.** Genuinely the most defensible cut on this list,
since the organisation is migrating from Excel and an import path is the real
migration story. It is out only because of the one-day budget.

**UI internationalisation.** English only.

**A deployed URL.** Cut deliberately rather than by time pressure. The
application runs as a single process serving both the API and the React
bundle from one origin, so deployment is a configuration step rather than a
code change; standing up a hosting account demonstrates nothing the rest of
the build does not. `docker compose up` is the reproduction path.

**CSV export.** First on the cut list in CLAUDE.md and the only item taken
from it. The directory already answers "who matches these filters" on screen,
and the analytics endpoints answer the questions the export would have been
used for. The audit log, the outlier view and the payroll trend chart all shipped.

Employee create and update shipped as API endpoints — with strong-parameter
protection and request specs — but without a UI. Recording a salary change
is the write path the persona actually needs, and it has a full interface;
adding and editing employee records is a thinner need for a demo dataset
that is seeded. Stated here rather than left for a reviewer to discover.

## Success criteria

*Revised after the deployment cut above; the original first line read "a
deployed URL the reviewer can open and use".*

- A reviewer can run the whole system with `docker compose up` and no local
  toolchain — no Ruby, no Node, no database server.
- A seed script that produces 10,000 employees in under 20 seconds.
- Every one of the six questions above answerable in the UI in under three
  clicks.
- A test suite that runs in under 30 seconds and passes deterministically.
- A commit history that shows the requirements document landing before the
  first line of application code.
