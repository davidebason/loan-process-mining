-- analysis/04_offer_size.sql
--
-- Hypothesis: larger loans take longer to consider, so a shorter offer expiry
-- would destroy disproportionately large loans and the cost of that change
-- would be understated by a headcount alone.
--
-- Tested and rejected. See DATA.md, "Offer size barely affects how long a
-- customer takes to accept".
--
-- Reads: events, offers

SET TimeZone = 'Europe/Amsterdam';
.mode markdown

-- one row per successful case: the wait before acceptance, and the amount
CREATE OR REPLACE TEMP TABLE accepted_wait AS
WITH accepted AS (
    SELECT
        case_id,
        MAX(CASE WHEN activity = 'O_Accepted' THEN offer_id END)   AS offer_id,
        MAX(CASE WHEN activity = 'O_Accepted' THEN event_time END) AS accepted_at
    FROM events
    GROUP BY case_id
    HAVING MAX(CASE WHEN activity = 'O_Accepted' THEN offer_id END) IS NOT NULL
),
sent AS (
    SELECT offer_id, MAX(event_time) AS sent_at
    FROM events
    WHERE starts_with(activity, 'O_Sent') AND offer_id IS NOT NULL
    GROUP BY offer_id
)
SELECT
    a.case_id,
    o.offered_amount,
    (epoch(a.accepted_at) - epoch(s.sent_at)) / 86400.0 AS gap_days
FROM accepted a
JOIN sent   s ON s.offer_id = a.offer_id
JOIN offers o ON o.offer_id = a.offer_id;


.print === 1. is the accepted offer always the last one sent? ===
-- If it were, MAX(sent time) per case would be a valid shortcut. It is not:
-- 2,541 of 17,228 successes accepted an earlier offer, so the join above must
-- key on offer_id.
WITH per_case AS (
    SELECT
        case_id,
        MAX(CASE WHEN activity = 'O_Accepted' THEN offer_id END)         AS accepted_offer,
        MAX(CASE WHEN starts_with(activity, 'O_Sent') THEN offer_id END) AS last_sent_offer,
        COUNT(*) FILTER (WHERE starts_with(activity, 'O_Sent'))          AS n_sent
    FROM events GROUP BY case_id
)
SELECT
    COUNT(*) FILTER (WHERE accepted_offer IS NOT NULL)                AS cases_with_accept,
    COUNT(*) FILTER (WHERE accepted_offer IS NOT NULL AND n_sent = 1) AS only_one_offer_sent,
    COUNT(*) FILTER (WHERE accepted_offer = last_sent_offer)          AS accepted_is_last_sent,
    COUNT(*) FILTER (WHERE accepted_offer IS NOT NULL
                       AND accepted_offer <> last_sent_offer)         AS accepted_is_not_last
FROM per_case;


.print
.print === 2. acceptance delay by offer size ===
WITH b AS (
    SELECT *, NTILE(5) OVER (ORDER BY offered_amount) AS quintile
    FROM accepted_wait
)
SELECT
    quintile,
    MIN(offered_amount)        AS min_amount,
    MAX(offered_amount)        AS max_amount,
    COUNT(*)                   AS n,
    ROUND(MEDIAN(gap_days), 2) AS median_gap_days,
    ROUND(AVG(gap_days), 2)    AS mean_gap_days
FROM b
GROUP BY quintile
ORDER BY quintile;


.print
.print === 3. correlation between amount and delay ===
-- r = 0.086, so r-squared under 0.008: size explains under 1% of the variance.
SELECT
    ROUND(CORR(offered_amount, gap_days), 4)     AS pearson_r,
    ROUND(CORR(LN(offered_amount), gap_days), 4) AS pearson_r_log_amount
FROM accepted_wait
WHERE offered_amount > 0;


.print
.print === 4. the decisive test: does principal lost outrun conversions lost? ===
-- If size mattered, pct_principal_lost would run well above pct_lost at every
-- threshold. It does not - the gap never exceeds 3 points.
CREATE OR REPLACE TEMP TABLE thresholds AS SELECT unnest([7, 14, 21, 25, 30]) AS dt;

SELECT
    t.dt AS expiry_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE w.gap_days > t.dt) / COUNT(*), 1) AS pct_conversions_lost,
    ROUND(100.0 * SUM(w.offered_amount) FILTER (WHERE w.gap_days > t.dt)
                / SUM(w.offered_amount), 1)                                AS pct_principal_lost
FROM accepted_wait w CROSS JOIN thresholds t
GROUP BY t.dt
ORDER BY t.dt;
