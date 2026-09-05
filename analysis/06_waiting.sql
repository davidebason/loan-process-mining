-- analysis/06_waiting.sql
--
-- Q2: between which two activities does the most waiting time accumulate?
--
-- Reads: transitions (built by sql/06)
--
-- Sub-second pairs are kept in the row counts and the totals, and excluded from
-- the percentiles via FILTER, see DATA.md decision 6. They are 44.9% of rows and
-- 0.0001% of elapsed time, so dropping them outright would break reconciliation
-- against case duration while leaving every total unchanged; but including them in
-- a median drags it into the noise (W_Complete application start->complete: 5
-- microseconds with them, 6.2 minutes without). n and n_real show the split.

SET TimeZone = 'Europe/Amsterdam';
.mode markdown
.maxrows 60


-- 0. The headline: how much of the process is waiting, and how much is work?
--    total days, and share of all elapsed time, split by gap_kind.
CREATE OR REPLACE TEMP TABLE time_elapsed AS
SELECT
    gap_kind,
    same_activity,
    SUM(gap_seconds) / 86400.0 AS total_days,
    (SUM(gap_seconds) FILTER (WHERE bookkeeping)) / 86400.0 AS total_bookkeeping,
    100.0 * (SUM(gap_seconds) FILTER (WHERE bookkeeping)) / SUM(gap_seconds) AS pct_bookkeeping,
    SUM(gap_seconds) FILTER (WHERE NOT bookkeeping) / 86400.0        AS real_days,
    100.0 * SUM(gap_seconds) FILTER (WHERE NOT bookkeeping)
        / SUM(SUM(gap_seconds) FILTER (WHERE NOT bookkeeping)) OVER ()  AS pct_of_real_elapsed
FROM transitions
GROUP BY gap_kind, same_activity
;
SELECT * FROM time_elapsed ORDER BY total_days DESC;


-- 1. Waiting inside one work item. to_activity is omitted because
--    same_activity is true here by construction, so it equals from_activity.
SELECT
    from_activity,
    from_transition,
    to_transition,
    COUNT(*) AS n,
    COUNT(*) FILTER (WHERE NOT bookkeeping) AS n_real,
    SUM(gap_seconds) / 86400.0 AS total_days,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gap_seconds) FILTER (WHERE NOT bookkeeping) / 3600.0 AS median_hours,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY gap_seconds) FILTER (WHERE NOT bookkeeping) / 3600.0 AS p90_hours,
    100.0 * SUM(gap_seconds) / (SELECT SUM(gap_seconds) FROM transitions) AS pct_of_all_elapsed
FROM transitions
WHERE gap_kind = 'waiting' AND same_activity
GROUP BY from_activity, from_transition, to_transition
ORDER BY total_days DESC
LIMIT 20
;

--2. Waiting across different work items.
SELECT
    from_activity,
    from_transition,
    to_activity,
    to_transition,
    COUNT(*) AS n,
    COUNT(*) FILTER (WHERE NOT bookkeeping) AS n_real,
    SUM(gap_seconds) / 86400.0 AS total_days,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gap_seconds) FILTER (WHERE NOT bookkeeping) / 3600.0 AS median_hours,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY gap_seconds) FILTER (WHERE NOT bookkeeping) / 3600.0 AS p90_hours,
    100.0 * SUM(gap_seconds) / (SELECT SUM(gap_seconds) FROM transitions) AS pct_of_all_elapsed
FROM transitions
WHERE gap_kind = 'waiting' AND NOT same_activity
GROUP BY from_activity, from_transition, to_activity, to_transition
ORDER BY total_days DESC
LIMIT 20
;

--3. Handling.
SELECT
    from_activity,
    from_transition,
    to_activity,
    to_transition,
    COUNT(*) AS n,
    COUNT(*) FILTER (WHERE NOT bookkeeping) AS n_real,
    SUM(gap_seconds) / 86400.0 AS total_days,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gap_seconds) FILTER (WHERE NOT bookkeeping) / 3600.0 AS median_hours,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY gap_seconds) FILTER (WHERE NOT bookkeeping) / 3600.0 AS p90_hours,
    100.0 * SUM(gap_seconds) / (SELECT SUM(gap_seconds) FROM transitions) AS pct_of_all_elapsed
FROM transitions
WHERE gap_kind = 'handling'
GROUP BY from_activity, from_transition, to_activity, to_transition
ORDER BY total_days DESC
LIMIT 20
;

