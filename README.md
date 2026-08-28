# Where a loan application stalls

Analysis of a real, anonymised event log from a Dutch financial institution's
loan-application process: **where the elapsed time actually goes, and which
single change would shorten it most.**

> **Status: in progress.** The headline finding, the figure that carries it, and
> the memo land with the `report` deliverable.

---

## The question

*"Loan applications take too long and we don't know where the time goes. Tell us
where the process stalls, and what one change would shorten it most."*

The deliverable is a memo an operations lead could act on - a recommendation with
a number attached and the caveats that qualify it. Not a process map, not a model.

Full framing, scope and what was deliberately left out: [`BRIEF.md`](BRIEF.md).
Findings and recommendation: `REPORT.md` (arrives with the `report` deliverable).

## How it works

Every analytical question is answered in hand-written SQL against a DuckDB
database. Python's job is ingestion, orchestration of those queries, and one
figure - not analysis. Query logic used twice is promoted into the `procmine`
package and covered by tests against a small hand-built event log whose answers
are computable on paper.

```
src/procmine/     analytical logic, importable and tested
tests/            unit tests, incl. a five-case fixture log
notebooks/        numbered, thin, call into src/
data/raw/         untouched downloads (gitignored - see DATA.md to obtain)
data/processed/   derived Parquet / DuckDB store
figures/          the figure that carries the recommendation
```

## Data

BPI Challenge event log, published via 4TU.ResearchData. Source, licence,
retrieval steps and every cleaning decision are recorded in
[`DATA.md`](DATA.md).

## Running it

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev,ingest]"
pytest
```

Then follow [`DATA.md`](DATA.md) to fetch the log and build the DuckDB store.
