# Data provenance and cleaning decisions

Written as the work happens, never reconstructed afterwards. Every number in
`REPORT.md` should be traceable to a decision on this page.

---

## Source

| | |
|---|---|
| Dataset | *to record on download* |
| Publisher | 4TU.ResearchData |
| DOI / URL | *to record on download* |
| Licence | *to record on download* |
| Retrieved | *to record on download* |
| Format | XES (gzipped XML) |
| Size on disk | *to record on download* |

### Which log, and why

*BPI Challenge 2017 is the intended source; BPI Challenge 2012 is the fallback if
2017 does not fit in memory on this machine. The decision and the evidence behind
it get written here once made, and are not revisited.*

## Retrieval

*The exact commands used to download and verify the file, so that a reader can
reproduce the starting state.*

## Load procedure

XES to Parquet to DuckDB, converted once. From that point every question is
answered in SQL against the DuckDB file.

*Record: the conversion command, row counts at each hop, and the documented
`SELECT COUNT(*) FROM events` figure that later loads are checked against.*

## Schema

### `events` - one row per event

*Columns, types, and what each field actually means in the source system.*

### `cases` - one row per case

*Derived from `events`. The grain decision and its justification are the point of
this section; the same reasoning is summarised in `REPORT.md`.*

## Cleaning decisions

Each entry: what was found, what was done, and what it could cost.

| # | Observation | Decision | Risk accepted |
|---|---|---|---|
| | | | |

## Known data quality issues

*Anything left unfixed, and why that was the right call. This section feeds the
caveats in `REPORT.md`.*
