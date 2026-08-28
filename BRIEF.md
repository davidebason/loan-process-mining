# Brief - where a loan application stalls

Scope and framing for this engagement. Findings live in `REPORT.md`; data
provenance and cleaning decisions in `DATA.md`.

---

## The client and the question

A consumer-lending operation. Their stated problem, in their words:

> *"Loan applications take too long and we don't know where the time goes. Tell
> us where the process stalls, and what one change would shorten it most."*

The deliverable is a memo a head of operations could act on: a recommendation
with a number attached, and the caveats that qualify it. Explicitly **not** a
process map, and **not** a predictive model.

## Turning that into measurable questions

The question as stated is not answerable. It decomposes into four that are:

1. **How long does an application take end to end**, and how does that vary
   across cases?
2. **Between which two activities does the most waiting time accumulate?**
   Waiting time, not handling time - the gap between one activity finishing and
   the next starting is where elapsed time hides.
3. **How much of the elapsed time is rework** - the same activity repeated
   within a single case?
4. **Is the stall concentrated** in a subset of cases (by requested amount,
   channel, or outcome), or spread evenly across all of them?

Question 4 is the first to be dropped if the engagement runs short. If it is
dropped, that decision and its reasoning appear in the caveats of `REPORT.md`
rather than going unmentioned.

## Data

**BPI Challenge event log** - a real, anonymised log from a Dutch financial
institution's loan-application process, published via 4TU.ResearchData. Roughly
31,500 cases and 1.2 million events, with case-level attributes (requested
amount, loan goal, application type) and offer-level detail.

It is the canonical public dataset for this class of question, which gives the
memo a defensible reference frame. Exact release, DOI, licence, retrieval steps
and every cleaning decision are recorded in [`DATA.md`](DATA.md) as the work
happens.

**Analytical constraint:** the log is converted from XES to Parquet once, loaded
into a DuckDB database, and from that point **every analytical question is
answered in SQL**. pandas is used for the final plotting step only. This keeps
the analysis reproducible, inspectable, and close to how the same question would
be answered against a client's warehouse.

## Data model

Two tables. The grain of each is a decision, defended in `REPORT.md`:

- **`events`** - one row per event: `case_id`, `activity`, `timestamp`,
  `resource`, `lifecycle`, plus event-level attributes. The raw grain.
- **`cases`** - one row per case: start, end, duration, outcome, requested
  amount, application type, event count. Derived from `events` in SQL.

Anything further - transition tables, variant tables - is derived by query
rather than stored, unless it becomes a performance problem worth documenting.

## Deliverables

Each is a branch, a reviewed pull request, and a merge, in this order.

| # | Branch | Deliverable | Done when |
|---|---|---|---|
| 1 | `setup` | Repo scaffold, packaging, CI | Green check on `main` |
| 2 | `load` | XES to Parquet to DuckDB; `DATA.md` started | `SELECT COUNT(*) FROM events` returns the documented figure |
| 3 | `cases` | `cases` table in SQL; sanity tests | Tests pass; grain decision written down |
| 4 | `durations` | Questions 1 and 2 - end-to-end time, waiting time per transition | Results reproducible from SQL in the repo |
| 5 | `rework` | Question 3 - repeated activities within a case | As above |
| 6 | `segments` | Question 4, if scope allows | As above, or dropped with the reason recorded |
| 7 | `report` | `REPORT.md`, one figure, recruiter-first `README.md` | A non-technical reader can state the recommendation after one read |
| 8 | `polish` | Docstrings, logging, final test pass | `main` green |

Tests cover the analytical functions against a hand-built event log of five
cases whose answers are computable on paper. That fixture is what makes the SQL
debuggable, and it is built early rather than last.

## Out of scope

Named deliberately, so that the boundary is a decision rather than an omission:

- **No process-discovery algorithms as the centrepiece.** A single
  directly-follows graph may appear as an illustration; the analysis is SQL.
- **No predictive model.** The question is diagnostic, not predictive.
- **No orchestration, containerisation, or cloud deployment.** This is a
  one-shot analysis, not a pipeline in production.
- **No pandas for analysis.** Plotting only.

Anything that feels necessary but falls outside these lines is written up under
*"what I would do next"* in `REPORT.md` rather than quietly added.
