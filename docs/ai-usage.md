# AI usage

The brief asks for intentional use of AI tools. This file records what was
delegated, what was accepted, and — more usefully — what was rejected and why.

Append an entry whenever AI output materially shaped a decision or a file. Keep
it honest; entries showing where the model was wrong are the ones that
demonstrate judgement.

**Tools used:** Claude (planning and architecture), Claude Code (implementation).

---

## Entry format

```
### <what was being worked on>
**Asked:** <the substance of the prompt>
**Accepted:** <what was kept>
**Rejected:** <what was discarded, and why>
```

---

### Requirements and scope

**Asked:** For a plan to complete the assessment, given Rails and React as the
required stack, and for questions about anything ambiguous.

**Accepted:** The framing that "answer questions about how the org pays people"
is the actual product requirement rather than a throwaway line, which made the
analytics layer the centre of the design instead of an add-on. Also the
observation that "multiple countries" implies multi-currency normalisation,
which is what drove the exchange-rate table into the schema.

**Rejected:** An initial suggestion of PostgreSQL. It was the right call on
capability grounds — `percentile_cont` in particular — but wrong for a one-day
budget, where provisioning a managed database is pure overhead. Chose SQLite
and solved percentiles in application code instead. See `docs/decisions.md` 2
and 3.

**Rejected:** A proposed bulk spreadsheet import feature. Defensible on product
grounds, since the organisation is migrating from Excel, but it does not
demonstrate any engineering decision the rest of the build does not already
cover. Moved to out-of-scope with that reasoning stated.

---

### Schema design

**Asked:** How to model salary such that historical questions are answerable.

**Accepted:** Append-only, effective-dated salary rows with a denormalised
`current_salary_id` for read performance.

**Rejected:** Future-dated salary changes. They break the denormalised current
pointer, and the fixes — a daily job, or a view parameterised on today's date —
either add infrastructure or make tests non-deterministic. Listed as an explicit
non-goal rather than left as a latent bug.

---

### Currency conversion formula

**Asked:** To implement `Rates` per the architecture document.

**Rejected:** The formula the architecture document itself specified —
`(amount_cents * rate_ppm).fdiv(1_000_000).round`. Checking it before
writing it showed `fdiv` returns a Float and the product exceeds the 53-bit
mantissa at realistic salary values: 400029407 cents at 83123457 ppm gives
33251827212 against 33251827211 by integer arithmetic. A cent per
conversion, in the one place the integer-money rule was supposed to protect.

**Accepted:** Integer arithmetic throughout, rounding half away from zero,
with a spec pinning the exact divergent case so the reason is executable
rather than folklore. The document has been corrected.

---

### Database indexes

**Rejected:** The `(employee_id, effective_from DESC)` index the architecture
document listed for `salaries`. SQLite scans an ordered index backwards at
the same cost, so it would be a redundant second copy on the largest table.
The ascending unique index serves both directions.

---

### Analytics cache invalidation

**Rejected:** Keying the analytics cache on `Salary.maximum(:updated_at)`
alone, as documented. Terminating an employee, or moving them between
departments, changes headcount and payroll totals without touching a salary
row — the dashboard would have kept serving the previous figure until an
unrelated raise happened to be recorded. Both tables are now watermarked, by
max `updated_at` and max `id` together.

---

### Frontend libraries

**Asked:** For the stack in the plan — Mantine, TanStack Query, TanStack
Table, Recharts, MSW.

**Rejected:** TanStack Table. Sorting and pagination are both server-side
because the dataset is 10,000 rows, so the library rendered nothing and did
no work. The plain version is an array of column definitions and a `.map()`,
and it is shorter.

**Accepted:** The rest. `web/README.md` documents each one against the
plain-React equivalent, so the code can be read without opening five sets of
library documentation.

---

### Verifying the UI

**Accepted:** The suggestion to screenshot the running application rather
than trust typechecking and unit tests. It found three defects none of those
would have caught: a blank employee page (the hook claimed an API response
wrapper *was* the object inside it — `apiGet<T>` is an assertion, not a
check), Rails refusing requests that carried a container hostname, and a tab
badge clipping "1,734" to "1..". Each now has a regression test or a
corrected configuration.

---

### Performance

**Accepted:** Measuring before optimising. The perf spec found the payroll
trend at 795ms and outliers at 425ms, neither visible by reading the code:
the trend re-scanned each employee's history per month boundary, and the
outlier query built a Hash for all 9,237 active employees to read three
fields from each. 188ms and 233ms after.
