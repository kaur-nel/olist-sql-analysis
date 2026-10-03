-- Question: How does delivery time relate to the review score?
-- Approach: Join delivered orders to their single cleaned review. Summarise by score, by delivery
--           time bucket, and with one correlation coefficient.
-- Assumptions: Delivery time = purchase to customer delivery, in days. Only delivered orders with
--              a review are used. Correlation shows association, not causation.

-- result: by_score
WITH delivered AS (
    SELECT o.delivery_days, o.is_late, r.review_score
    FROM v_orders_clean o
    JOIN v_reviews_clean r ON r.order_id = o.order_id
    WHERE o.is_delivered
)
SELECT review_score,
       COUNT(*) AS orders,
       ROUND(AVG(delivery_days), 2) AS avg_delivery_days,
       ROUND(CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days) AS NUMERIC), 2) AS median_delivery_days,
       ROUND(100.0 * SUM(CASE WHEN is_late THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS late_rate_pct
FROM delivered
GROUP BY review_score
ORDER BY review_score;

-- result: by_delivery_bucket
WITH delivered AS (
    SELECT o.delivery_days, r.review_score
    FROM v_orders_clean o
    JOIN v_reviews_clean r ON r.order_id = o.order_id
    WHERE o.is_delivered
),
bucketed AS (
    SELECT review_score,
           CASE WHEN delivery_days < 7  THEN '1: under 1 week'
                WHEN delivery_days < 14 THEN '2: 1-2 weeks'
                WHEN delivery_days < 21 THEN '3: 2-3 weeks'
                ELSE '4: 3+ weeks' END AS delivery_bucket   -- weekly buckets
    FROM delivered
)
SELECT delivery_bucket,
       COUNT(*) AS orders,
       ROUND(AVG(review_score), 2) AS avg_review_score,
       ROUND(100.0 * SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS bad_review_rate_pct
FROM bucketed
GROUP BY delivery_bucket
ORDER BY delivery_bucket;

-- result: correlation
SELECT COUNT(*) AS orders,
       ROUND(CAST(CORR(o.delivery_days, r.review_score) AS NUMERIC), 3) AS corr_delivery_days_vs_score
FROM v_orders_clean o
JOIN v_reviews_clean r ON r.order_id = o.order_id
WHERE o.is_delivered;