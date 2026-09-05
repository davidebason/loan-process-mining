"""Tests for the three-table model, run against a five-case fixture.

Every expected value below was computed by hand from tests/fixtures/CASES.md,
independently of the SQL under test. A test whose expectation came from the
code it is testing proves nothing.
"""

from datetime import timedelta
from pathlib import Path

import pytest

from procmine import db

FIXTURES = Path(__file__).parent / "fixtures"
SQL_DIR = Path(__file__).resolve().parents[1] / "sql"

# Hand-verified totals across the five fixture cases.
EXPECTED_EVENTS = 94
EXPECTED_OFFERS = 6
EXPECTED_CASES = 5

# Hand-verified per case: (case_id, events, offers, end-to-end span).
CASE_FACTS = [
    (
        "Application_919038062",
        22,
        1,
        timedelta(hours=4, minutes=7, seconds=10, microseconds=714000),
    ),
    ("Application_2098856182", 13, 2, timedelta(minutes=17, seconds=43, microseconds=588000)),
    (
        "Application_323048075",
        30,
        1,
        timedelta(hours=20, minutes=57, seconds=30, microseconds=516000),
    ),
    ("Application_682602203", 11, 1, timedelta(minutes=16, seconds=8, microseconds=592000)),
    (
        "Application_1291275220",
        18,
        1,
        timedelta(days=6, hours=16, minutes=48, seconds=49, microseconds=489000),
    ),
]


@pytest.fixture(scope="module")
def mini_db():
    """In-memory database: the five-case fixture log with the model applied."""
    con = db.connect()
    db.run_sql_file(con, FIXTURES / "mini_log.sql")
    # Every file in sql/, not just the three base tables. The derived tables
    # carry every headline number in the project, and until this list included
    # them a syntax error in 04-06 could not fail the suite.
    for name in (
        "01_events.sql",
        "02_offers.sql",
        "03_cases.sql",
        "04_case_durations.sql",
        "05_cancellation_gaps.sql",
        "06_transitions.sql",
    ):
        db.run_sql_file(con, SQL_DIR / name)
    yield con
    con.close()


def scalar(con, sql: str, params: list | None = None):
    """Run a query expected to return one row and one column, and return that value.

    Fails loudly if the query returns no rows at all, rather than raising an
    obscure TypeError on a None result.
    """
    row = con.execute(sql, params or []).fetchone()
    assert row is not None, f"query returned no rows:\n{sql}"
    return row[0]


# --- table sizes -------------------------------------------------------
def test_events_row_count(mini_db):
    assert scalar(mini_db, "SELECT COUNT(*) FROM events") == EXPECTED_EVENTS


def test_offers_row_count(mini_db):
    assert scalar(mini_db, "SELECT COUNT(*) FROM offers") == EXPECTED_OFFERS


def test_cases_row_count(mini_db):
    assert scalar(mini_db, "SELECT COUNT(*) FROM cases") == EXPECTED_CASES


# --- keys --------------------------------------------------------------
def test_case_id_is_unique(mini_db):
    """cases is one row per application, so case_id cannot repeat."""
    duplicates = scalar(mini_db, "SELECT COUNT(*) - COUNT(DISTINCT case_id) FROM cases")
    assert duplicates == 0


def test_offer_id_is_unique(mini_db):
    duplicates = scalar(mini_db, "SELECT COUNT(*) - COUNT(DISTINCT offer_id) FROM offers")
    assert duplicates == 0


@pytest.mark.parametrize(
    "table, key",
    [("events", "event_id"), ("offers", "offer_id"), ("cases", "case_id")],
)
def test_primary_keys_are_never_null(mini_db, table, key):
    n_rows = scalar(mini_db, f"SELECT COUNT(*) FROM {table}")
    n_keys = scalar(mini_db, f"SELECT COUNT({key}) FROM {table}")
    assert n_rows == n_keys


@pytest.mark.parametrize("column", ["case_id", "activity", "event_time"])
def test_events_have_no_missing_essentials(mini_db, column):
    """Every analytical question depends on these three; a null would be silent."""
    n_rows = scalar(mini_db, "SELECT COUNT(*) FROM events")
    n_present = scalar(mini_db, f"SELECT COUNT({column}) FROM events")
    assert n_rows == n_present


# --- referential integrity ---------------------------------------------
def test_every_offer_belongs_to_a_known_case(mini_db):
    """LEFT JOIN + IS NULL is an anti-join: it returns offers with no matching case."""
    orphans = scalar(
        mini_db,
        """
        SELECT COUNT(*)
        FROM offers o
        LEFT JOIN cases c ON o.case_id = c.case_id
        WHERE c.case_id IS NULL
        """,
    )
    assert orphans == 0


def test_every_event_offer_id_exists_in_offers(mini_db):
    """events.offer_id is nullable, but where present it must resolve."""
    orphans = scalar(
        mini_db,
        """
        SELECT COUNT(*)
        FROM events e
        LEFT JOIN offers o ON e.offer_id = o.offer_id
        WHERE e.offer_id IS NOT NULL AND o.offer_id IS NULL
        """,
    )
    assert orphans == 0


def test_every_case_has_at_least_one_event(mini_db):
    orphans = scalar(
        mini_db,
        """
        SELECT COUNT(*)
        FROM cases c
        LEFT JOIN events e ON c.case_id = e.case_id
        WHERE e.case_id IS NULL
        """,
    )
    assert orphans == 0


# --- per-case facts, verified by hand ----------------------------------
@pytest.mark.parametrize("case_id, n_events, n_offers, span", CASE_FACTS)
def test_events_per_case(mini_db, case_id, n_events, n_offers, span):
    actual = scalar(mini_db, "SELECT COUNT(*) FROM events WHERE case_id = ?", [case_id])
    assert actual == n_events


