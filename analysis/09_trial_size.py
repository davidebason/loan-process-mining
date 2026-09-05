"""How large would the day-14 trial have to be, and how long would it take?

Supports the sizing quoted in REPORT.md: "roughly 3,000 applications over two
months detects any effect above three percentage points".

The control acceptance rate and the eligible population both come from
analysis/08 section H, which measures applications still unresolved fourteen
days after the last offer was sent. Nothing here reads the database; it is
arithmetic on those two figures, kept in the repository so the sizing can be
rerun when they change.

Run:  python analysis/09_trial_size.py
"""

from __future__ import annotations

# Two-sided test at alpha = 0.05 with 80% power. Normal approximation, which is
# ample at these sample sizes and these proportions.
Z_ALPHA = 1.959964
Z_BETA = 0.841621

# From analysis/08 section H.
CONTROL_RATE = 0.399
ELIGIBLE_PER_YEAR = 16_727

# From analysis/08 section E: the mean principal on an offer that lapsed.
MEAN_LAPSED_PRINCIPAL = 16_864


def arm_sizes(uplift_pp: float, frac_treated: float = 0.5) -> tuple[float, float]:
    """Return (treated, control) needed to detect `uplift_pp` percentage points.

    `frac_treated` below 0.5 limits how many applications are exposed to an
    intervention that might turn out to be harmful, at the cost of a larger
    total and a longer trial.
    """
    p1 = CONTROL_RATE
    p2 = p1 + uplift_pp / 100
    ratio = (1 - frac_treated) / frac_treated
    variance = p1 * (1 - p1) / ratio + p2 * (1 - p2)
    treated = (Z_ALPHA + Z_BETA) ** 2 * variance / (p2 - p1) ** 2
    return treated, treated * ratio


def months(total: float) -> float:
    return total / ELIGIBLE_PER_YEAR * 12


def main() -> None:
    print(f"control acceptance {CONTROL_RATE:.1%}, eligible {ELIGIBLE_PER_YEAR:,} per year\n")

    print("Detectable effect against trial size, balanced 50/50:\n")
    header = f"{'uplift':>7} {'treated':>9} {'control':>9} {'total':>9}"
    print(f"{header} {'months':>8} {'value / year':>14}")
    for uplift in (1, 2, 3, 5, 8):
        treated, control = arm_sizes(uplift)
        total = treated + control
        value = ELIGIBLE_PER_YEAR * uplift / 100 * MEAN_LAPSED_PRINCIPAL
        print(
            f"{uplift:>5.0f}pp {treated:>9,.0f} {control:>9,.0f} {total:>9,.0f} "
            f"{months(total):>8.1f} {value / 1e6:>13.1f}m"
        )

    print("\nSame 5pp effect, treating a smaller share to limit exposure:\n")
    print(f"{'treated':>8} {'n treated':>10} {'n control':>10} {'total':>9} {'months':>8}")
    for frac in (0.5, 0.3, 0.2, 0.1):
        treated, control = arm_sizes(5, frac)
        total = treated + control
        row = f"{frac:>7.0%} {treated:>10,.0f} {control:>10,.0f} {total:>9,.0f}"
        print(f"{row} {months(total):>8.1f}")

    treated, control = arm_sizes(5)
    print(
        f"\nBounded downside: if the call HURTS by 5pp, a balanced trial exposes "
        f"{treated:,.0f} applications\nover {months(treated + control):.1f} months, "
        f"costing about {treated * 0.05 * MEAN_LAPSED_PRINCIPAL / 1e6:.1f}m once. "
        f"The upside repeats every year."
    )


if __name__ == "__main__":
    main()
