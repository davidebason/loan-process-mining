-- analysis/08_report_numbers.sql
--
-- Regenerates every figure quoted in REPORT.md that no other file produces.
--
-- Reads: events, offers, case_durations, transitions (sql/01 to sql/06)
--
-- PIPELINE.md invariant 9 says every number in the prose traces to code in the
-- repository. Files 01 to 07 answer the four analytical questions, but several
-- headline figures are totals or shares computed across their output rather
-- than printed by any of them. This file closes that gap. Each section names
-- the sentence in REPORT.md it supports, so a reader can go from a figure in
-- the memo to the query that produces it.

SET TimeZone = 'Europe/Amsterdam';
.mode markdown
.maxrows 40


-- ===========================================================================
-- A. Finding 4: "690,035 application-days ... 565 days handling ... 0.08%"
--    and the four-way split table, and "roughly 26 minutes per application".
--    analysis/06 prints the four rows; it never prints their totals.
-- ===========================================================================
.print === A. work versus waiting, with the totals Finding 4 quotes ===
SELECT
    gap_kind,
    same_activity,
    ROUND(SUM(gap_seconds) / 86400.0)                                     AS days,
    ROUND(100.0 * SUM(gap_seconds) / SUM(SUM(gap_seconds)) OVER (), 2)    AS pct_of_elapsed
FROM transitions
GROUP BY gap_kind, same_activity
ORDER BY days DESC
;

SELECT
    ROUND(SUM(gap_seconds) / 86400.0)                                       AS total_days,
    ROUND(SUM(gap_seconds) FILTER (WHERE gap_kind = 'handling') / 86400.0)  AS handling_days,
    ROUND(100.0 * SUM(gap_seconds) FILTER (WHERE gap_kind = 'handling')
          / SUM(gap_seconds), 3)                                            AS pct_handling,
    -- "roughly 26 minutes per application"
    ROUND(SUM(gap_seconds) FILTER (WHERE gap_kind = 'handling')
          / (SELECT COUNT(*) FROM case_durations) / 60.0, 1)                AS handling_minutes_per_case,
    -- the sensitivity quoted in Finding 4: twenty times the measured figure
    ROUND(20 * SUM(gap_seconds) FILTER (WHERE gap_kind = 'handling')
          / (SELECT COUNT(*) FROM case_durations) / 3600.0, 1)              AS hours_per_case_at_20x,
    ROUND(100.0 * 20 * SUM(gap_seconds) FILTER (WHERE gap_kind = 'handling')
          / (SELECT COUNT(*) FROM case_durations)
          / (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_hours) * 3600
             FROM case_durations), 2)                                       AS pct_of_median_cycle_at_20x
FROM transitions
;


-- ===========================================================================
-- B. Finding 1: "215,677 days, 31.3% of all elapsed time".
--    The transitions that end in the automatic cancellation.
-- ===========================================================================
.print
.print === B. the expiry clock as a share of all elapsed time ===
SELECT
    COUNT(*)                                                          AS transitions,
    COUNT(DISTINCT case_id)                                           AS applications,
    ROUND(SUM(gap_seconds) / 86400.0)                                 AS days,
    ROUND(100.0 * SUM(gap_seconds)
          / (SELECT SUM(gap_seconds) FROM transitions), 1)            AS pct_of_all_elapsed,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gap_seconds) / 86400.0, 2) AS median_days
FROM transitions
WHERE to_activity = 'A_Cancelled' AND to_transition = 'complete'
;


-- ===========================================================================
-- C. Finding 1: "213,200 application-days, 30.9% of all elapsed time",
--    measured from the last action by any human to the automated cancellation.
--    User_1 is the system account established in analysis/01 and analysis/03.
-- ===========================================================================
.print
.print === C. elapsed time after the last human touch ===
WITH auto_cancelled AS (
    SELECT case_id, event_time AS cancelled_at
    FROM events
    WHERE activity = 'A_Cancelled' AND transition = 'complete' AND resource = 'User_1'
),
last_human AS (
    SELECT case_id, MAX(event_time) AS last_touch
    FROM events
    WHERE resource <> 'User_1'
    GROUP BY case_id
),
-- restricted to the applications that actually received an offer, so this is
-- the same 7,932 population the rest of the memo quotes. 21 further User_1
-- cancellations never reached an offer and are excluded.
had_an_offer AS (
    SELECT DISTINCT case_id FROM events
    WHERE starts_with(activity, 'O_Sent') AND transition = 'complete'
)
SELECT
    COUNT(*)                                                                       AS applications,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY (epoch(cancelled_at) - epoch(last_touch)) / 86400.0), 2)          AS median_silent_days,
    ROUND(SUM((epoch(cancelled_at) - epoch(last_touch)) / 86400.0))                AS total_silent_days,
    ROUND(100.0 * SUM(epoch(cancelled_at) - epoch(last_touch))
          / (SELECT SUM(gap_seconds) FROM transitions), 1)                         AS pct_of_all_elapsed
