-- Question: How do monthly revenue, orders and average order value (AOV) change over time?
-- Approach: Aggregate v_sales by purchase month, build a month calendar so empty months show as
--           0 instead of vanishing, then use LAG() to compare each month with the previous one.
-- Assumptions: Revenue = SUM(price), excluding freight. Canceled/unavailable orders are already
--              excluded by v_sales. AOV = revenue / distinct orders. Months with fewer than
--              {{MIN_SAMPLE_SIZE}} orders are flagged low_sample (the dataset's first and last
--              months are partial), so their growth rates should not be trusted.
WITH monthly AS (
    SELECT purchase_month,
           SUM(price) AS revenue,
           COUNT(DISTINCT order_id) AS orders
    FROM v_sales
    GROUP BY purchase_month
),
calendar AS (
    SELECT g AS purchase_month
    FROM generate_series(
             (SELECT MIN(purchase_month) FROM monthly),
             (SELECT MAX(purchase_month) FROM monthly),
             INTERVAL '1 month') AS g
),
filled AS (
    SELECT c.purchase_month,
           COALESCE(m.revenue, 0) AS revenue,
           COALESCE(m.orders, 0) AS orders
    FROM calendar c
    LEFT JOIN monthly m ON m.purchase_month = c.purchase_month
)
SELECT TO_CHAR(purchase_month, 'YYYY-MM') AS order_month,
       ROUND(revenue, 2) AS revenue,
       orders,
       ROUND(revenue / NULLIF(orders, 0), 2) AS avg_order_value,
       ROUND(100.0 * (revenue - LAG(revenue) OVER w) / NULLIF(LAG(revenue) OVER w, 0), 2) AS revenue_mom_pct,
       ROUND(100.0 * (orders - LAG(orders) OVER w) / NULLIF(LAG(orders) OVER w, 0), 2) AS orders_mom_pct,
       orders < {{MIN_SAMPLE_SIZE}} AS low_sample
FROM filled
WINDOW w AS (ORDER BY purchase_month)
ORDER BY purchase_month;