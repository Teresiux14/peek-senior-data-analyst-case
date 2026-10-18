--  One row per cohort month and month offset:
--   cohort_month        month of the customer's first completed order
--   months_since_first  0 = first month, 1 = one month later, up to 12
--   cohort_customers    customers in the cohort
--   active_customers    cohort customers who ordered at that offset
--   pct_active          active_customers / cohort_customers, in percent
--
-- Requires: analysis.completed_order_items (part1_queries.sql, section A2).
-- The cutoff is not written here: it comes from the base view, so changing the cutoff in A2 updates this view automatically.
-- Cells that have not yet occurred are excluded, not shown as 0%.


CREATE OR REPLACE VIEW `peek-data-case.analysis.cohort_retention` AS
WITH first_orders AS (
  SELECT
    user_id,
    DATE_TRUNC(DATE(MIN(order_created_at)), MONTH) AS cohort_month
  FROM `peek-data-case.analysis.completed_order_items`
  GROUP BY user_id
),

cohort_size AS (
  SELECT cohort_month, COUNT(*) AS cohort_customers
  FROM first_orders
  GROUP BY cohort_month
),

activity AS (
  SELECT DISTINCT
    c.user_id,
    f.cohort_month,
    DATE_DIFF(c.month, f.cohort_month, MONTH) AS months_since_first
  FROM `peek-data-case.analysis.completed_order_items` AS c
  JOIN first_orders AS f
    USING (user_id)
),

active_counts AS (
  SELECT
    cohort_month,
    months_since_first,
    COUNT(DISTINCT user_id) AS active_customers
  FROM activity
  GROUP BY cohort_month, months_since_first
),

-- last complete month, taken from the base view
last_month AS (
  SELECT MAX(month) AS last_complete_month
  FROM `peek-data-case.analysis.completed_order_items`
),

-- full grid of cohort x offset, keeping only offsets that have already happened
grid AS (
  SELECT
    c.cohort_month,
    k AS months_since_first
  FROM cohort_size AS c
  CROSS JOIN UNNEST(GENERATE_ARRAY(0, 12)) AS k
  CROSS JOIN last_month AS l
  WHERE DATE_ADD(c.cohort_month, INTERVAL k MONTH) <= l.last_complete_month
)

SELECT
  g.cohort_month,
  g.months_since_first,
  s.cohort_customers,
  COALESCE(a.active_customers, 0) AS active_customers,
  ROUND(100 * SAFE_DIVIDE(COALESCE(a.active_customers, 0), s.cohort_customers), 2) AS pct_active
FROM grid AS g
JOIN cohort_size AS s
  USING (cohort_month)
LEFT JOIN active_counts AS a
  USING (cohort_month, months_since_first);
