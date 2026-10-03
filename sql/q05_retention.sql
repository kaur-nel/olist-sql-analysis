-- Question: What share of customers buy again, and how well does each first-purchase-month
--           cohort retain over time?
-- Approach: Identify people by customer_unique_id. Cohort = month of a customer's first order.
--           For each cohort and each month offset, count customers who ordered again, divided by
--           cohort size. A grid of cohort x offset keeps zero-activity months visible.
-- Assumptions: Based on revenue orders only (canceled/unavailable excluded). Offsets are shown only
--              up to the last month in the data (later months are unobserved, not zero).
--              Cohorts smaller than {{MIN_SAMPLE_SIZE}} customers are flagged low_sample.

-- result: repeat_rate
WITH customer_orders AS (
    SELECT customer_unique_id, COUNT(DISTINCT order_id) AS orders
    FROM v_sales
    GROUP BY customer_unique_id
)
SELECT COUNT(*) AS customers,
       SUM(CASE WHEN orders >= 2 THEN 1 ELSE 0 END) AS repeat_customers,
       ROUND(100.0 * SUM(CASE WHEN orders >= 2 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS repeat_rate_pct,
       ROUND(AVG(orders), 3) AS avg_orders_per_customer,
       MAX(orders) AS max_orders
FROM customer_orders;

-- result: cohort_retention
WITH params AS (
    SELECT 12 AS max_months     -- show up to 12 months after the first purchase
),
customer_orders AS (
    SELECT DISTINCT customer_unique_id, order_id, purchase_month
    FROM v_sales
),
first_purchase AS (
    SELECT customer_unique_id, MIN(purchase_month) AS cohort_month
    FROM customer_orders
    GROUP BY customer_unique_id
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM first_purchase
    GROUP BY cohort_month
),
activity AS (
    SELECT f.cohort_month,
           CAST(EXTRACT(YEAR FROM AGE(c.purchase_month, f.cohort_month)) * 12
              + EXTRACT(MONTH FROM AGE(c.purchase_month, f.cohort_month)) AS INTEGER) AS months_since_first,
           c.customer_unique_id
    FROM customer_orders c
    JOIN first_purchase f ON f.customer_unique_id = c.customer_unique_id
),
retained AS (
    SELECT cohort_month, months_since_first,
           COUNT(DISTINCT customer_unique_id) AS active_customers
    FROM activity
    GROUP BY cohort_month, months_since_first
),
last_data_month AS (
    SELECT MAX(purchase_month) AS last_month FROM customer_orders
),
grid AS (
    SELECT s.cohort_month, s.cohort_size, k AS months_since_first
    FROM cohort_sizes s
    CROSS JOIN generate_series(0, (SELECT max_months FROM params)) AS k
    WHERE s.cohort_month + k * INTERVAL '1 month' <= (SELECT last_month FROM last_data_month)
)
SELECT TO_CHAR(g.cohort_month, 'YYYY-MM') AS cohort_month,
       g.months_since_first,
       g.cohort_size,
       COALESCE(r.active_customers, 0) AS active_customers,
       ROUND(100.0 * COALESCE(r.active_customers, 0) / NULLIF(g.cohort_size, 0), 2) AS retention_pct,
       g.cohort_size < {{MIN_SAMPLE_SIZE}} AS low_sample
FROM grid g
LEFT JOIN retained r
       ON r.cohort_month = g.cohort_month AND r.months_since_first = g.months_since_first
ORDER BY g.cohort_month, g.months_since_first;