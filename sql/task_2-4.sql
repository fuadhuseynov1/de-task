--Task 2.4 — Incremental load (required)
--Write the statement that loads new and corrected events from a staging table into the clean table
--incrementally. It must be safe to re-run: running it twice over an overlapping period must not create
--duplicates and must not lose corrections.

--Explain: which time column do you filter on to pick up new rows — event_time or ingested_at — and
--why? What is the smallest window you can reload without losing late events, and what does that choice
--cost you?

-- Create new events clean table
CREATE TABLE IF NOT EXISTS mobile_analytics.events_raw_clean (
	event_id TEXT PRIMARY KEY,
	user_id TEXT NOT NULL,
	app_id TEXT NOT NULL,
	event_name TEXT NOT NULL,
	event_time TIMESTAMP NOT NULL,
	ingested_at TIMESTAMP NOT NULL,
	country TEXT,
	media_source TEXT,
	campaign TEXT,
	revenue_usd DECIMAL(10, 2)
);


WITH event_orders AS (
	SELECT 
		event_id, 
		user_id, 
		app_id, 
		event_name, 
		event_time, 
		ingested_at, 
		UPPER(NULLIF(NULLIF(TRIM(country), ''), '--')) AS country, 
		media_source, 
		campaign, 
		CASE 
      		WHEN revenue_usd IS NULL OR TRIM(revenue_usd) IN ('', 'NULL', 'null') THEN NULL
      		ELSE REPLACE(TRIM(revenue_usd), ',', '.')::DECIMAL(10, 2)
    	END AS revenue_usd,
		row_number() OVER (
			PARTITION BY event_id 
			ORDER BY ingested_at DESC, event_time DESC
		) AS order_event_ingested
	FROM mobile_analytics.events_raw
	WHERE is_test = 'false' AND 
		  ingested_at > COALESCE(
        	(SELECT 
        		MAX(ingested_at) 
        		FROM mobile_analytics.events_raw_clean
        	), '1970-01-01'::timestamp) - INTERVAL '2 days' -- the frist run, we will get null, so we need to have an alternative to compare with (1970-01-01)
), -- Read only rows newer than (newest ingested_at already loaded) minus 2 days.
  -- The 2 extra days re-read old rows on purpose, to catch rows that arrived late.
  -- Rows we already loaded are read again, but they do not change anything.
unique_event_orders AS (
	SELECT 
		event_id, 
		user_id, 
		app_id, 
		event_name, 
		event_time, 
		ingested_at, 
		country, 
		media_source, 
		campaign, 
		revenue_usd
	FROM event_orders
	WHERE order_event_ingested = 1
)
INSERT INTO mobile_analytics.events_raw_clean AS erc (event_id, user_id, app_id, event_name, event_time, ingested_at, country, media_source, campaign, revenue_usd)
SELECT 
	event_id, 
	user_id, 
	app_id, 
	event_name, 
	event_time, 
	ingested_at, 
	country, 
	media_source, 
	campaign, 
	revenue_usd
FROM unique_event_orders
ON CONFLICT (event_id)
DO UPDATE 
SET
	user_id = EXCLUDED.user_id,
	app_id = EXCLUDED.app_id,
	event_name = EXCLUDED.event_name,
	event_time = EXCLUDED.event_time,
	ingested_at = EXCLUDED.ingested_at,
	country = EXCLUDED.country,
	media_source = EXCLUDED.media_source,
	campaign = EXCLUDED.campaign,
	revenue_usd = EXCLUDED.revenue_usd
WHERE EXCLUDED.ingested_at > erc.ingested_at; -- update the saved row only if the incoming row has a newer ingested_at than the saved one


SELECT * FROM mobile_analytics.events_raw_clean erc;



-- Checks (a bit messy)
-- Raw data 
SELECT count(*) FROM mobile_analytics.events_raw er; -- 251 --> AFTER 2nd batch become 261
SELECT count(DISTINCT event_id) FROM mobile_analytics.events_raw er WHERE is_test = 'false'; -- 209, 187 --> AFTER 2nd batch become 213/190


-- Cleaned data
-- First run events_raw data: 187 inserted
-- Second/Third/Fourth run the same events_raw data: 0 inserted

SELECT count(*) FROM mobile_analytics.events_raw_clean erc; -- 187 --> become 190

SELECT count(DISTINCT event_id) FROM mobile_analytics.events_raw_clean erc; -- 187 --> become 190

SELECT SUM(revenue_usd) FROM mobile_analytics.events_raw_clean erc; --242.66 --> become 250.15
SELECT max(ingested_at) FROM mobile_analytics.events_raw_clean erc; -- 2026-09-08 12:02:48.000 --> become 2026-09-11 14:10:31.000

-- before the 2nd run save the first batch clean table
CREATE TABLE mobile_analytics.clean_snapshot AS SELECT * FROM mobile_analytics.events_raw_clean;


-- Second batch run
-- 7 values (updated/inserted)
-- doesn't produce duplicates when we re-run