@pytest.mark.parametrize("case_id, n_events, n_offers, span", CASE_FACTS)
def test_offers_per_case(mini_db, case_id, n_events, n_offers, span):
    actual = scalar(mini_db, "SELECT COUNT(*) FROM offers WHERE case_id = ?", [case_id])
    assert actual == n_offers


@pytest.mark.parametrize("case_id, n_events, n_offers, span", CASE_FACTS)
def test_case_span(mini_db, case_id, n_events, n_offers, span):
    """End-to-end elapsed time: last event minus first, per case."""
    actual = scalar(
        mini_db,
        "SELECT MAX(event_time) - MIN(event_time) FROM events WHERE case_id = ?",
        [case_id],
    )
    assert actual == span


# NOTE: "no negative durations" is not testable here. MAX(x) >= MIN(x) holds by
# definition for any group, so the check is vacuous against a single timestamp
# column. It becomes meaningful once cases carries derived first_event/last_event
# columns, or once deliverable 4 computes gaps with LAG - where a wrong PARTITION
# or ORDER genuinely can produce a negative interval.


# --- derived tables: transitions ---------------------------------------------
#
# Each test below corresponds to a defect that actually occurred during the
# project. A test that has never had a chance of failing is decoration.


def test_transitions_row_count(mini_db):
    """One transition per event, less the first event of each case.

    LAG returns NULL for a case's first event and 06 drops those rows, so the
    count is determined: 94 events across 5 cases gives 89 pairs.
    """
    assert scalar(mini_db, "SELECT COUNT(*) FROM transitions") == EXPECTED_EVENTS - EXPECTED_CASES


def test_no_negative_gaps(mini_db):
    """Time does not run backwards.

    Stated as a count of offending rows rather than MAX >= MIN, which is true
    by definition and can never fail.
    """
    assert scalar(mini_db, "SELECT COUNT(*) FROM transitions WHERE gap_seconds < 0") == 0


def test_gap_kind_covers_every_row(mini_db):
    """Classification is total: no row escapes as NULL or an unexpected value."""
    assert (
        scalar(
            mini_db,
            "SELECT COUNT(*) FROM transitions "
            "WHERE gap_kind IS NULL OR gap_kind NOT IN ('handling', 'waiting')",
        )
        == 0
    )


def test_bookkeeping_flag_matches_its_definition(mini_db):
    """DATA.md decision 6: sub-second gaps are flagged, not dropped."""
    assert (
        scalar(
            mini_db,
            "SELECT COUNT(*) FROM transitions WHERE bookkeeping <> (gap_seconds < 1.0)",
        )
        == 0
    )


def test_gaps_reconcile_to_case_duration(mini_db):
    """Summed consecutive gaps must equal each case's first-to-last elapsed time.

    This is the assertion that found both real duration bugs: epoch() applied
    to a calendar interval across a DST boundary, and the operator-precedence
    error introduced while fixing it. Neither was visible in any individual
    number; both were unmistakable in this aggregate.
    """
    disagreements = scalar(
        mini_db,
        """
        SELECT COUNT(*) FROM (
            SELECT t.case_id
            FROM (SELECT case_id, SUM(gap_seconds) AS summed
                  FROM transitions GROUP BY case_id) t
            JOIN (SELECT case_id,
                         epoch(MAX(event_time)) - epoch(MIN(event_time)) AS elapsed
                  FROM events GROUP BY case_id) c USING (case_id)
            WHERE ABS(t.summed - c.elapsed) > 0.001
        )
        """,
    )
    assert disagreements == 0


def test_epoch_of_an_interval_is_not_dst_safe(mini_db):
    """Regression guard for DATA.md known issue 9.

    Amsterdam springs forward on 2016-03-27, so 26 March noon to 28 March noon
    is 47 hours, not 48. epoch() on a calendar interval converts at 86,400
    seconds per day and returns 48; subtracting two absolute epochs returns 47.
    3,558 cases (11.3%) span a DST boundary in the full log.

    If this ever starts failing, DuckDB changed its semantics and every
    duration in sql/ needs rechecking -- it does not mean the bug is fixed.
    """
    via_interval, via_epochs = mini_db.execute(
        """
        SELECT epoch(TIMESTAMPTZ '2016-03-28 12:00:00+02'
                   - TIMESTAMPTZ '2016-03-26 12:00:00+01'),
               epoch(TIMESTAMPTZ '2016-03-28 12:00:00+02')
                   - epoch(TIMESTAMPTZ '2016-03-26 12:00:00+01')
        """
    ).fetchone()
    assert via_interval == 48 * 3600, "the unsafe form no longer returns 48 hours"
    assert via_epochs == 47 * 3600, "the safe form must return the true 47 hours"


def test_sql_uses_the_dst_safe_subtraction(mini_db):
    """No file in sql/ may call epoch() on a difference of two timestamps.

    Guards the fix itself rather than its effect: a reintroduced epoch(a - b)
    would pass the reconciliation test on any fixture that spans no boundary.

    The pattern allows one level of nesting inside the call, so it catches the
    aggregate form epoch(cancelled_at - MIN(event_time)) as well as the plain
    one, while not matching the correct epoch(a) - epoch(b). Two levels of
    nesting would slip through; nothing in sql/ currently goes that deep.
    """
    import re

    inner = r"(?:[^()]|\([^()]*\))*"
    pattern = re.compile(r"epoch\s*\(" + inner + r"-" + inner + r"\)", re.IGNORECASE)
    offenders = [
        f"{path.name}: {m.group(0)}"
        for path in sorted(SQL_DIR.glob("*.sql"))
        for m in pattern.finditer(path.read_text(encoding="utf-8"))
    ]
    assert not offenders, "epoch() applied to an interval: " + "; ".join(offenders)
