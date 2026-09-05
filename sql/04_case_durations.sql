-- 04_case_durations.sql
--
-- Q1: how long does an application take end to end, and how does that vary?
--
-- Produces: case_durations, grain is one row per application.
-- Reads:    events
-- Caveat:   98 cases have no terminal state; their span is truncated by the
--           log's cut-off, not by the process ending. See DATA.md.

SET TimeZone = 'Europe/Amsterdam';

-- 1. One row per case, with its span.
CREATE OR REPLACE TABLE case_durations AS
SELECT
    case_id,
    MIN(event_time) AS first_event,
    MAX(event_time) AS last_event,
    (epoch(MAX(event_time)) - epoch(MIN(event_time))) / 3600.0 AS duration_hours,
    COUNT(*) AS n_events,
    MAX(CASE WHEN activity IN ('A_Pending', 'A_Cancelled', 'A_Denied')
         THEN activity END) AS outcome
FROM events
GROUP BY case_id;

-- 2. Sanity: this must equal 31,509, and 5 against the fixture.
SELECT COUNT(*) AS n_cases FROM case_durations;

-- 3. The distribution. The spread is the finding, not the average.
SELECT
    COUNT(*) AS n_cases,
    MIN(duration_hours) AS min_duration,
    MEDIAN(duration_hours) AS median_duration,
    AVG(duration_hours) AS mean_duration,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY duration_hours) AS p90_duration,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_hours) AS p99_duration,
    MAX(duration_hours) AS max_duration
FROM case_durations;

-- 4. Split by outcome, censored cases are truncated, and denied cases
--    almost certainly behave differently from successful ones.
SELECT
    outcome,
    COUNT(*)                                    AS n_cases,
    ROUND(MEDIAN(duration_hours), 1)            AS median_hours,
    ROUND(QUANTILE_CONT(duration_hours, 0.9), 1) AS p90_hours
FROM case_durations
GROUP BY outcome
ORDER BY n_cases DESC;