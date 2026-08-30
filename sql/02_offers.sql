SET TimeZone = 'Europe/Amsterdam';

CREATE OR REPLACE TABLE offers AS
SELECT
    "EventID" AS "offer_id",
    "case:concept:name" AS case_id,
    "OfferedAmount" AS "offered_amount", 
    "MonthlyCost" AS "monthly_cost", 
    "NumberOfTerms" AS "number_terms", 
    "CreditScore" AS "credit_score",
    "FirstWithdrawalAmount" AS "first_withdr", 
    "Accepted" AS "accepted", 
    "Selected" AS "selected"
FROM raw_events
WHERE "concept:name" = 'O_Create Offer';

SELECT COUNT(*) FROM offers;