"""Build the report figure: what happens after an offer is sent.

One figure, because it has to carry the whole recommendation. It shows the
problem and the reason the obvious fix fails, in the same axes:

  - Cancellations pile against a wall at day 30. That wall is an automated
    expiry, not a customer decision: 7,932 of them land within four hours of
    30.0 days after the last offer was sent, a standard deviation of 0.156
    days against 16.4 for the human cancellations.
  - Acceptances are still arriving well past day 14, which is why shortening
    the expiry to 14 days costs 6,880 conversions (39.9%) to save 3.5 days
    of median cycle time.

Run:  python figures/make_figure.py
Reads data/processed/loans.duckdb, writes figures/offer_response.png.
"""

from __future__ import annotations

import logging
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.ticker import FuncFormatter  # noqa: E402

from procmine import db  # noqa: E402

logger = logging.getLogger(__name__)

REPO = Path(__file__).resolve().parents[1]
DB_PATH = REPO / "data" / "processed" / "loans.duckdb"
OUT_PATH = REPO / "figures" / "offer_response.png"

# Days from the last offer being sent to the case reaching a terminal state.
QUERY = """
WITH last_offer AS (
    SELECT case_id, MAX(event_time) AS sent_at
    FROM events
    WHERE activity LIKE 'O_Sent%' AND transition = 'complete'
    GROUP BY case_id
),
terminal AS (
    SELECT case_id, activity AS outcome, MIN(event_time) AS resolved_at
    FROM events
    WHERE transition = 'complete'
      AND activity IN ('A_Pending', 'A_Cancelled', 'A_Denied')
    GROUP BY case_id, activity
)
SELECT t.outcome,
       (epoch(t.resolved_at) - epoch(o.sent_at)) / 86400.0 AS days
FROM terminal t
JOIN last_offer o USING (case_id)
WHERE t.resolved_at >= o.sent_at
"""

EXPIRY_DAYS = 30
PROPOSED_CUT = 14
XMAX = 45

INK = "#1a1a1a"
MUTED = "#666666"
GRID = "#d8d8d8"
ACCEPTED = "#2166ac"   # blue
CANCELLED = "#b2182b"  # red


def fetch(con) -> tuple[dict[str, list[float]], dict[str, int]]:
    """Return ({outcome: [days]}, {outcome: n_excluded}) for the two outcomes shown."""
    rows = con.execute(QUERY).fetchall()
    series: dict[str, list[float]] = {"A_Pending": [], "A_Cancelled": []}
    excluded: dict[str, int] = {"A_Pending": 0, "A_Cancelled": 0}
    for outcome, days in rows:
        if outcome not in series:
            continue
        if 0 <= days <= XMAX:
            series[outcome].append(days)
        else:
            excluded[outcome] += 1
    return series, excluded


def build(series: dict[str, list[float]], excluded: dict[str, int]) -> plt.Figure:
    """Draw the figure. Returns it rather than saving, so a caller can test it."""
    fig, ax = plt.subplots(figsize=(10, 5.4), dpi=200)
    bins = range(0, XMAX + 1)

    ax.hist(
        series["A_Pending"], bins=bins, color=ACCEPTED, alpha=0.85,
        label=f"Accepted  (n={len(series['A_Pending']):,})",
    )
    ax.hist(
        series["A_Cancelled"], bins=bins, color=CANCELLED, alpha=0.85,
        label=f"Cancelled  (n={len(series['A_Cancelled']):,})",
    )

    top = ax.get_ylim()[1]

    ax.axvline(EXPIRY_DAYS, color=INK, lw=1.1, ls="--", zorder=5)
    ax.annotate(
        "7,932 cancellations land within four hours of\n"
        "30.0 days, a standard deviation of 0.16 days.\n"
        "This is an automated expiry, not a decision.",
        xy=(EXPIRY_DAYS - 0.4, top * 0.96),
        xytext=(EXPIRY_DAYS - 5.5, top * 0.70),
        color=INK, fontsize=9.5, ha="right", va="center",
        arrowprops={"arrowstyle": "->", "color": INK, "lw": 1,
                    "connectionstyle": "arc3,rad=0.28"},
    )

    ax.axvspan(PROPOSED_CUT, XMAX, color="#000000", alpha=0.045, zorder=0)
    ax.axvline(PROPOSED_CUT, color=INK, lw=1.1, ls=":", zorder=5)
    ax.annotate(
        "Cutting the expiry to 14 days removes\n"
        "everything shaded: 3.5 days of median\n"
        "cycle time saved, 6,880 conversions lost.",
        xy=(PROPOSED_CUT + 0.6, top * 0.40),
        color=INK, fontsize=9.5, ha="left", va="center",
    )

    ax.set_xlabel("Days from the last offer being sent to the application being resolved")
    ax.set_ylabel("Applications")
    ax.set_xlim(0, XMAX)
    ax.set_title(
        "Cancellations are a timer expiring, not customers saying no",
        fontsize=13.5, fontweight="bold", color=INK, loc="left", pad=14,
    )
    ax.yaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{v:,.0f}"))
    ax.legend(frameon=False, loc="upper left", fontsize=10)
    ax.grid(axis="y", color=GRID, lw=0.7)
    ax.set_axisbelow(True)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(GRID)

    fig.text(
        0.125, -0.02,
        "BPI Challenge 2017. Applications resolved within 45 days of the last offer; "
        f"{excluded['A_Pending']} accepted and {excluded['A_Cancelled']} cancelled "
        "cases fall outside that window. "
        "Source: sql/05_cancellation_gaps.sql, analysis/01, analysis/02.",
        fontsize=8, color=MUTED, ha="left",
    )
    fig.tight_layout()
    return fig


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    con = db.connect(str(DB_PATH))
    try:
        series, excluded = fetch(con)
    finally:
        con.close()
    fig = build(series, excluded)
    OUT_PATH.parent.mkdir(exist_ok=True)
    fig.savefig(OUT_PATH, bbox_inches="tight", facecolor="white")
    logger.info(
        "wrote %s  (accepted %d, cancelled %d; excluded %d / %d)",
        OUT_PATH, len(series["A_Pending"]), len(series["A_Cancelled"]),
        excluded["A_Pending"], excluded["A_Cancelled"],
    )


if __name__ == "__main__":
    main()