FROM auto_cancelled JOIN last_human USING (case_id) JOIN had_an_offer USING (case_id)
;


-- ===========================================================================
-- D. Finding 1: "Cancelled 31.6 days, Accepted 14.8, Denied 14.1".
--    The table showing the slowest applications are the ones that fail.
-- ===========================================================================
.print
.print === D. end-to-end duration by outcome ===
SELECT
    outcome,
    COUNT(*)                                                                    AS applications,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_hours) / 24, 1)  AS median_days,
    ROUND(AVG(duration_hours) / 24, 1)                                          AS mean_days
FROM case_durations
WHERE outcome IS NOT NULL
GROUP BY outcome
ORDER BY median_days DESC
;


-- ===========================================================================
-- E. Summary and recommendation: "EUR 133.8m of principal and EUR 25.3m of
--    gross interest, 23.5% of everything the bank offers", and the average
--    lapsed loan of EUR 16,864 against EUR 18,909 for an accepted one.
--
--    Grain: one row per application that ever received an offer, carrying the
--    LAST offer sent to it. A replaced offer is not counted separately, since
--    the bank was never going to lend both.
-- ===========================================================================
.print
.print === E. offered principal, by what happened to the application ===
CREATE OR REPLACE TEMP TABLE offer_fate AS
WITH last_sent AS (
    SELECT case_id, offer_id,
           ROW_NUMBER() OVER (PARTITION BY case_id ORDER BY event_time DESC) AS rn
    FROM events
    WHERE starts_with(activity, 'O_Sent') AND transition = 'complete'
      AND offer_id IS NOT NULL
),
auto_cancelled AS (
    SELECT DISTINCT case_id FROM events
    WHERE activity = 'A_Cancelled' AND transition = 'complete' AND resource = 'User_1'
)
SELECT
    s.case_id,
    CASE WHEN cd.outcome = 'A_Pending'   THEN 'accepted'
         WHEN a.case_id IS NOT NULL      THEN 'lapsed at the timer'
         WHEN cd.outcome = 'A_Cancelled' THEN 'cancelled by staff'
         WHEN cd.outcome = 'A_Denied'    THEN 'denied by the bank'
         ELSE 'still open' END                                       AS fate,
    o.offered_amount,
    o.monthly_cost * o.number_terms - o.offered_amount               AS gross_interest
FROM last_sent s
JOIN offers        o  ON o.offer_id = s.offer_id
JOIN case_durations cd ON cd.case_id = s.case_id
LEFT JOIN auto_cancelled a ON a.case_id = s.case_id
WHERE s.rn = 1
;

SELECT
    fate,
    COUNT(*)                                                                   AS applications,
    ROUND(AVG(offered_amount))                                                 AS mean_principal,
    ROUND(SUM(offered_amount) / 1e6, 1)                                        AS principal_m,
    ROUND(100.0 * SUM(offered_amount) / SUM(SUM(offered_amount)) OVER (), 1)   AS pct_of_principal,
    ROUND(SUM(gross_interest) / 1e6, 1)                                        AS interest_m
FROM offer_fate
GROUP BY fate
ORDER BY principal_m DESC
;


-- ===========================================================================
-- F. Finding 3: "100,441 days, 14.6% of all elapsed time", "forty-nine
--    distinct activity steps repeat", and the shares of the process and of
--    all repetition quoted in the first Finding 3 table.
--
--    Same definitions as analysis/07: a repetition is the same
--    (activity, transition) pair occurring more than once in a case, and the
--    time attributed to it is the gap before each occurrence after the first.
-- ===========================================================================
.print
.print === F. repetition totals and shares ===
CREATE OR REPLACE TEMP TABLE repeats AS
WITH gapped AS (
    SELECT
        case_id, activity, transition,
        epoch(event_time) - epoch(LAG(event_time) OVER (
            PARTITION BY case_id ORDER BY event_time)) AS gap_seconds,
        ROW_NUMBER() OVER (
            PARTITION BY case_id, activity, transition ORDER BY event_time) AS occ_no
    FROM events
)
SELECT case_id, activity, transition,
       SUM(gap_seconds) FILTER (WHERE occ_no > 1) AS repeat_gap_seconds
FROM gapped
GROUP BY case_id, activity, transition
HAVING COUNT(*) > 1
;

