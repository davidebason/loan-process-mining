-- analysis/02_dt_days_timeout.sql
--
-- Question: what if automatic cancellation after 14 days?
--
-- Reads: cancellation_gaps, cancellations (built by sql/05)
-- Known: we are going to assume no change in the clients behaviour and see 
--        this change of cut-off changes the result.

SET TimeZone = 'Europe/Amsterdam';
SET VARIABLE dt = 14;
.mode markdown
.maxrows 100

-- 1. Every case, with its actual and counterfactual duration.
CREATE OR REPLACE TEMP TABLE counterfactual AS
SELECT
    cd.case_id,
    cd.outcome,
    cd.duration_hours,
    CASE WHEN c.offer_expired IS TRUE THEN cd.duration_hours - (30-getvariable('dt'))*24 ELSE cd.duration_hours END AS counterfactual_hours
FROM case_durations cd LEFT JOIN cancellations c ON cd.case_id = c.case_id
;

-- 2. Before and after, over all 31,509 cases.
SELECT
    COUNT(*) AS n_cases,
    MEDIAN(duration_hours) / 24        AS median_days_now,
    MEDIAN(counterfactual_hours) / 24  AS median_days_then,
    AVG(duration_hours) / 24          AS mean_days_now,
    AVG(counterfactual_hours) / 24    AS mean_days_then,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY counterfactual_hours) / 24 AS p90_days_then,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY duration_hours) / 24 AS p90_days_now
FROM counterfactual;

-- 3. Amount of offer lost if the cut-off was dt days instead of 30.
CREATE OR REPLACE TEMP TABLE cost_of_shorter_expiry AS

WITH accepted AS (
    -- one row per successful case: which offer was accepted, and when
    SELECT
        case_id,
        MAX(CASE WHEN activity = 'O_Accepted' THEN offer_id END)   AS offer_id,
        MAX(CASE WHEN activity = 'O_Accepted' THEN event_time END) AS accepted_at
    FROM events
    GROUP BY case_id
    HAVING MAX(CASE WHEN activity = 'O_Accepted' THEN offer_id END) IS NOT NULL
),

sent AS (
    -- one row per offer: when it was last sent
    SELECT
        offer_id,
        MAX(event_time) AS sent_at
    FROM events
    WHERE starts_with(activity, 'O_Sent')
      AND offer_id IS NOT NULL
    GROUP BY offer_id
),

joined AS (
    -- one row per successful case, with its wait and its value
    SELECT
        a.case_id,
        o.offered_amount,
        -- Gross interest: total repayments minus the sum lent. Principal is
        -- returned to the bank, so the economic loss of a foregone loan is the
        -- interest never earned, not the principal never lent. Gross, because
        -- cost of funds, defaults and servicing are not in this data.
        o.monthly_cost * o.number_terms - o.offered_amount AS gross_interest,
        (epoch(a.accepted_at) - epoch(s.sent_at)) / 86400.0 AS gap_days
    FROM accepted a
    JOIN sent   s ON s.offer_id = a.offer_id
    JOIN offers o ON o.offer_id = a.offer_id
)

SELECT
    COUNT(*)                                                     AS n_accepted,
    COUNT(*) FILTER (WHERE gap_days > getvariable('dt'))         AS n_lost,
    ROUND(100.0 * COUNT(*) FILTER (WHERE gap_days > getvariable('dt'))
                / COUNT(*), 2)                                   AS pct_lost,
    ROUND(SUM(offered_amount), 0)                                AS principal_total,
    ROUND(SUM(offered_amount)
          FILTER (WHERE gap_days > getvariable('dt')), 0)        AS principal_lost,
    ROUND(100.0 * SUM(offered_amount)
                  FILTER (WHERE gap_days > getvariable('dt'))
                / SUM(offered_amount), 2)                        AS pct_principal_lost,
    ROUND(SUM(gross_interest), 0)                                AS interest_total,
    ROUND(SUM(gross_interest)
          FILTER (WHERE gap_days > getvariable('dt')), 0)        AS interest_lost,
    ROUND(100.0 * SUM(gross_interest)
                  FILTER (WHERE gap_days > getvariable('dt'))
                / SUM(gross_interest), 2)                        AS pct_interest_lost
FROM joined
;

SELECT * FROM cost_of_shorter_expiry;