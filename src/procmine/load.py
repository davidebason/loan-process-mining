"""Load the BPI Challenge 2017 event log into DuckDB.

Converts the source XES to Parquet once, then loads that Parquet into a DuckDB
database as a single raw table. No modelling decisions are made here - this
only changes the file format so that everything afterwards can be done in SQL.
The three analytical tables (cases, offers, events) are built in SQL under
sql/. See DATA.md for provenance and the decisions behind that model.
"""

import logging
import time
from pathlib import Path

import duckdb
import pm4py

logger = logging.getLogger(__name__)


# --- stage 1: XES -> Parquet -------------------------------------------
def xes_to_parquet(xes_path: Path, parquet_path: Path) -> int:
    """Parse an XES event log and write it to Parquet.

    Creates the destination directory if it does not exist. Returns the number
    of events written, so the caller can check it against a documented figure.
    """
    # First check that the XES log exists
    if not xes_path.exists():
        raise FileNotFoundError(f"XES log not found: {xes_path}")

    t0 = time.time()
    logger.info("reading %s", xes_path)
    df = pm4py.read_xes(str(xes_path))
    logger.info("parsed %s rows x %s cols in %.0fs", f"{len(df):,}", df.shape[1], time.time() - t0)

    t1 = time.time()
    parquet_path.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(parquet_path, index=False)
    size_mb = parquet_path.stat().st_size / 1e6
    logger.info("wrote %s (%.1f MB) in %.0fs", parquet_path, size_mb, time.time() - t1)

    return len(df)


# --- stage 2: Parquet -> DuckDB ----------------------------------------
def parquet_to_duckdb(parquet_path: Path, db_path: Path, table: str = "raw_events") -> int:
    """Load a Parquet file into DuckDB, replacing `table` if it exists.

    Only the named table is touched; any other tables in the database survive.
    Returns the number of rows loaded.
    """
    t2 = time.time()

    with duckdb.connect(str(db_path)) as con:
        con.execute(f"CREATE OR REPLACE TABLE {table} AS SELECT * FROM '{parquet_path}'")

        n_rows = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        n_cases = con.execute(
            f'SELECT COUNT(DISTINCT "case:concept:name") FROM {table}'
        ).fetchone()[0]

    db_mb = db_path.stat().st_size / 1e6
    logger.info(
        "loaded %s rows (%s cases) into %s (%.1f MB) in %.0fs",
        f"{n_rows:,}",
        f"{n_cases:,}",
        db_path,
        db_mb,
        time.time() - t2,
    )

    return n_rows


def main() -> None:
    """Rebuild the raw DuckDB table from the source XES log."""
    # Log configuration
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    # Paths
    project_root = Path(__file__).resolve().parents[2]
    raw = project_root / "data" / "raw" / "BPI_Challenge_2017.xes.gz"
    parquet = project_root / "data" / "processed" / "raw_events.parquet"
    db = project_root / "data" / "processed" / "loans.duckdb"

    # Final things
    n_parquet = xes_to_parquet(raw, parquet)
    n_db = parquet_to_duckdb(parquet, db)

    # The two counts must agree; a silent row loss would not announce itself.
    if n_parquet != n_db:
        raise RuntimeError(f"row count mismatch: parquet {n_parquet:,}, duckdb {n_db:,}")

    logger.info("done: %s rows in %s", f"{n_db:,}", db)


if __name__ == "__main__":
    main()
