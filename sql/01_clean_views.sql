-- Cleaning layer: non-destructive views over the raw tables. Safe to re-run.
-- Rules come from docs/data_quality_findings.md.

DROP VIEW IF EXISTS v_sales CASCADE;
DROP VIEW IF EXISTS v_payments_clean CASCADE;
DROP VIEW IF EXISTS v_customers_clean CASCADE;
DROP VIEW IF EXISTS v_geolocation_clean CASCADE;
DROP VIEW IF EXISTS v_reviews_clean CASCADE;
DROP VIEW IF EXISTS v_products_clean CASCADE;
DROP VIEW IF EXISTS v_orders_clean CASCADE;

-- Orders with parsed flags. is_delivered is true only for delivered orders with a valid date.
-- is_late and delivery_days are NULL when not delivered, so they never skew the rates.
CREATE VIEW v_orders_clean AS
WITH base AS (
    SELECT o.*,
           (o.order_status = 'delivered'
            AND o.order_delivered_customer_date IS NOT NULL
            AND o.order_delivered_customer_date >= o.order_purchase_timestamp) AS is_delivered
    FROM orders o
    WHERE o.order_purchase_timestamp IS NOT NULL
)
SELECT order_id,
       customer_id,
       order_status,
       order_purchase_timestamp,
       order_delivered_carrier_date,
       order_delivered_customer_date,
       order_estimated_delivery_date,
       DATE_TRUNC('month', order_purchase_timestamp) AS purchase_month,
       (order_status NOT IN ('canceled', 'unavailable')) AS is_revenue_order,
       is_delivered,
       CASE WHEN is_delivered THEN
            ROUND(EXTRACT(EPOCH FROM (order_delivered_customer_date - order_purchase_timestamp)) / 86400.0, 2)
       END AS delivery_days,
       CASE WHEN is_delivered THEN
            (order_delivered_customer_date > order_estimated_delivery_date)
       END AS is_late
FROM base;

-- Products: English category, typo columns fixed, weight 0 treated as missing.
CREATE VIEW v_products_clean AS
SELECT p.product_id,
       COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
       p.product_name_lenght AS product_name_length,
       p.product_description_lenght AS product_description_length,
       p.product_photos_qty,
       NULLIF(p.product_weight_g, 0) AS product_weight_g,
       p.product_length_cm,
       p.product_height_cm,
       p.product_width_cm
FROM products p
LEFT JOIN product_category_name_translation t
       ON t.product_category_name = p.product_category_name;

-- Reviews: exactly one row per order (the latest), valid scores only.
CREATE VIEW v_reviews_clean AS
SELECT order_id,
       review_id,
       review_score,
       (NULLIF(TRIM(review_comment_message), '') IS NOT NULL) AS has_comment,
       review_creation_date
FROM (
    SELECT r.*,
           ROW_NUMBER() OVER (
               PARTITION BY r.order_id
               ORDER BY r.review_creation_date DESC, r.review_answer_timestamp DESC, r.review_id
           ) AS rn
    FROM order_reviews r
    WHERE r.review_score BETWEEN 1 AND 5
) ranked
WHERE rn = 1;

-- Geolocation: one row per zip prefix (average coordinates, most common city/state).
CREATE VIEW v_geolocation_clean AS
SELECT geolocation_zip_code_prefix AS zip_code_prefix,
       AVG(geolocation_lat) AS lat,
       AVG(geolocation_lng) AS lng,
       MODE() WITHIN GROUP (ORDER BY LOWER(TRIM(geolocation_city))) AS city,
       MODE() WITHIN GROUP (ORDER BY geolocation_state) AS state
FROM geolocation
WHERE geolocation_zip_code_prefix IS NOT NULL
GROUP BY geolocation_zip_code_prefix;

-- Customers: normalised text (accents are kept, only case and spaces are fixed).
CREATE VIEW v_customers_clean AS
SELECT customer_id,
       customer_unique_id,
       customer_zip_code_prefix AS zip_code_prefix,
       LOWER(TRIM(customer_city)) AS city,
       UPPER(TRIM(customer_state)) AS state
FROM customers;

-- Payments: drop not_defined type, invalid installment counts become NULL.
CREATE VIEW v_payments_clean AS
SELECT order_id,
       payment_sequential,
       payment_type,
       CASE WHEN payment_installments >= 1 THEN payment_installments END AS payment_installments,
       payment_value
FROM order_payments
WHERE payment_type <> 'not_defined';

-- Main fact view: one row per item sold, revenue orders only (not canceled/unavailable).
-- Reviews are not joined here (they are per order, which would repeat across items).
CREATE VIEW v_sales AS
SELECT i.order_id,
       i.order_item_id,
       o.order_status,
       o.purchase_month,
       o.order_purchase_timestamp,
       o.is_delivered,
       o.is_late,
       o.delivery_days,
       c.customer_unique_id,
       c.state AS customer_state,
       i.seller_id,
       s.seller_state,
       p.category,
       i.price,
       i.freight_value
FROM order_items i
JOIN v_orders_clean o    ON o.order_id = i.order_id
JOIN v_customers_clean c ON c.customer_id = o.customer_id
JOIN sellers s           ON s.seller_id = i.seller_id
JOIN v_products_clean p  ON p.product_id = i.product_id
WHERE o.is_revenue_order;