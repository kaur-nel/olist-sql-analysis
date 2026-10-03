-- Question: How heavy is freight relative to price, by category and by region?
-- Approach: Freight pct = total freight / total price (a weighted ratio), grouped by category and by
--           the customer's Brazilian region (mapped from state codes).
-- Assumptions: Weighted ratio (sum over sum), not the average of per-item ratios, so cheap items do not
--              distort it. Region is the customer's destination. Categories with fewer than
--              {{MIN_SAMPLE_SIZE}} orders are flagged and not ranked.

-- result: by_category
WITH agg AS (
    SELECT category,
           COUNT(DISTINCT order_id) AS orders,
           COUNT(*) AS items,
           SUM(price) AS price_total,
           SUM(freight_value) AS freight_total
    FROM v_sales
    GROUP BY category
),
rates AS (
    SELECT category, orders, items,
           ROUND(price_total / NULLIF(items, 0), 2) AS avg_price,
           ROUND(freight_total / NULLIF(items, 0), 2) AS avg_freight,
           ROUND(100.0 * freight_total / NULLIF(price_total, 0), 2) AS freight_pct_of_price,
           orders < {{MIN_SAMPLE_SIZE}} AS low_sample
    FROM agg
)
SELECT category, orders, items, avg_price, avg_freight, freight_pct_of_price, low_sample,
       CASE WHEN NOT low_sample
            THEN RANK() OVER (PARTITION BY low_sample ORDER BY freight_pct_of_price DESC)
       END AS freight_pct_rank
FROM rates
ORDER BY low_sample, freight_pct_rank, freight_pct_of_price DESC;

-- result: by_region
WITH sales_region AS (
    SELECT order_id, price, freight_value,
           CASE WHEN customer_state IN ('AC', 'AP', 'AM', 'PA', 'RO', 'RR', 'TO') THEN 'North'
                WHEN customer_state IN ('AL', 'BA', 'CE', 'MA', 'PB', 'PE', 'PI', 'RN', 'SE') THEN 'Northeast'
                WHEN customer_state IN ('DF', 'GO', 'MT', 'MS') THEN 'Central-West'
                WHEN customer_state IN ('ES', 'MG', 'RJ', 'SP') THEN 'Southeast'
                WHEN customer_state IN ('PR', 'RS', 'SC') THEN 'South'
                ELSE 'Unknown' END AS region
    FROM v_sales
)
SELECT region,
       COUNT(DISTINCT order_id) AS orders,
       COUNT(*) AS items,
       ROUND(SUM(price), 2) AS revenue,
       ROUND(SUM(freight_value), 2) AS freight,
       ROUND(100.0 * SUM(freight_value) / NULLIF(SUM(price), 0), 2) AS freight_pct_of_price,
       ROUND(AVG(freight_value), 2) AS avg_freight_per_item
FROM sales_region
GROUP BY region
ORDER BY freight_pct_of_price DESC;