SELECT
    COUNT(*) FILTER (WHERE TRUE)                                          AS case_pair_rows,
    (SELECT COUNT(*) FROM (SELECT 1 FROM repeats GROUP BY activity, transition)) AS distinct_steps_repeating,
    ROUND(SUM(repeat_gap_seconds) / 86400.0)                              AS repetition_days,
    ROUND(100.0 * SUM(repeat_gap_seconds)
          / (SELECT SUM(gap_seconds) FROM transitions), 1)                AS pct_of_all_elapsed
FROM repeats
;

SELECT
    activity, transition,
    COUNT(*)                                                               AS applications,
    ROUND(SUM(repeat_gap_seconds) / 86400.0)                               AS repeat_days,
    ROUND(100.0 * SUM(repeat_gap_seconds)
          / (SELECT SUM(gap_seconds) FROM transitions), 1)                 AS pct_of_all_elapsed,
    ROUND(100.0 * SUM(repeat_gap_seconds)
          / (SELECT SUM(repeat_gap_seconds) FROM repeats), 1)              AS pct_of_all_repetition
FROM repeats
GROUP BY activity, transition
ORDER BY repeat_days DESC
LIMIT 4
;

-- "of the 8,559 applications in the offer loop, only 3,143 also run the
--  document loop"
.print
.print === F2. how far the two loops overlap ===
SELECT
    (SELECT COUNT(*) FROM repeats
       WHERE activity = 'W_Call incomplete files' AND transition = 'resume')   AS document_loop,
    (SELECT COUNT(*) FROM repeats
       WHERE activity = 'O_Create Offer' AND transition = 'complete')          AS offer_loop,
    (SELECT COUNT(*) FROM
        (SELECT case_id FROM repeats
           WHERE activity = 'W_Call incomplete files' AND transition = 'resume'
         INTERSECT
         SELECT case_id FROM repeats
           WHERE activity = 'O_Create Offer' AND transition = 'complete'))     AS both
;


-- ===========================================================================
-- G. Finding 3: "accepted 59.3% against a population rate of 54.8%, and
--    cancelled 30.0% against 33.2%" for applications receiving a second offer.
-- ===========================================================================
.print
.print === G. outcome of applications that receive a second offer ===
WITH loop_cases AS (
    SELECT DISTINCT case_id FROM repeats
    WHERE activity = 'O_Create Offer' AND transition = 'complete'
)
SELECT
    cd.outcome,
    COUNT(*) FILTER (WHERE l.case_id IS NOT NULL)                              AS in_offer_loop,
    ROUND(100.0 * COUNT(*) FILTER (WHERE l.case_id IS NOT NULL)
          / SUM(COUNT(*) FILTER (WHERE l.case_id IS NOT NULL)) OVER (), 1)     AS pct_of_loop,
    COUNT(*)                                                                   AS all_applications,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                         AS pct_of_population
FROM case_durations cd
LEFT JOIN loop_cases l USING (case_id)
WHERE cd.outcome IS NOT NULL
GROUP BY cd.outcome
ORDER BY cd.outcome
;


-- ===========================================================================
-- H. Recommendation: "16,727 applications are still open at day 14: 40% of
--    them go on to accept anyway, and 52% go on to lapse."
--    This is the trial's eligible population and its control base rate.
-- ===========================================================================
.print
.print === H. the day-14 pool, and what happens to it ===
WITH sent AS (
    SELECT case_id, MAX(event_time) AS sent_at
    FROM events
    WHERE starts_with(activity, 'O_Sent') AND transition = 'complete'
    GROUP BY case_id
),
resolved AS (
    SELECT case_id,
           MIN(event_time)                  AS resolved_at,
           MIN_BY(activity, event_time)     AS outcome
    FROM events
    WHERE transition = 'complete'
      AND activity IN ('A_Pending', 'A_Cancelled', 'A_Denied')
    GROUP BY case_id
)
SELECT
    COUNT(*)                                                                AS open_at_day_14,
    COUNT(*) FILTER (WHERE outcome = 'A_Pending')                           AS eventually_accept,
    ROUND(100.0 * COUNT(*) FILTER (WHERE outcome = 'A_Pending') / COUNT(*), 1) AS pct_accept,
    COUNT(*) FILTER (WHERE outcome = 'A_Cancelled')                         AS eventually_lapse,
    ROUND(100.0 * COUNT(*) FILTER (WHERE outcome = 'A_Cancelled') / COUNT(*), 1) AS pct_lapse
FROM sent JOIN resolved USING (case_id)
WHERE (epoch(resolved_at) - epoch(sent_at)) / 86400.0 > 14
;
