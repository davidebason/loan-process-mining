-- analysis/07_rework.sql
--
-- Q3: how much of the process is rework?
--
-- Reads: events, transitions (built by sql/01 and sql/06)
--
-- Approach: rank (activity, transition) pairs by how often they repeat within
-- a case, then decide from the ranking what counts as rework. The definition is
-- chosen after looking, not before, because some repetition is designed --
-- W_Call after offers repeats because the chase is meant to happen twice
-- (analysis/05) -- and some is a loop caused by something going wrong.
-- Whatever line gets drawn, write it into DATA.md as a decision with the
-- reasoning, the way decision 6 records the transition rules.

SET TimeZone = 'Europe/Amsterdam';
.mode markdown
.maxrows 60


-- 0. Does anything repeat at all, and how much?
--    One number to size the problem before ranking anything: of all
--    (case_id, activity, transition) combinations, what share occur more than
--    once? Cross-check: total events must equal (distinct combinations) plus
--    (excess occurrences). If it does not, the grain is wrong.
--
--    Hint: the useful building block for every section below is one CTE that
--    counts occurrences per (case_id, activity, transition). Write it once.
--    LAG is a window function, and windows are evaluated after GROUP BY, so an
--    aggregate cannot consume one in the same query. The gap is computed in a
--    CTE first, then averaged. NOTE the partition: PARTITION BY case_id means
--    gap_seconds is the time since the previous event of ANY kind. For the time
--    between successive occurrences of this pair, partition by
--    (case_id, activity, transition) instead -- see the check below.
CREATE OR REPLACE TEMP TABLE cases_rep_time AS
WITH gapped AS (                       -- ← stage 1: window runs here
    SELECT
        case_id,
        activity,
        transition,
        epoch(event_time) - epoch(LAG(event_time) OVER (
            PARTITION BY case_id
            ORDER BY event_time
        )) AS gap_seconds,
        -- occ_no counts occurrences of THIS pair, so occ_no = 1 is the first
        -- time the case reached it and occ_no > 1 are the repeats. Note the
        -- partition differs from LAG's: both windows run at the same stage,
        -- but they are answering different questions.
        ROW_NUMBER() OVER (
            PARTITION BY case_id, activity, transition
            ORDER BY event_time
        ) AS occ_no
    FROM events
)
SELECT
    case_id,
    activity,
    transition,
    COUNT(*) - 1                                AS n_rep_cases,
    COUNT(gap_seconds)                          AS n_gaps,
    AVG(gap_seconds)                            AS avg_gap_seconds,
    -- Sums carried through rather than rebuilt from the average. AVG x COUNT
    -- does equal SUM exactly, but only with COUNT(gap_seconds): AVG skips
    -- NULLs and a row count does not, so the identity breaks silently the
    -- moment a NULL gap appears. n_gaps is kept so that can be checked.
    SUM(gap_seconds)                            AS total_gap_seconds,
    SUM(gap_seconds) FILTER (WHERE occ_no > 1)  AS repeat_gap_seconds
FROM gapped
GROUP BY case_id, activity, transition
HAVING COUNT(*) > 1
;

CREATE OR REPLACE TEMP TABLE rep_summary AS
SELECT
    activity,
    transition,
    COUNT(*) FILTER (WHERE n_rep_cases > 0) AS n_rep,
    SUM(n_rep_cases) AS excess,
    MIN(n_rep_cases) AS min_at,
    MAX(n_rep_cases) AS max_at,
    AVG(n_rep_cases) AS mean_at,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY n_rep_cases) AS median_at,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY n_rep_cases) AS pc90_at
FROM cases_rep_time
GROUP BY activity, transition
;

/*
SELECT * FROM rep_summary ORDER BY n_rep DESC LIMIT 7;
SELECT * FROM rep_summary ORDER BY excess DESC LIMIT 7;
SELECT * FROM rep_summary ORDER BY mean_at DESC LIMIT 7;
SELECT * FROM rep_summary ORDER BY median_at DESC LIMIT 7;
SELECT * FROM rep_summary ORDER BY pc90_at DESC LIMIT 7;
*/

CREATE OR REPLACE TEMP TABLE time_summary AS
SELECT
    activity,
    transition,
    COUNT(*)                                AS cases,
    -- total_gap_days  : all waiting attached to this pair, first visit included
    -- repeat_gap_days : the same, counting only repeat visits (occ_no > 1).
    -- The difference is the one-off wait to reach the activity the first time,
    -- which is not rework.
    SUM(total_gap_seconds)  / 86400.0       AS total_gap_days,
    SUM(repeat_gap_seconds) / 86400.0       AS repeat_gap_days,
    100.0 * SUM(repeat_gap_seconds) / NULLIF(SUM(total_gap_seconds), 0) AS pct_in_repeats,
    AVG(avg_gap_seconds) / 3600.0           AS mean_gap_hours,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_gap_seconds) / 3600.0 AS median_gap_hours,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY avg_gap_seconds) / 3600.0 AS pc90_gap_hours
FROM cases_rep_time
GROUP BY activity, transition
;

SELECT * FROM time_summary ORDER BY repeat_gap_days DESC LIMIT 10;
SELECT * FROM time_summary ORDER BY total_gap_days DESC LIMIT 10;
SELECT * FROM time_summary ORDER BY mean_gap_hours DESC LIMIT 7;
SELECT * FROM time_summary ORDER BY median_gap_hours DESC LIMIT 7;
SELECT * FROM time_summary ORDER BY pc90_gap_hours DESC LIMIT 7;


-- 1. The ranking. One row per (activity, transition).
--
--    Columns worth having, and the reason for each:
--      cases_with_pair    -- how many cases contain it at all. This is the
--                            denominator for the next column. Do NOT use 31,509:
--                            a pair absent from a case is not a case where it
--                            failed to repeat.
--      cases_repeating    -- of those, how many see it more than once
--      pct_repeating      -- cases_repeating / cases_with_pair
--      mean_per_case      -- average occurrences among cases that have it
--      max_per_case       -- the worst case. Look for absurd values; they are
--                            usually a data problem, not a process problem.
--      excess             -- total occurrences minus one per case. This is the
--                            volume of repetition: the count of occurrences
--                            that would not exist if nothing ever repeated.
--
--    Order by excess. pct_repeating alone will float rare pairs to the top,
--    the same way the unguarded median ranking did in 06.


-- 2. Is the repetition designed or accidental?
--    Two shapes to separate, and this is the judgement Q3 turns on:
--      (a) a pair repeating a small, tight number of times in most cases that
--          have it -- that is process design, not waste
--      (b) a pair repeating a highly variable number of times in a minority of
--          cases -- that is a loop, and the tail is where the cost sits
--    A distribution of occurrences-per-case tells these apart. Consider a
--    histogram: occurrences, cases at that count, share.


-- 3. What does the repetition cost in time?
--    A count is not yet an answer to "how much is rework". Join back to
--    transitions and sum gap_seconds for the intervals that sit inside a
--    repeated stretch, then express it against the 690,035 total case-days from
--    06 so it is comparable with the waiting result.
--
--    Decide and record: does the clock start at the first occurrence or the
--    second? The first occurrence is not rework -- the work had to happen once.


-- 4. Which cases carry it?
--    Rework concentrated in 5% of cases is a different recommendation from
--    rework spread evenly. Rank cases by total excess occurrences and look at
--    the distribution, then check whether the heavy cases share an outcome
--    (A_Pending / A_Cancelled / A_Denied) or a channel.


-- 5. Checks. As in 06 section 5: regenerate any number that ends up quoted in
--    DATA.md or REPORT.md, so the prose traces to code here.
