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

### What the publisher documents, and what it does not

Two official sources, both thin.

The [4TU dataset page](https://data.4tu.nl/articles/_/12696884/1) gives the process description and one structural fact: *"the system now allows for multiple offers per application. These offers can be tracked through their IDs in the log."*

The [BPI Challenge 2017 page](https://ais.win.tue.nl/bpi/2017/challenge.html) adds the three event types (Application, Offer, Workflow), the attribute list at application and offer level, and the count of 149 originators. Its headline figures agree exactly with the ones loaded here: 1,202,267 events, 31,509 applications, 42,995 offers.

**One attribute it explains that would otherwise look redundant.** Lifecycle information is provided *"both in the form of the standard XES lifecycle as well as the internally used lifecycle events."* So `Action` (`Created` / `statechange` / `Obtained` / `Released` / `Deleted`) is the institution's own internal vocabulary, not a duplicate of `lifecycle:transition`. It was dropped from `events` as redundant for this analysis, which remains the right call — but the reason is now documented rather than assumed.

**What neither source defines**, and what therefore had to be established empirically from the log itself:

- the meaning of `A_Pending`, `A_Cancelled` and `A_Denied` as outcomes
- the meaning of `complete` on a work item
- the meaning of the `Accepted` and `Selected` flags on an offer
- that `User_1` is an automation account
- the existence of the 30-day offer expiry

Every one of those is recorded in the Definitions section with the evidence behind it.

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

## Definitions

### Case outcome

**A case's outcome is whichever of `A_Pending`, `A_Cancelled` or `A_Denied` appears in it — or `NULL` if none does.**

Exactly one or exactly zero of the three appears in every case: 17,228 + 10,431 + 3,752 = 31,411 with one, 98 with none, and no case has two. It is therefore a genuine single-valued attribute of a case, not a choice between competing signals.

| Outcome | Cases | Share | Meaning |
|---|---|---|---|
| `A_Pending` | 17,228 | 54.7% | An offer was accepted |
| `A_Cancelled` | 10,431 | 33.1% | Application lapsed or was withdrawn |
| `A_Denied` | 3,752 | 11.9% | The bank refused |
| `NULL` | 98 | 0.3% | Still running when the log was cut |

Two alternative definitions were considered and rejected:

- **"The last `A_` activity."** Agrees for all 31,411 resolved cases, but labels the 98 censored ones `A_Complete`, `A_Incomplete` or `A_Validating` — which read like outcomes and are really just where the case had got to. Censoring should be visible, not disguised.
- **Derived from offer states.** An accepted offer implies `A_Pending` and a refused offer implies `A_Denied`, both without exception. But 32 denied cases have only a cancelled offer, making them indistinguishable from the 10,431 cancelled ones; the 98 censored cases have no offer outcome at all; and offers run at 1.36 per case, so "the offer state" is not single-valued and would need aggregating. Offer states are used for offer-level questions instead.

### `A_Pending` is the success state

The name suggests "undecided". It is not. **`A_Pending` occurs when and only when an offer is accepted** — every `A_Pending` case has an `O_Accepted` event and every case with one is `A_Pending`, 17,228 in both directions with no exceptions. It is also never performed by the automation account, and never co-occurs with `A_Cancelled` or `A_Denied`.

**Caveat for `REPORT.md`:** an accepted offer is not a disbursed loan. This log ends at acceptance; whether the money was paid, or the agreement later fell through, is outside the dataset. The defensible claim is *"the application completed successfully with an accepted offer"*, never *"the customer received a loan"*.

### `A_Cancelled` versus `A_Denied`

The two differ in who ends the case and how far it got.

| | Distinct resources | Performed by `User_1` | Fraud check | Reached "documents incomplete" |
|---|---|---|---|---|
| `A_Pending` | 40 | 0% | 0.6% | 73.4% |
| `A_Cancelled` | 108 | **76.2%** | 0.3% | **9.2%** |
| `A_Denied` | 99 | 0% | **4.5%** | 36.1% |

`User_1` is the automation account — it fires several events within seconds at case creation.

**`A_Denied` is never automated.** A named person performs it every time, denied cases receive a fraud assessment fifteen times more often than others, and most got far enough for someone to assess them. It reads as an active refusal by the bank.

**`A_Cancelled` is automated three times in four**, and 91% of cancelled cases never reach the document stage at all. It reads as a lapse or early drop-out rather than a deliberate cancellation.

**Limit:** the log records which account performed an event, not who decided. "The applicant cancelled" is consistent with the data but not demonstrated by it. Any statement about intent belongs in the caveats.

### `A_Cancelled` is two mechanisms, not one

The 10,431 cancellations split into two populations with opposite behaviour. Any statistic that does not separate them is misleading, including the headline that "cancelled cases take 2.1x longer than successful ones".

| | Automated (`User_1`) | Human |
|---|---|---|
| Cases | 7,953 (76.2%) | 2,478 (23.8%) |
| Median days idle before cancellation | 26.8 | **0.20** |
| Share cancelled the same day as the last event | — | 60.5% (1,498) |
| Share idle more than 30 days | 7.6% (604) | **0.0% (0)** |
| Median days from case start | 31.9 | 10.9 |

**Humans cancel immediately.** Three in five human cancellations happen on the same day as the last activity in the case, and none ever follows more than 28 days of inactivity.

**The automation enforces a 30-day offer expiry.** Measured from the offer being sent:

| | n | mean | **std dev** | min | p90 | max |
|---|---|---|---|---|---|---|
| Automated | 7,932 | 30.718 | **0.155** | 30.014 | 30.905 | 32.563 |
| Human | 2,389 | 14.596 | 16.412 | ~0 | 36.169 | 167.115 |

A standard deviation of 0.155 days — **3 hours 40 minutes** — across 7,932 cases is not a behaviour, it is a rule. The minimum is 30.014 days and no automated cancellation occurs before it. The median at 30.72 rather than 30.00 indicates a scheduled sweep that catches expired offers within a day of the threshold; the few reaching 32.5 days are consistent with weekends.

(7,932 rather than 7,953 because 21 automated cases had no offer sent; likewise 2,389 of 2,478 human ones. The 110 difference matches the count of cancelled cases with no `O_Sent` event.)

**Why the inactivity gap peaks at 26 days rather than 30.** The clock runs from the offer, not from the last event. After an offer is sent a few events typically follow over the next days — `O_Created`, a call attempt — and then nothing. So the last activity sits roughly four days into the thirty, leaving a 26-day silence before the sweep fires: 4,312 of 7,953 automated cancellations fall in day 26, and 81.6% in days 25 to 27. The three anchors reconcile: 30.7 from offer, minus ~4 days of residual activity, gives 26.8 from last event.

**Consequence for the analysis.** 7,953 applications — 25.2% of the entire year's volume — were idle for a month and then closed by a scheduled job with no human involvement. They are the largest single block of dead time in the process. Reporting cancelled cases as one group hides this entirely.

### Offer size barely affects how long a customer takes to accept

**Hypothesis tested and rejected.** If larger loans took materially longer to consider, then shortening the offer expiry would destroy disproportionately large loans, and the cost of that change would be understated by a headcount alone. Three tests, all pointing the same way.

**1 — Acceptance delay by offer size**, across successful cases:

| quintile | offered amount | n | median days to accept |
|---|---|---|---|
| 1 | EUR 5,000-8,000 | 3,446 | 11.68 |
| 2 | EUR 8,000-14,000 | 3,446 | 11.79 |
| 3 | EUR 14,000-18,000 | 3,446 | 11.97 |
| 4 | EUR 18,000-27,000 | 3,445 | 12.15 |
| 5 | EUR 27,000-75,000 | 3,445 | 13.81 |

Monotone across all five, so the effect is real rather than noise. But the largest quintile takes only 2.1 days longer than the smallest, on a base of about 12.

**2 — Correlation.** Pearson r between `offered_amount` and days-to-accept is **0.086** (0.082 against log amount). That is r-squared below 0.008: offer size explains under 1% of the variation.

**3 — The decisive comparison.** If size mattered, the share of *principal* lost under a shortened expiry would run well above the share of *conversions* lost. It does not:

| expiry threshold | % conversions lost | % principal lost | difference |
|---|---|---|---|
| 7 days | 83.7 | 84.9 | +1.2 |
| 14 days | 39.9 | 42.7 | +2.8 |
| 21 days | 18.6 | 19.9 | +1.3 |
| 25 days | 12.1 | 13.6 | +1.5 |
| 30 days | 6.9 | 7.9 | +1.0 |

Offers lost at a 14-day cut-off are roughly 7% larger than the average accepted offer. Consistent, and immaterial.

**Conclusion.** The cost of a shorter expiry is not driven by large loans. It is driven by the fact that the *typical* customer takes about twelve days to accept, whatever the amount — so any deadline near two weeks cuts close to the middle of the distribution rather than at its tail. Reporting conversions lost is therefore sufficient; principal lost tracks it almost exactly and adds precision rather than a different conclusion.

### What the log can and cannot establish about chasing

The bank's only mechanism for chasing an unanswered offer is the phone call. There is no reminder, email or SMS activity in the log, and `W_` work items carry no `offer_id`, so a call can be attached to a case but never to a particular offer.

**Established by the data:**

- A call is recorded as an *attempt*, not an outcome. No field records whether anyone answered.
- The chase is two attempts, a median of **3.99 days** apart. 71.7% of cases get exactly two; 91.4% get one or two.
- Attempts three and beyond are same-session redials, not further chasing: the median gap from attempt 2 to 3 is **0.01 days**, about fifteen minutes.
- Chasing is abandoned a median of 4.74 days after the second attempt, so it stops around **day 9**. The offer stays live until day 30.
- 7,932 cases end in an automated cancellation after that silence.

**Not established by the data, and not knowable from it:**

Whether chasing later would convert anyone. The observational relationship runs the wrong way:

| call attempts | cases | acceptance rate |
|---|---|---|
| 1 | 6,220 | 59.5% |
| 2 | 22,494 | 53.9% |
| 3 | 1,969 | 54.1% |
| 4+ | 679 | 51.0% |

More calls, lower acceptance — but the causation is reversed. A customer who was always going to accept does so quickly and needs one call; a customer drifting away gets called again. The second call is *caused by* the reluctance it appears to be associated with. No treatment of this log removes that confounding.

**Consequence for the recommendation.** The size of the gap is a fact and can be stated. The effect of filling it is not, and must not be claimed. The defensible recommendation is to *test* an intervention in that window, not to assert its return.

### `W_Call after offers` with lifecycle `complete`: tested, inconclusive

342 of 60,615 attempts (0.56%) are recorded as `complete` rather than ending in `suspend`. Whether this means the customer answered was tested and could not be resolved:

- **For:** in all 169 of the 341 such cases that went on to accept, acceptance followed the completed call, a median of 6.25 days later.
- **Against that test:** calls occur shortly after the offer and acceptance comes later, so acceptance follows calls in nearly every case regardless. The test does not discriminate.
- **Against the reading:** a 0.56% answer rate is implausible for a call centre, and cases with a completed call accept at 49.6% versus 54.7% without — the wrong direction if answering helped.
- **Ambiguous:** `start -> complete` lasts a median 26 s (shorter than a no-answer at 141 s), but `resume -> complete` lasts 89 s (longer than 29 s).

At 1.1% of cases the field cannot support a finding either way. Treated as an administrative state of unknown meaning.

### Two different "accepted"s

`A_Accepted` and `O_Accepted` are unrelated events at opposite ends of the process, and confusing them would corrupt every duration computed from them.

- **`A_Accepted`** — 31,509 events, one per case, near the start. The bank accepting the *application* into processing.
- **`O_Accepted`** — 17,228 events, at the end. The customer accepting an *offer*.

### An aborted work item is not a case ending

A `W_` event with lifecycle `ate_abort` is a *task* being abandoned. The case continues afterwards and reaches its own terminal state separately. Any measure of "the last event of a case" must not treat a work-item abort as the end.

---

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
