-- 05_cancellation_gaps.sql
--
-- Is A_Cancelled produced by an automated inactivity timeout?
--
-- Produces: cancellation_gaps, grain is one row per (cancelled case, anchor).
-- Reads:    events
-- Why:      76% of A_Cancelled events are performed by User_1, and cancelled
--           cases run 2.1x longer than successful ones (31.6 vs 14.8 days
--           median). If a fixed timeout exists, the gap from the last preceding
--           event will cluster on one value.


SET TimeZone = 'Europe/Amsterdam';


-- 1. The population: one row per cancelled case.
--
--    offer_expired marks the cases the offer-expiry counterfactual applies to:
--    cancelled by the automation account AND having had an offer sent. The 21
--    automated cancellations with no offer sent had no expiry clock to shorten.
CREATE OR REPLACE TABLE cancellations AS
WITH base AS (
    SELECT
        e.case_id,
        e.event_time            AS cancelled_at,
        e.resource,
        e.resource = 'User_1'   AS is_automated,
        EXISTS (
            SELECT 1 FROM events o
            WHERE o.case_id = e.case_id
              AND starts_with(o.activity, 'O_Sent')
        )                       AS offer_sent
    FROM events e
    WHERE e.activity = 'A_Cancelled'
)
SELECT
    case_id,
    cancelled_at,
    resource,
    is_automated,
    offer_sent,
    is_automated AND offer_sent AS offer_expired
FROM base;


-- 2. Sanity: this must be 10,431.
SELECT COUNT(*) AS n_cancelled FROM cancellations;


-- 3. Gaps from several anchors, stacked into one table.
CREATE OR REPLACE TABLE cancellation_gaps AS
WITH joined_with_prev AS (
    SELECT
        c.case_id,
        c.cancelled_at,
        e.activity,
        e.event_time,
        LAG(e.event_time) OVER (
            PARTITION BY c.case_id
            ORDER BY e.event_time
        ) AS prev_time
    FROM cancellations c JOIN events e ON c.case_id = e.case_id
)
    -- anchor A: from the start of the case
    SELECT 
        c.case_id, 
        'case_start' AS gap_from, 
        (epoch(cancelled_at) - epoch(MIN(event_time))) / 86400.0 AS gap_days
    FROM cancellations c JOIN events e ON c.case_id = e.case_id
    GROUP BY c.case_id, cancelled_at
UNION ALL
    -- anchor B: from the event immediately before the cancellation
    -- (this one needs LAG, see note)
    SELECT 
        case_id, 
        'previous_event' AS gap_from, 
        (epoch(cancelled_at) - epoch(prev_time)) / 86400.0 AS gap_days
        FROM joined_with_prev
    WHERE activity = 'A_Cancelled'
UNION ALL
    -- anchor C: from the last offer sent, where the case had one
    SELECT 
        c.case_id, 
        'offer_sent' AS gap_from,
        (epoch(cancelled_at) - epoch(MAX(e.event_time))) / 86400.0 AS gap_days
    FROM cancellations c JOIN events e ON c.case_id = e.case_id
    WHERE starts_with(e.activity, 'O_Sent')
    GROUP BY c.case_id, cancelled_at
;