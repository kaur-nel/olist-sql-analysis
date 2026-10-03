-- Question: Which 10 product categories earn the most revenue, and how concentrated is revenue?
-- Approach: Aggregate revenue per category, compute each category's share of TOTAL revenue and a
--           running (cumulative) share with window functions, then keep the top 10.
-- Assumptions: Shares are computed over ALL categories before the top-10 filter, so they are true
--              shares of the whole business. Missing categories appear as 'unknown'.
--              Ties are broken alphabetically so the cumulative share is deterministic.
WITH params AS (
    SELECT 10 AS top_n          -- the question asks for the top 10
),
category_revenue AS (
    SELECT category,
           SUM(price) AS revenue,
           COUNT(DISTINCT order_id) AS orders
    FROM v_sales
    GROUP BY category
),
ranked AS (
    SELECT category,
           revenue,
           orders,
           RANK() OVER (ORDER BY revenue DESC) AS revenue_rank,
           100.0 * revenue / NULLIF(SUM(revenue) OVER (), 0) AS share_pct,
           100.0 * SUM(revenue) OVER (ORDER BY revenue DESC, category)
                 / NULLIF(SUM(revenue) OVER (), 0) AS cumulative_share_pct
    FROM category_revenue
)
SELECT revenue_rank,
       category,
       ROUND(revenue, 2) AS revenue,
       orders,
       ROUND(share_pct, 2) AS share_pct,
       ROUND(cumulative_share_pct, 2) AS cumulative_share_pct
FROM ranked
WHERE revenue_rank <= (SELECT top_n FROM params)
ORDER BY revenue_rank;