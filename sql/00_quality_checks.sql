-- Data-quality audit for the raw Olist tables (PostgreSQL). Read-only.
-- Each "-- name:" block is run by src/run_quality_audit.py and becomes a report section.
-- Blocks with issue_count / total_rows get a pct column added by the runner (zero-safe).
-- Primary keys are enforced by the schema, so duplicate checks cover non-key data only.

-- name: row_counts
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'product_category_name_translation', COUNT(*) FROM product_category_name_translation
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
ORDER BY table_name;

-- name: null_pct_per_column
-- Only columns with at least one NULL are listed. jsonb_each_text turns every column into
-- a key/value pair, so one query covers all tables (PostgreSQL-specific).
SELECT t.table_name,
       j.key AS column_name,
       COUNT(*) AS total_rows,
       COUNT(*) FILTER (WHERE j.value IS NULL) AS null_rows,
       ROUND(100.0 * COUNT(*) FILTER (WHERE j.value IS NULL) / NULLIF(COUNT(*), 0), 2) AS null_pct
FROM (
    SELECT 'customers' AS table_name, to_jsonb(c) AS r FROM customers c
    UNION ALL SELECT 'sellers', to_jsonb(s) FROM sellers s
    UNION ALL SELECT 'products', to_jsonb(p) FROM products p
    UNION ALL SELECT 'geolocation', to_jsonb(g) FROM geolocation g
    UNION ALL SELECT 'orders', to_jsonb(o) FROM orders o
    UNION ALL SELECT 'order_items', to_jsonb(i) FROM order_items i
    UNION ALL SELECT 'order_payments', to_jsonb(pay) FROM order_payments pay
    UNION ALL SELECT 'order_reviews', to_jsonb(rv) FROM order_reviews rv
) t,
LATERAL jsonb_each_text(t.r) j
GROUP BY t.table_name, j.key
HAVING COUNT(*) FILTER (WHERE j.value IS NULL) > 0
ORDER BY null_pct DESC, t.table_name, j.key;

-- name: duplicate_keys
SELECT 'order_reviews: review_id used by more than one row' AS check_name,
       COUNT(*) AS issue_count,
       (SELECT COUNT(DISTINCT review_id) FROM order_reviews) AS total_rows
