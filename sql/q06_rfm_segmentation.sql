-- Question: Which customer segments exist based on how recently, how often and how much they buy (RFM),
--           and how much revenue does each segment bring?
-- Approach: Per customer_unique_id compute Recency (days since last order), Frequency (distinct orders),
--           Monetary (sum of price). Score Recency and Monetary 1-5 with NTILE(5), score Frequency with
--           fixed rules, then map score combinations to named segments.
-- Assumptions: "Today" is the last purchase date in the data, not the real date, since the dataset is
--              historical. Frequency uses rules instead of NTILE because most customers ordered once, and
--              NTILE would split identical values into different buckets arbitrarily. Recency and money
--              ties are broken by customer id so results are repeatable. Segment rules are a judgement call.
WITH data_end AS (
    SELECT MAX(order_purchase_timestamp) AS last_ts FROM v_sales
),
customer AS (
    SELECT customer_unique_id,
           MAX(order_purchase_timestamp) AS last_purchase_ts,
           COUNT(DISTINCT order_id) AS frequency,
           SUM(price) AS monetary
    FROM v_sales
    GROUP BY customer_unique_id
),
rfm_raw AS (
    SELECT c.customer_unique_id,
           c.frequency,
           c.monetary,
           CAST(DATE_PART('day', d.last_ts - c.last_purchase_ts) AS INTEGER) AS recency_days
    FROM customer c
    CROSS JOIN data_end d
),
scored AS (
    SELECT customer_unique_id, recency_days, frequency, monetary,
           NTILE(5) OVER (ORDER BY recency_days DESC, customer_unique_id) AS r_score,  -- 5 = most recent
           CASE WHEN frequency >= 3 THEN 3
                WHEN frequency = 2 THEN 2
                ELSE 1 END AS f_score,                                                 -- 3 = 3+ orders
           NTILE(5) OVER (ORDER BY monetary ASC, customer_unique_id) AS m_score        -- 5 = top spenders
    FROM rfm_raw
),
segmented AS (
    SELECT customer_unique_id, recency_days, frequency, monetary,
           CASE WHEN r_score >= 4 AND f_score >= 2 THEN '1 Champions (recent repeat buyers)'
                WHEN r_score >= 4 AND m_score >= 4 THEN '2 Recent high spenders'
                WHEN r_score >= 4                  THEN '3 Recent / new'
                WHEN r_score <= 2 AND f_score >= 2 THEN '4 At-risk repeat buyers'
                WHEN r_score <= 2 AND m_score >= 4 THEN '5 Lapsed high spenders'
                WHEN r_score <= 2                  THEN '6 Lapsed'
                ELSE '7 Middle (recency score 3)' END AS segment
    FROM scored
)
SELECT segment,
       COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER (), 0), 2) AS customer_share_pct,
       ROUND(SUM(monetary), 2) AS revenue,
       ROUND(100.0 * SUM(monetary) / NULLIF(SUM(SUM(monetary)) OVER (), 0), 2) AS revenue_share_pct,
       ROUND(AVG(recency_days), 1) AS avg_recency_days,
       ROUND(AVG(frequency), 2) AS avg_orders,
       ROUND(AVG(monetary), 2) AS avg_spend
FROM segmented
GROUP BY segment
ORDER BY segment;