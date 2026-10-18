
-- Creates monthly_summary, the one table the dashboard reads.
-- Requires: analysis.completed_order_items (created in part1_queries.sql, section A2).
--
-- The cutoff (2026-09-30) and the low-volume threshold (500 orders) are writteninside this view. Views cannot use DECLARE. If you change either one, change it here.

CREATE OR REPLACE VIEW `peek-data-case.analysis.monthly_summary` AS
WITH base AS (
  SELECT * FROM `peek-data-case.analysis.completed_order_items`
),

-- month in which each customer made their first completed order
first_orders AS (
  SELECT user_id, DATE_TRUNC(DATE(MIN(order_created_at)), MONTH) AS first_order_month
  FROM base
  GROUP BY user_id
),

sales AS (
  SELECT
    month,
    SUM(sale_price) AS revenue,
    SUM(sale_price - cogs) AS gross_profit,
    COUNT(DISTINCT order_id) AS orders,
    COUNT(*) AS units
  FROM base
  GROUP BY month
),

customers AS (
  SELECT
    b.month,
    COUNT(DISTINCT b.user_id) AS active_customers,
    COUNT(DISTINCT IF(b.month = f.first_order_month, b.user_id, NULL)) AS new_customers,
    COUNT(DISTINCT IF(b.month != f.first_order_month, b.user_id, NULL)) AS returning_customers
  FROM base AS b
  JOIN first_orders AS f
    USING (user_id)
  GROUP BY b.month
),

revenue_split AS (
  SELECT
    b.month,
    SUM(IF(b.month = f.first_order_month, b.sale_price, 0)) AS revenue_new,
    SUM(IF(b.month != f.first_order_month, b.sale_price, 0)) AS revenue_returning
  FROM base AS b
  JOIN first_orders AS f
    USING (user_id)
  GROUP BY b.month
),

customer_months AS (
  SELECT DISTINCT month, user_id FROM base
),

-- churn flag per customer-month (same rule as B2 in part1_queries.sql)
churn_flags AS (
  SELECT
    cm.month,
    DATE_ADD(LAST_DAY(cm.month), INTERVAL 90 DAY) AS window_end,
    NOT EXISTS (
      SELECT 1
      FROM base AS x
      WHERE x.user_id = cm.user_id
        AND DATE(x.order_created_at) > LAST_DAY(cm.month)
        AND DATE(x.order_created_at) <= DATE_ADD(LAST_DAY(cm.month), INTERVAL 90 DAY)
    ) AS is_churn
  FROM customer_months AS cm
),

churn AS (
  SELECT
    month,
    COUNTIF(window_end <= DATE '2026-09-30') AS mature_customers,
    COUNTIF(window_end <= DATE '2026-09-30' AND is_churn) AS churned_customers_90d
  FROM churn_flags
  GROUP BY month
)

SELECT
  s.month,
  ROUND(s.revenue, 2) AS revenue,
  ROUND(s.gross_profit, 2) AS gross_profit,
  ROUND(100 * SAFE_DIVIDE(s.gross_profit, s.revenue), 2) AS gross_margin_pct,
  s.orders,
  s.units,
  ROUND(SAFE_DIVIDE(s.revenue, s.orders), 2) AS aov,
  ROUND(100 * SAFE_DIVIDE(s.revenue - LAG(s.revenue) OVER w, LAG(s.revenue) OVER w), 2) AS revenue_mom_growth_pct,
  c.active_customers,
  c.new_customers,
  c.returning_customers,
  ROUND(r.revenue_new, 2) AS revenue_new,
  ROUND(r.revenue_returning, 2) AS revenue_returning,
  ROUND(100 * SAFE_DIVIDE(r.revenue_returning, s.revenue), 2) AS pct_revenue_from_returning,
  ch.churned_customers_90d,
  ch.mature_customers,
  ROUND(100 * SAFE_DIVIDE(ch.churned_customers_90d, ch.mature_customers), 2) AS churn_rate_90d,
  DATE_ADD(LAST_DAY(s.month), INTERVAL 90 DAY) <= DATE '2026-09-30' AS is_mature,
  s.orders < 500 AS is_low_volume
FROM sales AS s
JOIN customers AS c USING (month)
JOIN revenue_split AS r USING (month)
JOIN churn AS ch USING (month)
WINDOW w AS (ORDER BY s.month)
ORDER BY s.month;
