# Data Quality Findings and Decisions

Source: docs/data_quality_report.md (audit run 2026-10-03). All timestamps are naive and assumed to be Brazil local time.

| Issue | Found | Decision |
|---|---|---|
| Review title / comment empty | 88.3% / 58.7% | Optional fields. Keep; add `has_comment` flag |
| Repeated review_id / orders with >1 review | 789 / 547 | Keep the latest review per order (`v_reviews_clean`) |
| Geolocation rows beyond 1 per zip prefix | 981,148 of 1,000,163 | One row per zip prefix, averaged lat/lng (`v_geolocation_clean`) |
| customer_unique_id with >1 customer_id | 2,997 (3.1%) | Count customers by `customer_unique_id` |
| Products with no category | 610 (1.85%) | Category = `unknown` |
| Categories missing from translation | 13 products | Keep the Portuguese name as fallback |
| Orders canceled / unavailable | 1,234 (1.24%) | Excluded from revenue and all sales metrics |
| Orders with no items | 775 (603 unavailable, 164 canceled, 8 other) | No revenue; dropped by inner join to items |
| Orders with no review | 768 | Left join; treated as "no review", never as a score |
| Delivered but no delivery date | 8 | Not counted as delivered; excluded from delivery/late metrics |
| Delivery date present but not delivered | 6 | Same: excluded from delivery/late metrics |
| Carrier pickup before purchase / delivery before pickup | 166 / 23 | Flagged only. Delivery time uses purchase to customer delivery |
| payment_type = not_defined | 3 | Removed from payment analysis |
| installments < 1 | 2 | Set to NULL |
| payment_value = 0 | 9 | Kept (may be fully voucher-paid; assumption) |
| product weight = 0 | 4 | Set to NULL |
| Customer / seller zip not in geolocation | 278 / 7 | Left join; no revenue impact |