FROM (SELECT review_id FROM order_reviews GROUP BY review_id HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'order_reviews: orders with more than one review row', COUNT(*),
       (SELECT COUNT(DISTINCT order_id) FROM order_reviews)
FROM (SELECT order_id FROM order_reviews GROUP BY order_id HAVING COUNT(*) > 1) d
UNION ALL
SELECT 'geolocation: extra rows beyond one per zip prefix',
       COUNT(*) - COUNT(DISTINCT geolocation_zip_code_prefix), COUNT(*)
FROM geolocation
UNION ALL
SELECT 'customers: customer_unique_id with more than one customer_id', COUNT(*),
       (SELECT COUNT(DISTINCT customer_unique_id) FROM customers)
FROM (SELECT customer_unique_id FROM customers GROUP BY customer_unique_id HAVING COUNT(*) > 1) d;

-- name: orphan_foreign_keys
SELECT 'orders.customer_id -> customers' AS check_name,
       COUNT(*) FILTER (WHERE c.customer_id IS NULL) AS issue_count, COUNT(*) AS total_rows
FROM orders o LEFT JOIN customers c ON c.customer_id = o.customer_id
UNION ALL
SELECT 'order_items.order_id -> orders', COUNT(*) FILTER (WHERE o.order_id IS NULL), COUNT(*)
FROM order_items i LEFT JOIN orders o ON o.order_id = i.order_id
UNION ALL
SELECT 'order_items.product_id -> products', COUNT(*) FILTER (WHERE p.product_id IS NULL), COUNT(*)
FROM order_items i LEFT JOIN products p ON p.product_id = i.product_id
UNION ALL
SELECT 'order_items.seller_id -> sellers', COUNT(*) FILTER (WHERE s.seller_id IS NULL), COUNT(*)
FROM order_items i LEFT JOIN sellers s ON s.seller_id = i.seller_id
UNION ALL
SELECT 'order_payments.order_id -> orders', COUNT(*) FILTER (WHERE o.order_id IS NULL), COUNT(*)
FROM order_payments pay LEFT JOIN orders o ON o.order_id = pay.order_id
UNION ALL
SELECT 'order_reviews.order_id -> orders', COUNT(*) FILTER (WHERE o.order_id IS NULL), COUNT(*)
FROM order_reviews rv LEFT JOIN orders o ON o.order_id = rv.order_id
UNION ALL
SELECT 'products.category -> translation (non-null categories)',
       COUNT(*) FILTER (WHERE t.product_category_name IS NULL), COUNT(*)
FROM products p
LEFT JOIN product_category_name_translation t ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
UNION ALL
SELECT 'customers.zip -> geolocation', COUNT(*) FILTER (WHERE g.zip IS NULL), COUNT(*)
FROM customers c
LEFT JOIN (SELECT DISTINCT geolocation_zip_code_prefix AS zip FROM geolocation) g
       ON g.zip = c.customer_zip_code_prefix
UNION ALL
SELECT 'sellers.zip -> geolocation', COUNT(*) FILTER (WHERE g.zip IS NULL), COUNT(*)
FROM sellers s
LEFT JOIN (SELECT DISTINCT geolocation_zip_code_prefix AS zip FROM geolocation) g
       ON g.zip = s.seller_zip_code_prefix;

-- name: impossible_dates
SELECT 'approved before purchase' AS check_name,
       COUNT(*) FILTER (WHERE order_approved_at < order_purchase_timestamp) AS issue_count,
       COUNT(*) AS total_rows
FROM orders
UNION ALL
SELECT 'carrier pickup before purchase',
       COUNT(*) FILTER (WHERE order_delivered_carrier_date < order_purchase_timestamp), COUNT(*)
FROM orders
UNION ALL
SELECT 'customer delivery before purchase',
       COUNT(*) FILTER (WHERE order_delivered_customer_date < order_purchase_timestamp), COUNT(*)
FROM orders
UNION ALL
SELECT 'customer delivery before carrier pickup',
       COUNT(*) FILTER (WHERE order_delivered_customer_date < order_delivered_carrier_date), COUNT(*)
FROM orders
UNION ALL
SELECT 'estimated delivery before purchase',
       COUNT(*) FILTER (WHERE order_estimated_delivery_date < order_purchase_timestamp), COUNT(*)
FROM orders
UNION ALL
SELECT 'status delivered but no delivery date',
       COUNT(*) FILTER (WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL), COUNT(*)
FROM orders
UNION ALL
SELECT 'delivery date present but status not delivered',
       COUNT(*) FILTER (WHERE order_status <> 'delivered' AND order_delivered_customer_date IS NOT NULL), COUNT(*)
FROM orders
UNION ALL
SELECT 'missing purchase timestamp',
       COUNT(*) FILTER (WHERE order_purchase_timestamp IS NULL), COUNT(*)
FROM orders;

-- name: invalid_values
SELECT 'order_items: price < 0' AS check_name,
       COUNT(*) FILTER (WHERE price < 0) AS issue_count, COUNT(*) AS total_rows
FROM order_items
UNION ALL SELECT 'order_items: price = 0', COUNT(*) FILTER (WHERE price = 0), COUNT(*) FROM order_items
UNION ALL SELECT 'order_items: price is NULL', COUNT(*) FILTER (WHERE price IS NULL), COUNT(*) FROM order_items
UNION ALL SELECT 'order_items: freight_value < 0', COUNT(*) FILTER (WHERE freight_value < 0), COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments: payment_value < 0', COUNT(*) FILTER (WHERE payment_value < 0), COUNT(*) FROM order_payments
UNION ALL SELECT 'order_payments: payment_value = 0', COUNT(*) FILTER (WHERE payment_value = 0), COUNT(*) FROM order_payments
UNION ALL SELECT 'order_payments: installments < 1', COUNT(*) FILTER (WHERE payment_installments < 1), COUNT(*) FROM order_payments
UNION ALL SELECT 'order_payments: payment_type = not_defined', COUNT(*) FILTER (WHERE payment_type = 'not_defined'), COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews: score NULL or outside 1-5',
       COUNT(*) FILTER (WHERE review_score IS NULL OR review_score NOT BETWEEN 1 AND 5), COUNT(*)
FROM order_reviews
UNION ALL SELECT 'products: weight is 0', COUNT(*) FILTER (WHERE product_weight_g = 0), COUNT(*) FROM products;

-- name: orders_missing_related_rows
SELECT 'orders with no items' AS check_name,
       COUNT(*) FILTER (WHERE i.order_id IS NULL) AS issue_count, COUNT(*) AS total_rows
FROM orders o
LEFT JOIN (SELECT DISTINCT order_id FROM order_items) i ON i.order_id = o.order_id
UNION ALL
SELECT 'orders with no payment', COUNT(*) FILTER (WHERE p.order_id IS NULL), COUNT(*)
FROM orders o
LEFT JOIN (SELECT DISTINCT order_id FROM order_payments) p ON p.order_id = o.order_id
UNION ALL
SELECT 'orders with no review', COUNT(*) FILTER (WHERE r.order_id IS NULL), COUNT(*)
FROM orders o
LEFT JOIN (SELECT DISTINCT order_id FROM order_reviews) r ON r.order_id = o.order_id
UNION ALL
SELECT 'orders canceled/unavailable (excluded from revenue)',
       COUNT(*) FILTER (WHERE order_status IN ('canceled', 'unavailable')), COUNT(*)
FROM orders;

-- name: order_status_mix
SELECT o.order_status,
       COUNT(*) AS orders,
       COUNT(*) FILTER (WHERE NOT EXISTS (
           SELECT 1 FROM order_items i WHERE i.order_id = o.order_id)) AS orders_without_items
FROM orders o
GROUP BY o.order_status
ORDER BY orders DESC;