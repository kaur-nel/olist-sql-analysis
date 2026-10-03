# Data Quality Report

Generated: 2026-10-03 20:26

## row_counts

| table_name | row_count |
|---|---|
| customers | 99441 |
| geolocation | 1000163 |
| order_items | 112650 |
| order_payments | 103886 |
| order_reviews | 99224 |
| orders | 99441 |
| product_category_name_translation | 71 |
| products | 32951 |
| sellers | 3095 |

## null_pct_per_column

| table_name | column_name | total_rows | null_rows | null_pct |
|---|---|---|---|---|
| order_reviews | review_comment_title | 99224 | 87656 | 88.34 |
| order_reviews | review_comment_message | 99224 | 58247 | 58.7 |
| orders | order_delivered_customer_date | 99441 | 2965 | 2.98 |
| products | product_category_name | 32951 | 610 | 1.85 |
| products | product_description_lenght | 32951 | 610 | 1.85 |
| products | product_name_lenght | 32951 | 610 | 1.85 |
| products | product_photos_qty | 32951 | 610 | 1.85 |
| orders | order_delivered_carrier_date | 99441 | 1783 | 1.79 |
| orders | order_approved_at | 99441 | 160 | 0.16 |
| products | product_height_cm | 32951 | 2 | 0.01 |
| products | product_length_cm | 32951 | 2 | 0.01 |
| products | product_weight_g | 32951 | 2 | 0.01 |
| products | product_width_cm | 32951 | 2 | 0.01 |

## duplicate_keys

| check_name | issue_count | total_rows | pct |
|---|---|---|---|
| order_reviews: review_id used by more than one row | 789 | 98410 | 0.8 |
| order_reviews: orders with more than one review row | 547 | 98673 | 0.55 |
| geolocation: extra rows beyond one per zip prefix | 981148 | 1000163 | 98.1 |
| customers: customer_unique_id with more than one customer_id | 2997 | 96096 | 3.12 |

## orphan_foreign_keys

| check_name | issue_count | total_rows | pct |
|---|---|---|---|
| orders.customer_id -> customers | 0 | 99441 | 0.0 |
| order_items.order_id -> orders | 0 | 112650 | 0.0 |
| order_items.product_id -> products | 0 | 112650 | 0.0 |
| order_items.seller_id -> sellers | 0 | 112650 | 0.0 |
| order_payments.order_id -> orders | 0 | 103886 | 0.0 |
| order_reviews.order_id -> orders | 0 | 99224 | 0.0 |
| products.category -> translation (non-null categories) | 13 | 32341 | 0.04 |
| customers.zip -> geolocation | 278 | 99441 | 0.28 |
| sellers.zip -> geolocation | 7 | 3095 | 0.23 |

## impossible_dates

| check_name | issue_count | total_rows | pct |
|---|---|---|---|
| missing purchase timestamp | 0 | 99441 | 0.0 |
| approved before purchase | 0 | 99441 | 0.0 |
| delivery date present but status not delivered | 6 | 99441 | 0.01 |
| customer delivery before purchase | 0 | 99441 | 0.0 |
| estimated delivery before purchase | 0 | 99441 | 0.0 |
| carrier pickup before purchase | 166 | 99441 | 0.17 |
| customer delivery before carrier pickup | 23 | 99441 | 0.02 |
| status delivered but no delivery date | 8 | 99441 | 0.01 |

## invalid_values

| check_name | issue_count | total_rows | pct |
|---|---|---|---|
| products: weight is 0 | 4 | 32951 | 0.01 |
| order_payments: payment_type = not_defined | 3 | 103886 | 0.0 |
| order_payments: installments < 1 | 2 | 103886 | 0.0 |
| order_payments: payment_value = 0 | 9 | 103886 | 0.01 |
| order_payments: payment_value < 0 | 0 | 103886 | 0.0 |
| order_reviews: score NULL or outside 1-5 | 0 | 99224 | 0.0 |
| order_items: price = 0 | 0 | 112650 | 0.0 |
| order_items: price is NULL | 0 | 112650 | 0.0 |
| order_items: freight_value < 0 | 0 | 112650 | 0.0 |
| order_items: price < 0 | 0 | 112650 | 0.0 |

## orders_missing_related_rows

| check_name | issue_count | total_rows | pct |
|---|---|---|---|
| orders canceled/unavailable (excluded from revenue) | 1234 | 99441 | 1.24 |
| orders with no payment | 1 | 99441 | 0.0 |
| orders with no review | 768 | 99441 | 0.77 |
| orders with no items | 775 | 99441 | 0.78 |

## order_status_mix

| order_status | orders | orders_without_items |
|---|---|---|
| delivered | 96478 | 0 |
| shipped | 1107 | 1 |
| canceled | 625 | 164 |
| unavailable | 609 | 603 |
| invoiced | 314 | 2 |
| processing | 301 | 0 |
| created | 5 | 5 |
| approved | 2 | 0 |
