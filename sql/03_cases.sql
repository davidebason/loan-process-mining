-- One row per loan application.
--
-- Lifts the four case-level attributes out of the event stream. DATA.md records
-- that all three non-key attributes were verified constant within every case
-- (max 1 distinct value per case), which is what makes DISTINCT safe here.
--
-- DISTINCT also self-checks that assumption: if any attribute ever varied within
-- a case, that case would produce more than one row and the count below would
-- exceed 31,509.

SET TimeZone = 'Europe/Amsterdam';

CREATE OR REPLACE TABLE cases AS
SELECT DISTINCT
    "case:concept:name"    AS case_id,
    "case:RequestedAmount" AS requested_amount,
    "case:LoanGoal"        AS loan_goal,
    "case:ApplicationType" AS application_type
FROM raw_events;

-- expect 31,509
SELECT COUNT(*) AS n_cases FROM cases;

-- and the key must be unique: this must return 0 rows
SELECT case_id, COUNT(*) AS n
FROM cases
GROUP BY case_id
HAVING COUNT(*) > 1;