-- 4. All three families pooled, ranked by median rather than by total.
--    1-3 answer "where does the aggregate time pool sit", a capacity question.
--    This answers "when this step happens, how long does that case wait": a
--    severity question. The two diverge when n is small: a step occurring 158
--    times with a 7.8-day median is 0.2% of elapsed time and invisible above.
--    HAVING COUNT(*) >= 100 so that a median rests on ~50 observations a side;
--    without it the ranking opens on groups of n = 1.
--    gap_kind is a pure function of from_transition (verified: no from_transition
--    carries two gap_kinds), so grouping by it splits nothing: it is display.
SELECT
    gap_kind,
    same_activity,
    from_activity,
    from_transition,
    to_activity,
    to_transition,
    COUNT(*) AS n,
    COUNT(*) FILTER (WHERE NOT bookkeeping) AS n_real,
    SUM(gap_seconds) / 86400.0 AS total_days,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gap_seconds) FILTER (WHERE NOT bookkeeping) / 3600.0 AS median_hours,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY gap_seconds) FILTER (WHERE NOT bookkeeping) / 3600.0 AS p90_hours,
    100.0 * SUM(gap_seconds) / (SELECT SUM(gap_seconds) FROM transitions) AS pct_of_all_elapsed
FROM transitions
GROUP BY gap_kind, same_activity, from_activity, from_transition, to_activity, to_transition
HAVING COUNT(*) >= 100
ORDER BY median_hours DESC
LIMIT 30
;

-- 5. The checks behind the DATA.md caveats. These produce no findings; they
--    generate the numbers quoted in decision 6 and known issue 8, so that
--    every figure in the prose traces to code here.

-- 5a. Grain: omitting to_activity merges groups that are not the same transition.
--     Quoted in decision 6 as 179 -> 427, with 80 groups pooling 328 destinations.
SELECT
    (SELECT COUNT(*) FROM (SELECT 1 FROM transitions
        GROUP BY from_activity, from_transition, to_transition))              AS groups_without_to_activity,
    (SELECT COUNT(*) FROM (SELECT 1 FROM transitions
        GROUP BY from_activity, from_transition, to_activity, to_transition)) AS groups_with_to_activity,
    (SELECT COUNT(*) FROM (SELECT 1 FROM transitions
        GROUP BY from_activity, from_transition, to_transition
        HAVING COUNT(DISTINCT to_activity) > 1))                              AS merged_groups,
    (SELECT SUM(d) FROM (SELECT COUNT(DISTINCT to_activity) AS d FROM transitions
        GROUP BY from_activity, from_transition, to_transition
        HAVING COUNT(DISTINCT to_activity) > 1))                              AS destinations_pooled
;

-- 5b. Concurrency: how often does a case hold two work items open at once?
--     A work item is open from `schedule` until complete / ate_abort / withdraw.
--     Sweep +1/-1 along each case's timeline and take the running maximum.
--     Quoted in known issue 8 as 99.77% at one item, 0.23% at two.
WITH marks AS (
    SELECT
        case_id,
        event_time,
        CASE WHEN transition = 'schedule'                             THEN  1
             WHEN transition IN ('complete', 'ate_abort', 'withdraw') THEN -1
             ELSE 0 END AS delta
    FROM events
    WHERE activity LIKE 'W\_%' ESCAPE '\'
),
running AS (
    SELECT
        case_id,
        SUM(delta) OVER (PARTITION BY case_id ORDER BY event_time
                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS open_items
    FROM marks
),
per_case AS (
    SELECT case_id, MAX(open_items) AS max_concurrent FROM running GROUP BY case_id
)
SELECT
    max_concurrent,
    COUNT(*)                                    AS cases,
    100.0 * COUNT(*) / SUM(COUNT(*)) OVER ()    AS pct_of_cases
FROM per_case
GROUP BY max_concurrent
ORDER BY max_concurrent
;

-- 5c. Why 5b is trustworthy: the sweep must never go negative (that would mean
--     an item closed without opening), and schedules less closes must equal the
--     174 work items left open at the 2017-02-01 censoring date (issue 7).
WITH marks AS (
    SELECT
        case_id,
        event_time,
        CASE WHEN transition = 'schedule'                             THEN  1
             WHEN transition IN ('complete', 'ate_abort', 'withdraw') THEN -1
             ELSE 0 END AS delta
    FROM events
    WHERE activity LIKE 'W\_%' ESCAPE '\'
),
running AS (
    SELECT
        SUM(delta) OVER (PARTITION BY case_id ORDER BY event_time
                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS open_items
    FROM marks
)
SELECT
    (SELECT MIN(open_items) FROM running)                              AS worst_running_total,
    (SELECT COUNT(*) FROM events
       WHERE activity LIKE 'W\_%' ESCAPE '\' AND transition = 'schedule') AS schedules,
    (SELECT COUNT(*) FROM events
       WHERE activity LIKE 'W\_%' ESCAPE '\'
         AND transition IN ('complete', 'ate_abort', 'withdraw'))      AS closes,
    (SELECT COUNT(*) FROM events
       WHERE activity LIKE 'W\_%' ESCAPE '\' AND transition = 'schedule')
  - (SELECT COUNT(*) FROM events
       WHERE activity LIKE 'W\_%' ESCAPE '\'
         AND transition IN ('complete', 'ate_abort', 'withdraw'))      AS left_open
;
