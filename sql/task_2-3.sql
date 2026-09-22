--Task 2.3 — Joining costs (required)
--Build one daily table that puts revenue and cost side by side per app_id, media_source and
--campaign, and adds ROAS (revenue / cost).

--Explain: there are campaigns with cost and no revenue, and campaigns with revenue and no cost. 
--Which join did you choose and what does each of those two cases mean for the business? What did you do about division by zero?

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
			ORDER BY ingested_at DESC, event_time DESC
		) AS order_event_ingested
	FROM mobile_analytics.events_raw
	WHERE is_test = 'false'
),
unique_event_orders AS (
	SELECT 
		app_id,
		media_source, 
		campaign, 
		CASE
            WHEN revenue_usd IS NULL OR TRIM(revenue_usd) IN ('', 'NULL', 'null') THEN NULL
            ELSE REPLACE(TRIM(revenue_usd), ',', '.')::NUMERIC(10, 2)
        END AS revenue_usd
	FROM event_orders
	WHERE order_event_ingested = 1
),
revenue_by_campaign AS (
    SELECT
        app_id,
        media_source,
        campaign,
        SUM(revenue_usd) AS total_revenue_usd
    FROM unique_event_orders
    GROUP BY app_id, media_source, campaign
),
cost_by_campaign AS (
    SELECT
        app_id,
        media_source,
        campaign,
        SUM(cost_usd) AS total_cost_usd
    FROM mobile_analytics.campaign_costs
    GROUP BY app_id, media_source, campaign
)
SELECT
	COALESCE(cc.app_id, rv.app_id) AS app_id,
    COALESCE(cc.media_source, rv.media_source) AS media_source,
    COALESCE(cc.campaign, rv.campaign) AS campaign,
    cc.total_cost_usd,
    COALESCE(rv.total_revenue_usd, 0) AS total_revenue_usd,
    ROUND(COALESCE(rv.total_revenue_usd, 0) / NULLIF(cc.total_cost_usd, 0), 2) AS roas
FROM cost_by_campaign cc
FULL JOIN revenue_by_campaign rv ON cc.app_id = rv.app_id AND cc.media_source = rv.media_source AND cc.campaign = rv.campaign
ORDER BY 1, 2, 3;