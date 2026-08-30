# Data provenance and cleaning decisions

Written as the work happens, never reconstructed afterwards. Every number in `REPORT.md` should be traceable to a decision on this page.

---

## Source

| | |
|---|---|
| Dataset | BPI Challenge 2017 |
| Citation | van Dongen, Boudewijn (2017): *BPI Challenge 2017*. Version 1. 4TU.ResearchData. dataset. |
| DOI | [`10.4121/uuid:5f3067df-f10b-45da-b98b-86ae4c7a310b`](https://doi.org/10.4121/uuid:5f3067df-f10b-45da-b98b-86ae4c7a310b) |
| Landing page | https://data.4tu.nl/articles/_/12696884/1 |
| Licence | 4TU General Terms of Use |
| Retrieved | 2026-08-28 |
| File | `BPI Challenge 2017.xes.gz` |
| Format | XES (gzipped XML) |
| Size (compressed) | 29,658,747 bytes |
| Size (uncompressed) | 578,941,403 bytes (579 MB) |
| SHA-256 | `183c5e5189282779c811c78c33ff936351b3dd201165d612211fc220936f8249` |

The log covers a Dutch financial institution's loan-application process for applications filed between 2016-01-01 and 2017-02-01 (397 days).

### Which log, and why

BPI Challenge 2017 was used rather than the smaller 2012 log. The 2012 fallback was reserved in case 2017 would not fit in memory on the development machine (7.6 GiB available to WSL2). It did: the parsed frame occupies **0.38 GB**, because pm4py returns Arrow-backed string columns rather than Python objects. Decision taken at roughly hour 3 and not revisited.

## Retrieval

```bash
curl -L -o "data/raw/BPI_Challenge_2017.xes.gz" \
  "https://data.4tu.nl/file/34c3f44b-3101-4ea9-8281-e38905c68b8d/f3aec4f7-d52c-4217-82f4-57d719a8298c"

sha256sum data/raw/BPI_Challenge_2017.xes.gz
```

`data/raw/` is gitignored, so the file is not in this repository. The checksum above is how a reader confirms they have the same bytes.

**Note for anyone inspecting the raw file:** the XES contains no line breaks — it is one 579 MB line. `head -n` is useless on it; cap by bytes instead, and insert breaks at a known delimiter:

```bash
zcat data/raw/BPI_Challenge_2017.xes.gz | head -c 4000 | sed 's|</event>|</event>\n|g'
```

## Load procedure

Converted once, in three stages. After stage 2 the XES is never read again.

| Stage | What | Output | Time |
|---|---|---|---|
| 1 | `pm4py.read_xes` -> pandas | in memory | 72 s |
| 2a | `to_parquet` | `data/processed/raw_events.parquet` (25.4 MB) | 1 s |
| 2b | Parquet -> DuckDB table `raw_events` | `data/processed/loans.duckdb` (29.6 MB) | 3 s |
| 3 | `raw_events` -> `cases`, `offers`, `events` | same database | in SQL |

Stages 1-2 are mechanical format conversion and make no modelling decisions. Every decision is made in stage 3, in SQL.

**Documented row counts** — later loads are checked against these:

```
raw_events   1,202,267 rows
cases           31,509
events per case      38.2 (mean)
```

579 MB of XML becomes 25.4 MB of Parquet: 23x smaller, and columnar, so a query touching two columns reads only those two.

## Completeness — the data is unusually clean

`SUMMARIZE raw_events` reports **0.00% nulls in eleven of the nineteen columns**: `Action`, `org:resource`, `concept:name`, `EventOrigin`, `EventID`, `lifecycle:transition`, `time:timestamp`, and all four `case:` attributes.

Every event has an actor, an activity, a lifecycle phase, a timestamp, and a complete set of case attributes. There are no partial records, no orphan events, and no missing timestamps. For a real operational system export this is unusually good, and it is worth stating explicitly: **no row-level cleaning was required, because there was nothing to clean.**

The remaining eight columns are *not* missing data. They are an artefact of flattening a nested structure into a rectangle:

| Columns | Null % | Populated on |
|---|---|---|
| `FirstWithdrawalAmount`, `NumberOfTerms`, `Accepted`, `MonthlyCost`, `Selected`, `CreditScore`, `OfferedAmount` | 96.42% | the 42,995 `O_Create Offer` rows |
| `OfferID` | 87.45% | the 150,854 `O_` events that are *not* creations |

All seven offer attributes share an identical null percentage, which means they are populated on exactly the same rows. 42,995 / 1,202,267 = 3.58%, matching the `O_Create Offer` count exactly. Splitting offers into their own table removes these nulls entirely rather than storing them.

## Data model

Three tables, built in SQL in stage 3. The grain of each is a decision:

### `cases` — one row per application (31,509)

Case attributes were verified constant within every case (maximum 1 distinct value per case for all three), so lifting them out of the event stream is safe.

Columns: `case_id`, `requested_amount`, `loan_goal`, `application_type`.

### `offers` — one row per offer (42,995)

Every one of the 31,509 cases has at least one offer; 8,559 cases (27.2%) have more than one, to a maximum of 10.

Key: the `EventID` of the `O_Create Offer` row. The set of those 42,995 IDs is *identical* to the set of `OfferID` values found on other offer events — 42,995 in both, none unique to either — so the join between `events` and `offers` is lossless.

### `events` — one row per event (1,202,267)

The raw grain, unfiltered — see decision 5. Case attributes and offer attributes are removed, since they live in `cases` and `offers`; what remains is the event-level columns plus the two foreign keys.

Columns: `event_id`, `case_id`, `offer_id`, `activity`, `timestamp`, `lifecycle`, `event_origin`, `resource`.

Note that `activity` alone does not identify an event type: `W_Call after offers` + `start` and `W_Call after offers` + `suspend` are different things. The event type is the pair `(activity, lifecycle)`.

## Decisions

| # | Decision | Reasoning | Risk accepted |
|---|---|---|---|
| 1 | Use BPI 2017, not 2012 | Fits in memory at 0.38 GB; richer log with offer-level detail | None material |
| 2 | Convert once to DuckDB; all analysis in SQL, pandas for plotting only | Reproducibility, and the analysis stays close to how it would be done against a client warehouse | Slower to write than pandas at first |
| 3 | Three tables (`cases`, `offers`, `events`), offers kept **separate** from events | Each fact stored once at its own grain. Prevents counting a EUR 20,000 loan 38 times, and removes the 96% null columns | An extra join for offer attributes |
| 4 | Session timezone fixed to **`Europe/Amsterdam`** | See below | See below |
| 5 | `events` keeps **every** row of the raw log (1,202,267). Lifecycle filtering happens inside each query, not at load time | Raw fact-table pattern: nothing is discarded before anyone knows whether it matters, and abandoned work is where delay hides | Every query must state its own filter; system-generated cascades produce millisecond transitions that each gap calculation has to exclude explicitly |
| 6 | `CreditScore = 0` handling | **OPEN** | |
| 7 | `RequestedAmount = 0` handling | **OPEN** | |

### Decision 5 — which events count

`events` keeps **all 1,202,267 rows**. No filtering is applied when the table is built.

Only `W_` (work item) events have a lifecycle at all; `A_` and `O_` events are instantaneous state changes, always recorded as `complete`. So this decision was only ever about which phases of a work item's life to retain:

| Phase | Events | Meaning |
|---|---|---|
| `schedule` | 149,104 | queued, untouched |
| `start` | 128,227 | picked up |
| `suspend` | 215,402 | put down |
| `resume` | 127,160 | picked up again |
| `complete` | 41,862 | finished |
| `ate_abort` | 85,224 | abandoned |
| `withdraw` | 21,844 | cancelled |

Of 149,104 work items scheduled, 128,227 are started and only **41,862 (28%) complete**. 57% are aborted and 15% withdrawn.

**Rationale.** Two narrower options were considered and rejected: keeping only `start`/`complete` (603,533 rows) and keeping `start` plus all endings (710,601 rows). Both discard queue time and pause time, and the strict variant also hides every abandoned work item — 86,365 of them, 67% of everything that starts. Since the engagement question is *where the process stalls*, discarding the failure paths before analysis would remove the most likely location of the answer.

Keeping everything follows the standard warehouse pattern: the fact table records what happened, and each query declares what it wants. It also makes the choice reversible — a narrower `events` table is one `CREATE OR REPLACE TABLE` away, and `raw_events` is never modified.

**Risk accepted.** The filtering decision is not eliminated, only moved into every query, where it must be made correctly each time rather than once. In particular, some events are system-generated cascades firing within milliseconds of one another — `Application_652823628` emits five events inside 27 ms — so any transition or gap calculation must exclude them explicitly or it will report thousands of meaningless near-zero waits.

### Decision 4 — timezone

`time:timestamp` is stored as `TIMESTAMP WITH TIME ZONE`: an absolute instant, displayed in whatever the session timezone happens to be. The development machine is set to `Asia/Shanghai`, so DuckDB was rendering the first event as `2016-01-01 17:51:15.304+08` while the same instant is `09:51:15.304+00:00` in UTC.

**All timestamps in this project are interpreted in `Europe/Amsterdam`**, the timezone the business actually operated in. A Dutch bank's "Monday morning" is a fact about Amsterdam, not about the analyst's laptop.

Every SQL file and every database connection sets this explicitly:

```sql
SET TimeZone = 'Europe/Amsterdam';
```

Durations are unaffected by this setting — subtraction operates on absolute instants either way. It matters for anything referencing clock time: hour of day, day of week, overnight and weekend effects, and the March and October DST boundaries, both of which fall inside the log window.

Leaving it to the session default would mean results that differ depending on which machine ran the query. That is not acceptable in a reproducible analysis.

## Known data quality issues

Feeds the caveats section of `REPORT.md`.

1. **`CreditScore = 0` is a missing-value sentinel, not a score.** 27,735 of 42,995 offers (64.5%) are zero, against a real population around 850-1,000 (75th percentile 848, max 1,145). The reported mean of 318.6 is meaningless. 4,806 cases show two distinct credit scores across their offers, most likely `{0, real}` pairs rather than genuine rescoring — to be confirmed.
2. **`RequestedAmount` has a minimum of 0.0.** Some applications request nothing. Count and cause not yet investigated.
3. **`EventID` is unique per event, not per work item.** A single work item emits `schedule`, `start`, `suspend` and `ate_abort` rows with four different IDs, so start and end cannot be joined by key — only paired by ordering within case and activity.
4. **The offer key moves columns.** `O_Create Offer` rows carry the offer's identity in `EventID` and have `OfferID` null; all later offer events carry it in `OfferID`.
5. **`Accepted` and `Selected` do not mean what their names suggest.** `Accepted = True` appears on 30,136 offers, but only 17,228 `O_Accepted` events exist in the entire log. All four combinations of the two flags occur in quantity. Their true semantics are unresolved.
6. **Both flags are retrospective.** They are stamped on the `O_Create Offer` row, at creation time, when the outcome could not have been known. Harmless for diagnostic work; they would leak the target in any predictive model.
7. **The log is right-censored at 2017-02-01.** 98 cases (0.3%) reach no terminal state; 174 offers and 174 work items are left open. These are cases still in flight when the extract was taken, and they bias any duration measure downward if included naively.
8. **Waiting time cannot be separated from handling time.** The log records when activities happened, not how long anyone worked. A five-day gap may be five days of queuing or one day of work started four days late. No transformation of this data can distinguish them.
