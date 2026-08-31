"""
Shared DuckDB access for the project.

Every connection is opened here so that the session timezone is set in exactly
one place. See DATA.md, decision 4.
"""

import logging
from pathlib import Path

import duckdb

logger = logging.getLogger(__name__)
TIMEZONE = "Europe/Amsterdam"


def connect(db_path: str | Path = ":memory:") -> duckdb.DuckDBPyConnection:
    """Connect to a DuckDB database and set the timezone."""

    con = duckdb.connect(str(db_path))
    con.execute(f"SET TIMEZONE TO '{TIMEZONE}'")
    return con


def run_sql_file(con: duckdb.DuckDBPyConnection, sql_path: Path) -> None:
    """Function to run SQL file."""

    sql = sql_path.read_text()
    con.execute(sql)
    logger.info("ran %s", sql_path.name)
