-- Question: Who are the best sellers when we combine revenue, on-time delivery and review score?
-- Approach: Aggregate per seller at order level, rank sellers on each metric (RANK for revenue and late
--           rate, DENSE_RANK for review score), average the three ranks, and rank that result.
-- Assumptions: Only sellers with at least {{MIN_SAMPLE_SIZE}} orders are ranked; the rest are counted in
--              the sample_size_summary result. Late rate uses delivered orders only. An order with several
--              sellers shares one review, so each of those sellers gets that review. Equal weights for the
--              three ranks is a simple heuristic. Many sellers tie at a 0 late rate, which is expected.

-- result: seller_ranking
WITH seller_orders AS (
    SELECT seller_id, order_id, is_late, SUM(price) AS order_revenue
    FROM v_sales
    GROUP BY seller_id, order_id, is_late
),
seller_agg AS (
    SELECT so.seller_id,
           COUNT(*) AS orders,
           SUM(so.order_revenue) AS revenue,
           SUM(CASE WHEN so.is_late IS NOT NULL THEN 1 ELSE 0 END) AS delivered_orders,
           SUM(CASE WHEN so.is_late THEN 1 ELSE 0 END) AS late_orders,
           AVG(r.review_score) AS avg_review_score
    FROM seller_orders so
    LEFT JOIN v_reviews_clean r ON r.order_id = so.order_id
    GROUP BY so.seller_id
),
reliable AS (
    SELECT a.seller_id,
           s.seller_state,
           a.orders,
           a.revenue,
           100.0 * a.late_orders / NULLIF(a.delivered_orders, 0) AS late_rate_pct,
           ROUND(a.avg_review_score, 2) AS avg_review_score
    FROM seller_agg a
    JOIN sellers s ON s.seller_id = a.seller_id
    WHERE a.orders >= {{MIN_SAMPLE_SIZE}}
),
ranked AS (
    SELECT seller_id, seller_state, orders, revenue, late_rate_pct, avg_review_score,
           RANK() OVER (ORDER BY revenue DESC) AS revenue_rank,
           RANK() OVER (ORDER BY late_rate_pct ASC NULLS LAST) AS late_rate_rank,
           DENSE_RANK() OVER (ORDER BY avg_review_score DESC NULLS LAST) AS review_rank
    FROM reliable
),
scored AS (
    SELECT seller_id, seller_state, orders, revenue, late_rate_pct, avg_review_score,
           revenue_rank, late_rate_rank, review_rank,
           (revenue_rank + late_rate_rank + review_rank) / 3.0 AS avg_rank
    FROM ranked
)
SELECT seller_id,
       seller_state,
       orders,
       ROUND(revenue, 2) AS revenue,
       ROUND(late_rate_pct, 2) AS late_rate_pct,
       avg_review_score,
       revenue_rank,
       late_rate_rank,
       review_rank,
       ROUND(avg_rank, 2) AS avg_rank,
       DENSE_RANK() OVER (ORDER BY avg_rank) AS overall_rank
FROM scored
ORDER BY overall_rank, revenue_rank
LIMIT 20;

-- result: sample_size_summary
WITH seller_totals AS (
    SELECT seller_id,
           COUNT(DISTINCT order_id) AS orders,
           SUM(price) AS revenue
    FROM v_sales
    GROUP BY seller_id
),
flagged AS (
    SELECT seller_id, revenue, orders < {{MIN_SAMPLE_SIZE}} AS low_sample
    FROM seller_totals
)
SELECT low_sample,
       COUNT(*) AS sellers,
       ROUND(SUM(revenue), 2) AS revenue,
       ROUND(100.0 * SUM(revenue) / NULLIF(SUM(SUM(revenue)) OVER (), 0), 2) AS revenue_share_pct
FROM flagged
GROUP BY low_sample
ORDER BY low_sample;