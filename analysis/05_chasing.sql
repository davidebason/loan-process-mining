-- analysis/05_chasing.sql
--
-- How the bank chases an unanswered offer, and what the log can and cannot
-- establish about whether chasing works.
--
-- Reads: events

SET TimeZone = 'Europe/Amsterdam';
.mode markdown
.maxrows 60

.print === 1. can a call be attached to a specific offer? ===
-- No. Only offer-state events carry offer_id; work items are linked to the
-- case and nothing finer.
SELECT
    CASE WHEN starts_with(activity, 'W_') THEN 'W_ (work item)'
         WHEN starts_with(activity, 'O_') THEN 'O_ (offer)'
         ELSE 'A_ (application)' END AS family,
    COUNT(*)        AS events,
    COUNT(offer_id) AS with_offer_id
FROM events
GROUP BY 1 ORDER BY events DESC;


.print
.print === 2. the call state machine ===
-- schedule and start are simultaneous; start -> suspend is the call itself;
-- suspend -> resume is the wait before the second attempt. Only 342 of 60,615
-- attempts ever reach 'complete'.
WITH seq AS (
    SELECT
        case_id, transition, event_time,
        LEAD(transition)  OVER (PARTITION BY case_id, activity ORDER BY event_time) AS nxt,
        LEAD(event_time)  OVER (PARTITION BY case_id, activity ORDER BY event_time) AS nxt_time
    FROM events
    WHERE activity = 'W_Call after offers'
)
SELECT
    transition || ' -> ' || COALESCE(nxt, '(none)')  AS path,
    COUNT(*)                                        AS n,
    ROUND(MEDIAN(epoch(nxt_time) - epoch(event_time)), 1)  AS median_seconds
FROM seq
GROUP BY 1
ORDER BY n DESC
LIMIT 15;


.print
.print === 3. how many attempts per case, and how far apart? ===
-- Two attempts is the norm (71.7%), a median 3.99 days apart. Attempts three
-- and beyond are same-session redials: median gap 0.01 days.
CREATE OR REPLACE TEMP TABLE attempts AS
SELECT
    case_id,
    event_time,
    ROW_NUMBER() OVER (PARTITION BY case_id ORDER BY event_time) AS attempt_no,
    LAG(event_time) OVER (PARTITION BY case_id ORDER BY event_time) AS prev_attempt
FROM events
WHERE activity = 'W_Call after offers'
  AND transition IN ('start', 'resume');

WITH per_case AS (SELECT case_id, COUNT(*) AS n FROM attempts GROUP BY case_id)
SELECT n AS attempts_in_case, COUNT(*) AS cases
FROM per_case GROUP BY n ORDER BY n LIMIT 10;

SELECT
    attempt_no,
    COUNT(*)                                                     AS n,
    ROUND(MEDIAN((epoch(event_time) - epoch(prev_attempt)) / 86400.0), 2) AS median_days,
    ROUND(MAX((epoch(event_time) - epoch(prev_attempt)) / 86400.0), 2)    AS max_days
FROM attempts
WHERE prev_attempt IS NOT NULL
GROUP BY attempt_no
ORDER BY attempt_no
LIMIT 6;


.print
.print === 4. what other channels exist? ===
-- Only phone calls. No reminder, email or SMS activity anywhere in the log.
SELECT
    activity,
    COUNT(*) FILTER (WHERE transition IN ('start', 'resume')) AS attempts,
    COUNT(DISTINCT case_id)                                   AS cases_touched
FROM events
WHERE starts_with(activity, 'W_')
GROUP BY activity
ORDER BY attempts DESC;

SELECT activity, COUNT(*) AS n, COUNT(DISTINCT case_id) AS cases
FROM events
WHERE starts_with(activity, 'O_Sent') OR activity = 'O_Returned'
GROUP BY activity ORDER BY n DESC;


.print
.print === 5. does calling more help? (confounded - see DATA.md) ===
-- More calls, lower acceptance. The causation runs backwards: a customer
-- drifting away is the reason for the second call. No treatment of this
-- observational log removes that confounding.
WITH att AS (
    SELECT case_id,
           COUNT(*) FILTER (WHERE activity = 'W_Call after offers'
                              AND transition IN ('start', 'resume')) AS n_attempts,
           MAX(CASE WHEN activity = 'O_Accepted' THEN 1 ELSE 0 END)  AS accepted
    FROM events GROUP BY case_id
)
SELECT
    LEAST(n_attempts, 4)                       AS attempts_capped,
    COUNT(*)                                   AS cases,
    SUM(accepted)                              AS accepted,
    ROUND(100.0 * SUM(accepted) / COUNT(*), 1) AS pct_accepted
FROM att GROUP BY 1 ORDER BY attempts_capped;


.print
.print === 6. does 'complete' mean the customer answered? inconclusive ===
-- 0.56% of attempts complete, and those cases accept slightly LESS often.
-- Too rare (1.1% of cases) to support a finding either way.
WITH flags AS (
    SELECT case_id,
        MAX(CASE WHEN activity = 'W_Call after offers' AND transition = 'complete'
                 THEN 1 ELSE 0 END)                             AS had_completed_call,
        MAX(CASE WHEN activity = 'O_Accepted' THEN 1 ELSE 0 END) AS accepted
    FROM events GROUP BY case_id
)
SELECT
    had_completed_call,
    COUNT(*)                                   AS cases,
    SUM(accepted)                              AS accepted,
    ROUND(100.0 * SUM(accepted) / COUNT(*), 1) AS pct_accepted
FROM flags GROUP BY 1 ORDER BY had_completed_call;
