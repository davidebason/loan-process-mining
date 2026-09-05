-- 06_transitions.sql
--
-- Q2: between which two activities does the most waiting time accumulate?
--
-- Produces: transitions, grain is one row per consecutive pair of events
--           within a case. Every event has a predecessor except its case's
--           first, so 1,202,267 - 31,509 = 1,170,758 pairs before filtering.
-- Reads:    events
--
-- Decisions (DATA.md, decision 6):
--   * an event type is the pair (activity, transition), not the activity alone
--   * gaps under one second are automatic bookkeeping; flagged, not dropped,
--     so that totals still reconcile to case duration
--   * waiting and handling are told apart by the PRECEDING transition:
--         start / resume  -> someone is holding the task -> handling
--         anything else   -> nothing is held             -> waiting
--     (approximate: a case can hold several work items at once)

SET TimeZone = 'Europe/Amsterdam';


-- 1. Every consecutive pair of events within a case.
CREATE OR REPLACE TABLE transitions AS
WITH paired AS (
    SELECT
        case_id,
        activity AS to_activity,
        transition AS to_transition,
        event_time AS to_time,
        LAG(activity) OVER (PARTITION BY case_id ORDER BY event_time) AS from_activity,
        LAG(transition) OVER (PARTITION BY case_id ORDER BY event_time) AS from_transition,
        LAG(event_time) OVER (PARTITION BY case_id ORDER BY event_time) AS from_time
    FROM events
)
SELECT
    case_id,
    from_activity,
    from_transition,
    to_activity,
    to_transition,
    epoch(to_time) - epoch(from_time) AS gap_seconds,
    CASE WHEN from_transition IN ('start', 'resume') THEN 'handling' ELSE 'waiting' END AS gap_kind,
    from_activity = to_activity AS same_activity,
    epoch(to_time) - epoch(from_time) < 1.0 AS bookkeeping
FROM paired
WHERE from_activity IS NOT NULL
;

-- 2. Sanity (should give 1170758).
SELECT COUNT(*) AS n_pairs FROM transitions;