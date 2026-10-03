-- Question: What share of deliveries are late, by category and by state, and which categories
--           drive both late deliveries AND bad reviews (1-2 stars)?
-- Approach: Work at order level. An order is late if delivered after the estimated date
--           (is_late in v_orders_clean). Undelivered orders have is_late = NULL and are excluded.
--           Orders with several categories count once per category.
-- Assumptions: Groups with fewer than {{MIN_SAMPLE_SIZE}} orders are flagged low_sample and not
--              ranked. Bad review = score 1 or 2. Only orders with a review enter the drivers table.
--              Driver ranking uses categories with enough reviewed orders; shares are among those.

-- result: by_category
WITH order_category AS (
    SELECT DISTINCT order_id, category, is_late
    FROM v_sales
    WHERE is_late IS NOT NULL
),
agg AS (
    SELECT category,
           COUNT(*) AS delivered_orders,
           SUM(CASE WHEN is_late THEN 1 ELSE 0 END) AS late_orders
    FROM order_category
    GROUP BY category
),
rates AS (
    SELECT category, delivered_orders, late_orders,
           ROUND(100.0 * late_orders / NULLIF(delivered_orders, 0), 2) AS late_rate_pct,
           delivered_orders < {{MIN_SAMPLE_SIZE}} AS low_sample
    FROM agg
)
SELECT category, delivered_orders, late_orders, late_rate_pct, low_sample,
       CASE WHEN NOT low_sample
            THEN RANK() OVER (PARTITION BY low_sample ORDER BY late_rate_pct DESC)
       END AS late_rate_rank
FROM rates
ORDER BY low_sample, late_rate_rank, late_rate_pct DESC;

-- result: by_state
WITH order_state AS (
    SELECT DISTINCT order_id, customer_state, is_late
    FROM v_sales
    WHERE is_late IS NOT NULL
),
agg AS (
    SELECT customer_state,
           COUNT(*) AS delivered_orders,
           SUM(CASE WHEN is_late THEN 1 ELSE 0 END) AS late_orders
    FROM order_state
    GROUP BY customer_state
),
rates AS (
    SELECT customer_state, delivered_orders, late_orders,
           ROUND(100.0 * late_orders / NULLIF(delivered_orders, 0), 2) AS late_rate_pct,
           delivered_orders < {{MIN_SAMPLE_SIZE}} AS low_sample
    FROM agg
)
SELECT customer_state, delivered_orders, late_orders, late_rate_pct, low_sample,
       CASE WHEN NOT low_sample
            THEN RANK() OVER (PARTITION BY low_sample ORDER BY late_rate_pct DESC)
       END AS late_rate_rank
FROM rates
ORDER BY low_sample, late_rate_rank, late_rate_pct DESC;

-- result: category_drivers
WITH order_category AS (
    SELECT DISTINCT order_id, category, is_late
    FROM v_sales
    WHERE is_late IS NOT NULL
),
agg AS (
    SELECT oc.category,
           COUNT(*) AS reviewed_orders,
           SUM(CASE WHEN oc.is_late THEN 1 ELSE 0 END) AS late_orders,
           SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END) AS bad_review_orders,
           SUM(CASE WHEN oc.is_late AND r.review_score <= 2 THEN 1 ELSE 0 END) AS late_and_bad_orders,
           SUM(CASE WHEN NOT oc.is_late AND r.review_score <= 2 THEN 1 ELSE 0 END) AS ontime_and_bad_orders
    FROM order_category oc
    JOIN v_reviews_clean r ON r.order_id = oc.order_id
    GROUP BY oc.category
    HAVING COUNT(*) >= {{MIN_SAMPLE_SIZE}}
)
SELECT category,
       reviewed_orders,
       ROUND(100.0 * late_orders / NULLIF(reviewed_orders, 0), 2) AS late_rate_pct,
       ROUND(100.0 * bad_review_orders / NULLIF(reviewed_orders, 0), 2) AS bad_review_rate_pct,
       ROUND(100.0 * late_and_bad_orders / NULLIF(late_orders, 0), 2) AS bad_rate_when_late_pct,
       ROUND(100.0 * ontime_and_bad_orders / NULLIF(reviewed_orders - late_orders, 0), 2) AS bad_rate_when_ontime_pct,
       late_and_bad_orders,
       ROUND(100.0 * late_and_bad_orders / NULLIF(SUM(late_and_bad_orders) OVER (), 0), 2) AS share_of_all_late_and_bad_pct,
       RANK() OVER (ORDER BY late_and_bad_orders DESC) AS rank_by_late_and_bad
FROM agg
ORDER BY rank_by_late_and_bad
LIMIT 15;