SET TimeZone = 'Europe/Amsterdam';

CREATE OR REPLACE TABLE events AS
SELECT
    "EventID" AS "event_id",
    "OfferID" AS "offer_id",
    "case:concept:name" AS "case_id",
    "concept:name" AS "activity",
    "time:timestamp" AS "event_time",
    "lifecycle:transition" AS "transition",
    "EventOrigin" AS "event_origin",
    "org:resource" AS "resource"
FROM raw_events;

SELECT COUNT(*) FROM events;