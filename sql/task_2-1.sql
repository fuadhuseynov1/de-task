--2.1 Produce a clean event table with exactly one row per event_id. When the same event_id arrives more than once, 
--keep the latest delivery by ingested_at, so that a corrected revenue value wins over the original one. Exclude test traffic.

--Explain: what happens to your query if two deliveries of the same event share the exact same
--ingested_at? Show how you make the result deterministic.


-- 1 row per event_id
-- if we have duplicate event_id, keep the latest one by ingested_at
-- exclude test traffic

WITH event_orders AS (
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
		revenue_usd, 
		is_test, 
		row_number() OVER (
			PARTITION BY event_id 
			ORDER BY ingested_at, event_time DESC
		) AS order_event_ingested
	FROM mobile_analytics.events_raw
	WHERE is_test = 'false'
),
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
		revenue_usd, 
		is_test
	FROM event_orders
	WHERE order_event_ingested = 1
)
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
	revenue_usd, 
	is_test
FROM unique_event_orders;