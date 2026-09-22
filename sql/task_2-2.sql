--Task 2.2 — Window functions (required)
--From the de-duplicated events, for every app_id and every calendar day, return:
--• daily revenue,
--• the running total of revenue since the app launched,
--• the 7-day moving average of daily revenue,
--• the day-over-day change in daily revenue, in percent.

--Explain: days with no events at all are missing from your output. Does that matter for the 7-day moving
--average? If it does, describe (no code needed) how you would fix it.

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
),
analytics AS (
	SELECT 
		app_id, 
		event_time::DATE AS calendar_date,
		CASE 
      		WHEN revenue_usd IS NULL OR TRIM(revenue_usd) IN ('', 'NULL', 'null') THEN NULL
      		ELSE REPLACE(TRIM(revenue_usd), ',', '.')::DECIMAL(10, 2)
    	END AS revenue_usd_clean
	FROM unique_event_orders ueo
),
analytics_daily_revenue AS (
	SELECT 
		app_id,
		calendar_date,
		sum(revenue_usd_clean) AS daily_revenue
	FROM analytics
	GROUP BY app_id, calendar_date
),
app_calendar_grid AS (
	SELECT 
		a.app_id,
		c.calendar_date
	FROM mobile_analytics.apps a
	CROSS JOIN mobile_analytics.calendar c
	WHERE c.calendar_date >= a.launched_on::DATE AND c.calendar_date <= CURRENT_DATE
),
continuous_daily AS (
	SELECT 
		acg.app_id,
		acg.calendar_date,
		COALESCE(adr.daily_revenue, 0.00) AS daily_revenue
	FROM app_calendar_grid acg
	LEFT JOIN analytics_daily_revenue adr ON acg.app_id = adr.app_id AND acg.calendar_date = adr.calendar_date
),
analytics_final AS (
	SELECT 
		app_id,
		calendar_date,
		daily_revenue,
		
		SUM(daily_revenue) OVER (
	      PARTITION BY app_id 
	      ORDER BY calendar_date 
	      RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
	    ) AS running_total_revenue, 
    
		ROUND(
	      AVG(daily_revenue) OVER (
	        PARTITION BY app_id 
	        ORDER BY calendar_date 
	        RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW
	      ), 2
	    ) AS moving_avg_7d_revenue, 
		
		ROUND(
		  COALESCE(
		    (daily_revenue - LAG(daily_revenue, 1) OVER (PARTITION BY app_id ORDER BY calendar_date)) * 100.0 / 
		    NULLIF(LAG(daily_revenue, 1) OVER (PARTITION BY app_id ORDER BY calendar_date), 0), 
		    0.00
		  ), 2
		) AS dod_revenue_change_pct

	FROM continuous_daily 
)
SELECT *
FROM analytics_final
ORDER BY app_id, calendar_date;