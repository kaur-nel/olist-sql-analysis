-- Question: How concentrated is revenue geographically (Pareto: which states make up 80 pct of revenue)?
-- Approach: Revenue per state, share of total, running cumulative share, and a flag for the states
--           needed to reach the Pareto threshold. Done for customer states and for seller states.
-- Assumptions: The 80 pct threshold is the classic Pareto rule. A state is in the group if the share
--              accumulated BEFORE it is below 80, so the state that crosses 80 is included.
--              Revenue = SUM(price) for revenue orders.

-- result: by_customer_state
WITH params AS (
    SELECT 80 AS pareto_pct     -- classic 80/20 rule
),
state_revenue AS (
    SELECT customer_state,
           SUM(price) AS revenue,
           COUNT(DISTINCT order_id) AS orders,
           COUNT(DISTINCT customer_unique_id) AS customers
    FROM v_sales
    GROUP BY customer_state
),
shares AS (
    SELECT customer_state, revenue, orders, customers,
           100.0 * revenue / NULLIF(SUM(revenue) OVER (), 0) AS share_pct,
           100.0 * SUM(revenue) OVER (ORDER BY revenue DESC, customer_state)
                 / NULLIF(SUM(revenue) OVER (), 0) AS cumulative_share_pct,
           RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
    FROM state_revenue
)
SELECT revenue_rank,
       customer_state,
       ROUND(revenue, 2) AS revenue,
       orders,
       customers,
       ROUND(share_pct, 2) AS share_pct,
       ROUND(cumulative_share_pct, 2) AS cumulative_share_pct,
       (cumulative_share_pct - share_pct) < (SELECT pareto_pct FROM params) AS in_pareto_group
FROM shares
ORDER BY revenue_rank;

-- result: by_seller_state
WITH params AS (
    SELECT 80 AS pareto_pct
),
state_revenue AS (
    SELECT seller_state,
           SUM(price) AS revenue,
           COUNT(DISTINCT order_id) AS orders,
           COUNT(DISTINCT seller_id) AS sellers
    FROM v_sales
    GROUP BY seller_state
),
shares AS (
    SELECT seller_state, revenue, orders, sellers,
           100.0 * revenue / NULLIF(SUM(revenue) OVER (), 0) AS share_pct,
           100.0 * SUM(revenue) OVER (ORDER BY revenue DESC, seller_state)
                 / NULLIF(SUM(revenue) OVER (), 0) AS cumulative_share_pct,
           RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
    FROM state_revenue
)
SELECT revenue_rank,
       seller_state,
       ROUND(revenue, 2) AS revenue,
       orders,
       sellers,
       ROUND(share_pct, 2) AS share_pct,
       ROUND(cumulative_share_pct, 2) AS cumulative_share_pct,
       (cumulative_share_pct - share_pct) < (SELECT pareto_pct FROM params) AS in_pareto_group
FROM shares
ORDER BY revenue_rank;