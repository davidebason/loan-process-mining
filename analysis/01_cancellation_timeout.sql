-- analysis/01_cancellation_timeout.sql
--
-- Question: why do cancelled cases take 2.1x longer than successful ones?
--
-- Reads: cancellation_gaps, cancellations   (built by sql/05)
-- Known: inactivity before cancellation never exceeds 31.00 days, but only
--        5.8% of cases come within a day of that ceiling. So the ceiling is
--        real and is not where the volume is. Split by actor to find out why.

SET TimeZone = 'Europe/Amsterdam';
.mode markdown
.maxrows 100

-- 1. Base: every gap, with who performed the cancellation.
CREATE OR REPLACE TEMP TABLE gaps AS
SELECT
    cg.case_id,
    gap_from,
    gap_days,
    is_automated
FROM cancellation_gaps cg JOIN cancellations c ON cg.case_id = c.case_id;

-- 2. Summary per anchor, split by actor.
SELECT
    gap_from,
    is_automated,
    COUNT(*) AS n,
    MIN(gap_days) AS min_days,
    MEDIAN(gap_days) AS median,
    AVG(gap_days) AS mean,
    StdDev(gap_days) AS stddev,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY gap_days) AS p90,
    Max(gap_days) AS max_days
FROM gaps
GROUP BY gap_from, is_automated
ORDER BY gap_from, is_automated;


-- 3. The decisive one: how often does each whole-day value occur?
--    Restricted to the inactivity anchor.
SELECT
    is_automated,
    FLOOR(gap_days) AS gap_days_rounded, -- gap rounded down to whole days
    COUNT(*) AS n
FROM gaps
WHERE gap_from = 'previous_event'
GROUP BY is_automated, FLOOR(gap_days)
ORDER BY is_automated, FLOOR(gap_days);


-- 4. Concentration: what share of each group sits near the ceiling?
SELECT
    is_automated,
    COUNT(*) AS n,
    COUNT(*) FILTER (WHERE gap_days > 30) AS n_above_30,
    ROUND(COUNT(*) FILTER (WHERE gap_days > 30) * 100.0 / COUNT(*), 1) AS pct_above_30
FROM gaps
WHERE gap_from = 'previous_event'
GROUP BY is_automated;