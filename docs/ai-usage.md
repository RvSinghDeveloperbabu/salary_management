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

<!-- Append implementation entries below as the build proceeds. -->
