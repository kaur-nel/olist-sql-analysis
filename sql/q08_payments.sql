-- Question: How do customers pay, and how do instalments relate to order value?
-- Approach: Use cleaned payments for revenue orders. Summarise by payment type, then look at credit
--           card orders by number of instalments, plus one correlation.
-- Assumptions: payment_value includes freight, so it is larger than item revenue. One order can use
--              several payment types (for example voucher plus card), so order shares add to more than
--              100 pct while value shares add to 100. An order's instalments = the maximum across its
--              card payments. Instalment counts with fewer than {{MIN_SAMPLE_SIZE}} orders are flagged.

-- result: payment_mix
WITH pay AS (
    SELECT p.order_id, p.payment_type, p.payment_value
    FROM v_payments_clean p
    JOIN v_orders_clean o ON o.order_id = p.order_id
    WHERE o.is_revenue_order
)
SELECT payment_type,
       COUNT(*) AS payments,
       COUNT(DISTINCT order_id) AS orders,
       ROUND(100.0 * COUNT(DISTINCT order_id) / NULLIF((SELECT COUNT(DISTINCT order_id) FROM pay), 0), 2) AS orders_using_type_pct,
       ROUND(SUM(payment_value), 2) AS payment_value,
       ROUND(100.0 * SUM(payment_value) / NULLIF(SUM(SUM(payment_value)) OVER (), 0), 2) AS value_share_pct,
       ROUND(AVG(payment_value), 2) AS avg_payment_value
FROM pay
GROUP BY payment_type
ORDER BY payment_value DESC;

-- result: installments_vs_value
WITH card_orders AS (
    SELECT p.order_id,
           SUM(p.payment_value) AS card_value,
           MAX(p.payment_installments) AS installments
    FROM v_payments_clean p
    JOIN v_orders_clean o ON o.order_id = p.order_id
    WHERE o.is_revenue_order
      AND p.payment_type = 'credit_card'
    GROUP BY p.order_id
)
SELECT installments,
       COUNT(*) AS orders,
       ROUND(AVG(card_value), 2) AS avg_order_value,
       ROUND(CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY card_value) AS NUMERIC), 2) AS median_order_value,
       COUNT(*) < {{MIN_SAMPLE_SIZE}} AS low_sample
FROM card_orders
WHERE installments IS NOT NULL
GROUP BY installments
ORDER BY installments;

-- result: installments_correlation
WITH card_orders AS (
    SELECT p.order_id,
           SUM(p.payment_value) AS card_value,
           MAX(p.payment_installments) AS installments
    FROM v_payments_clean p
    JOIN v_orders_clean o ON o.order_id = p.order_id
    WHERE o.is_revenue_order
      AND p.payment_type = 'credit_card'
    GROUP BY p.order_id
)
SELECT COUNT(*) AS orders,
       ROUND(CAST(CORR(installments, card_value) AS NUMERIC), 3) AS corr_installments_vs_value
FROM card_orders
WHERE installments IS NOT NULL;