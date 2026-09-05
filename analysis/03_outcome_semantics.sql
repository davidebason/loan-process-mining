-- analysis/03_outcome_semantics.sql
--
-- Establishes what the outcome activities mean. Neither the 4TU page nor the
-- BPI Challenge page defines them, so the outcome claims in DATA.md's
-- Definitions section are derived here. Section 5 below also feeds
-- "What the data can and cannot support" -> "A_Cancelled is two mechanisms".
--
-- Reads: events

SET TimeZone = 'Europe/Amsterdam';
.mode markdown
.maxrows 60

.print === 1. is the last A_ activity always a terminal state? ===
-- Establishes that "last A_ activity" and "which terminal state appears"
-- agree for every resolved case, and differ only for the 98 censored ones.
WITH last_a AS (
    SELECT case_id, arg_max(activity, event_time) AS last_a_activity
    FROM events
    WHERE starts_with(activity, 'A_')
    GROUP BY case_id
)
SELECT last_a_activity, COUNT(*) AS cases
FROM last_a GROUP BY 1 ORDER BY cases DESC;


.print
.print === 2. do offer states determine the application outcome? ===
-- Shows the two perfect implications (accepted -> A_Pending, refused ->
-- A_Denied) and the 32 cases that offer states cannot distinguish from the
-- 10,431 cancelled ones.
WITH per_case AS (
    SELECT case_id,
        MAX(CASE WHEN activity = 'A_Pending'   THEN 1 ELSE 0 END) AS a_pending,
        MAX(CASE WHEN activity = 'A_Cancelled' THEN 1 ELSE 0 END) AS a_cancelled,
        MAX(CASE WHEN activity = 'A_Denied'    THEN 1 ELSE 0 END) AS a_denied,
        MAX(CASE WHEN activity = 'O_Accepted'  THEN 1 ELSE 0 END) AS o_accepted,
        MAX(CASE WHEN activity = 'O_Refused'   THEN 1 ELSE 0 END) AS o_refused,
        MAX(CASE WHEN activity = 'O_Cancelled' THEN 1 ELSE 0 END) AS o_cancelled
    FROM events GROUP BY case_id
)
SELECT
    CASE WHEN a_pending = 1 THEN 'A_Pending'
         WHEN a_cancelled = 1 THEN 'A_Cancelled'
         WHEN a_denied = 1 THEN 'A_Denied'
         ELSE '(none)' END AS app_outcome,
    o_accepted, o_refused, o_cancelled,
    COUNT(*) AS cases
FROM per_case
GROUP BY 1, 2, 3, 4
ORDER BY app_outcome, cases DESC;


.print
.print === 3. who performs each terminal event? ===
-- User_1 performs 76% of cancellations and none of the accepts or denials.
SELECT
    activity,
    COUNT(*)                                    AS events,
    COUNT(DISTINCT resource)                    AS distinct_resources,
    COUNT(*) FILTER (WHERE resource = 'User_1') AS by_user_1,
    ROUND(100.0 * COUNT(*) FILTER (WHERE resource = 'User_1') / COUNT(*), 1) AS pct_user_1
FROM events
WHERE activity IN ('A_Pending', 'A_Cancelled', 'A_Denied')
GROUP BY activity
ORDER BY events DESC;


.print
.print === 4. how far did each outcome group get? ===
-- Denied cases get a fraud check 15x more often; cancelled cases mostly never
-- reach the document stage at all.
WITH flags AS (
    SELECT case_id,
        MAX(CASE WHEN activity = 'A_Pending'   THEN 1 ELSE 0 END) AS pending,
        MAX(CASE WHEN activity = 'A_Cancelled' THEN 1 ELSE 0 END) AS cancelled,
        MAX(CASE WHEN activity = 'A_Denied'    THEN 1 ELSE 0 END) AS denied,
        MAX(CASE WHEN activity = 'W_Assess potential fraud' THEN 1 ELSE 0 END) AS fraud,
        MAX(CASE WHEN activity = 'A_Incomplete' THEN 1 ELSE 0 END) AS incomplete
    FROM events GROUP BY case_id
)
SELECT
    CASE WHEN pending = 1 THEN 'A_Pending'
         WHEN cancelled = 1 THEN 'A_Cancelled'
         WHEN denied = 1 THEN 'A_Denied' ELSE '(none)' END AS outcome,
    COUNT(*)                                     AS cases,
    ROUND(100.0 * SUM(fraud) / COUNT(*), 1)      AS pct_fraud_check,
    ROUND(100.0 * SUM(incomplete) / COUNT(*), 1) AS pct_went_incomplete
FROM flags GROUP BY 1 ORDER BY cases DESC;


.print
.print === 5. is User_1 the only mechanical canceller? ===
-- The evidence for is_automated = (resource = 'User_1'): User_1 has a standard
-- deviation two orders of magnitude below every other resource, and a floor
-- that never drops below 30 days.
WITH g AS (
    SELECT c.resource, cg.gap_days
    FROM cancellations c
    JOIN cancellation_gaps cg
      ON cg.case_id = c.case_id AND cg.gap_from = 'offer_sent'
)
SELECT
    resource,
    COUNT(*)                   AS n_cancellations,
    ROUND(MEDIAN(gap_days), 2) AS median_days,
    ROUND(STDDEV(gap_days), 3) AS stddev_days,
    ROUND(MIN(gap_days), 2)    AS min_days,
    ROUND(MAX(gap_days), 2)    AS max_days
FROM g
GROUP BY resource
HAVING COUNT(*) >= 20
ORDER BY n_cancellations DESC
LIMIT 12;
