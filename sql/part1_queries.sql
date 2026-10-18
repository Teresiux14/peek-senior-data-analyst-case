-- HOW TO RUN
--   Run the whole file as a script in BigQuery (Standard SQL)
--   Sections are in dependency order:
--   A1 (checks) -> A2 (base view) -> A3 -> B1 -> B2.
--
-- CUTOFF
--   as_of_date = 2026-09-30. As October 2026 is not yet a complete month, it is a partial month. The analysis stops at the last complete month (September 2026)
--   Views cannot use DECLARE, so the same date is written inside the view in section A2. If the cutoff changes, it must change in both places.

-- Parameters used by the queries in this file
DECLARE as_of_date DATE DEFAULT DATE '2026-09-30';
DECLARE low_volume_threshold INT64 DEFAULT 500;  -- months with fewer orders are flagged


-- A1. DATA QUALITY CHECKS
--
-- Each block is one check. It returns the same four columns, so all checks are stacked with UNION ALL into one results table.
--
-- Purpose of each group, in order:
--   1-4:   order_items dates looked wrong, so order timestamps are tested first, then item timestamps are compared with their order.
--   5-6:   links between tables and status consistency.
--   7-8:   price validity and sale prices that are unusually high.
--   9-12:  product, cost and inventory data.
--   13-14: events and orders dated before the user's signup.
--   15-16: duplicate keys, which would inflate revenue and orders.

-- 1. Orders shipped before they were created (order header)
SELECT
  'orders_shipped_before_created' AS check_name,
  COUNTIF(shipped_at < created_at) AS failed_rows,
  COUNT(*) AS total_rows,
  ROUND(100 * COUNTIF(shipped_at < created_at) / COUNT(*), 2) AS pct_failed
FROM `bigquery-public-data.thelook_ecommerce.orders`
WHERE DATE(created_at) <= as_of_date
  AND shipped_at IS NOT NULL  -- an order that has not shipped cannot fail this check

UNION ALL

-- 2. Items shipped before they were created (item level)
-- This failed for about 30% of shipped items, so check 3 looks deeper.
SELECT
  'items_shipped_before_created',
  COUNTIF(shipped_at < created_at),
  COUNT(*),
  ROUND(100 * COUNTIF(shipped_at < created_at) / COUNT(*), 2)
FROM `bigquery-public-data.thelook_ecommerce.order_items`
WHERE DATE(created_at) <= as_of_date
  AND shipped_at IS NOT NULL

UNION ALL

-- 3. Items created outside the time window of their own order.
-- Check 2 pointed to item dates, so each item is compared with its order header.
-- Result: about 76% of items fall outside the window.
-- Conclusion: order header dates are the reliable reference for monthly figures.
SELECT
  'items_outside_order_window',
  COUNTIF(oi.created_at < o.created_at OR oi.created_at > o.shipped_at),
  COUNT(*),
  ROUND(100 * COUNTIF(oi.created_at < o.created_at OR oi.created_at > o.shipped_at) / COUNT(*), 2)
FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
JOIN `bigquery-public-data.thelook_ecommerce.orders` AS o
  USING (order_id)
WHERE DATE(o.created_at) <= as_of_date

UNION ALL

-- 4. Header item count differs from the number of item rows.
-- Tests whether the order header can be trusted as the reference.
SELECT
  'orders_item_count_mismatch',
  COUNTIF(COALESCE(i.n_items, 0) != o.num_of_item),
  COUNT(*),
  ROUND(100 * COUNTIF(COALESCE(i.n_items, 0) != o.num_of_item) / COUNT(*), 2)
FROM `bigquery-public-data.thelook_ecommerce.orders` AS o
LEFT JOIN (
  SELECT order_id, COUNT(*) AS n_items
  FROM `bigquery-public-data.thelook_ecommerce.order_items`
  GROUP BY order_id
) AS i
  USING (order_id)
WHERE DATE(o.created_at) <= as_of_date

UNION ALL

-- 5. Order items whose order does not exist (broken link)
SELECT
  'order_items_orphan_order',
  COUNTIF(o.order_id IS NULL),
  COUNT(*),
  ROUND(100 * COUNTIF(o.order_id IS NULL) / COUNT(*), 2)
FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
LEFT JOIN `bigquery-public-data.thelook_ecommerce.orders` AS o
  USING (order_id)
WHERE DATE(oi.created_at) <= as_of_date

UNION ALL

-- 6. Status and return date must agree: 'Returned' if and only if returned_at is set
SELECT
  'returned_status_mismatch',
  COUNTIF((status = 'Returned') != (returned_at IS NOT NULL)),
  COUNT(*),
  ROUND(100 * COUNTIF((status = 'Returned') != (returned_at IS NOT NULL)) / COUNT(*), 2)
FROM `bigquery-public-data.thelook_ecommerce.order_items`
WHERE DATE(created_at) <= as_of_date

UNION ALL

-- 7. Sale price missing, zero or negative
SELECT
  'sale_price_null_or_nonpositive',
  COUNTIF(sale_price IS NULL OR sale_price <= 0),
  COUNT(*),
  ROUND(100 * COUNTIF(sale_price IS NULL OR sale_price <= 0) / COUNT(*), 2)
FROM `bigquery-public-data.thelook_ecommerce.order_items`
WHERE DATE(created_at) <= as_of_date

UNION ALL

-- 8. Sale price more than 2x the list price.
-- The 2x threshold is an assumption. Some surcharges are legitimate, so this is a warning threshold, not proof of an error.
SELECT
  'sale_price_above_2x_retail',
  COUNTIF(oi.sale_price > 2 * p.retail_price),
  COUNT(*),
  ROUND(100 * COUNTIF(oi.sale_price > 2 * p.retail_price) / COUNT(*), 2)
FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
JOIN `bigquery-public-data.thelook_ecommerce.products` AS p
  ON oi.product_id = p.id
WHERE DATE(oi.created_at) <= as_of_date

UNION ALL

-- 9. Order items whose product is not in the catalog (broken link)
SELECT
  'order_items_orphan_product',
  COUNTIF(p.id IS NULL),
  COUNT(*),
  ROUND(100 * COUNTIF(p.id IS NULL) / COUNT(*), 2)
FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
LEFT JOIN `bigquery-public-data.thelook_ecommerce.products` AS p
  ON oi.product_id = p.id
WHERE DATE(oi.created_at) <= as_of_date

UNION ALL

-- 10. List price lower than cost (the product would sell at a loss)
SELECT
  'products_retail_below_cost',
  COUNTIF(retail_price < cost),
  COUNT(*),
  ROUND(100 * COUNTIF(retail_price < cost) / COUNT(*), 2)
FROM `bigquery-public-data.thelook_ecommerce.products`

UNION ALL

-- 11. Order items whose inventory record is missing (COGS would be lost)
SELECT
  'order_items_orphan_inventory',
  COUNTIF(ii.id IS NULL),
  COUNT(*),
  ROUND(100 * COUNTIF(ii.id IS NULL) / COUNT(*), 2)
FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
LEFT JOIN `bigquery-public-data.thelook_ecommerce.inventory_items` AS ii
  ON oi.inventory_item_id = ii.id
WHERE DATE(oi.created_at) <= as_of_date

UNION ALL

-- 12. Inventory cost missing or zero.
-- This checks the whole inventory table, not only sold items, because it is a property of the catalog. The COGS used in the analysis only covers sold items.
SELECT
  'inventory_cost_null_or_nonpositive',
  COUNTIF(cost IS NULL OR cost <= 0),
  COUNT(*),
  ROUND(100 * COUNTIF(cost IS NULL OR cost <= 0) / COUNT(*), 2)
FROM `bigquery-public-data.thelook_ecommerce.inventory_items`

UNION ALL

-- 13. Events dated before the user's signup date.
-- About 0.01% of events are affected. Most occur within the 3 hours before signup, which is consistent with browsing as a guest before creating an account.
-- These events are flagged, not deleted.
SELECT
  'events_before_user_signup',
  COUNTIF(u.id IS NOT NULL AND e.created_at < u.created_at),
  COUNTIF(u.id IS NOT NULL),
  ROUND(100 * COUNTIF(u.id IS NOT NULL AND e.created_at < u.created_at)
        / NULLIF(COUNTIF(u.id IS NOT NULL), 0), 2)
FROM `bigquery-public-data.thelook_ecommerce.events` AS e
LEFT JOIN `bigquery-public-data.thelook_ecommerce.users` AS u
  ON e.user_id = u.id
WHERE DATE(e.created_at) <= as_of_date

UNION ALL

-- 14. Orders dated before the user's signup date.
-- Result: 0. Every order has a user, and no order precedes its user.
SELECT
  'orders_before_user_signup',
  COUNTIF(u.id IS NOT NULL AND o.created_at < u.created_at),
  COUNTIF(u.id IS NOT NULL),
  ROUND(100 * COUNTIF(u.id IS NOT NULL AND o.created_at < u.created_at)
        / NULLIF(COUNTIF(u.id IS NOT NULL), 0), 2)
FROM `bigquery-public-data.thelook_ecommerce.orders` AS o
LEFT JOIN `bigquery-public-data.thelook_ecommerce.users` AS u
  ON o.user_id = u.id
WHERE DATE(o.created_at) <= as_of_date

UNION ALL

-- 15. Duplicate keys in order items.
-- Duplicates would inflate revenue and unit counts, so this must be zero.
SELECT
  'duplicate_order_items_id',
  COUNT(*) - COUNT(DISTINCT id),
  COUNT(*),
  ROUND(100 * (COUNT(*) - COUNT(DISTINCT id)) / COUNT(*), 2)
FROM `bigquery-public-data.thelook_ecommerce.order_items`
WHERE DATE(created_at) <= as_of_date

UNION ALL

-- 16. Duplicate keys in orders.
SELECT
  'duplicate_orders_id',
  COUNT(*) - COUNT(DISTINCT order_id),
  COUNT(*),
  ROUND(100 * (COUNT(*) - COUNT(DISTINCT order_id)) / COUNT(*), 2)
FROM `bigquery-public-data.thelook_ecommerce.orders`
WHERE DATE(created_at) <= as_of_date;



-- A2. REUSABLE BASE: completed order items
--
-- One definition of a "completed sale", used by every later query.
--   - status = 'Complete' and returned_at IS NULL (the case's definition)
--   - date = orders.created_at, because item dates failed checks 2-3
--   - cutoff = 2026-09-30 (written here because views cannot use DECLARE)
--   - COGS = inventory_items.cost of the item actually sold (the case's rule)
--
-- Inner joins are safe here: checks 5, 9 and 11 found no broken links.

CREATE OR REPLACE VIEW `peek-data-case.analysis.completed_order_items` AS
SELECT
  oi.id AS order_item_id,
  oi.order_id,
  o.user_id,
  oi.product_id,
  oi.inventory_item_id,
  o.created_at AS order_created_at,
  DATE_TRUNC(DATE(o.created_at), MONTH) AS month,   -- month comes from the order header
  oi.sale_price,
  ii.cost AS cogs
FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
JOIN `bigquery-public-data.thelook_ecommerce.orders` AS o
  USING (order_id)
JOIN `bigquery-public-data.thelook_ecommerce.inventory_items` AS ii
  ON oi.inventory_item_id = ii.id
WHERE oi.status = 'Complete'
  AND oi.returned_at IS NULL
  AND DATE(o.created_at) <= DATE '2026-09-30';




-- A3. MONTHLY BUSINESS HEALTH
--
-- One row per complete month.
-- Revenue, gross profit, orders, units and AOV come from the base view.
-- Session conversion comes from events, so it is calculated separately and joined by month.
--
-- Known limitation: the case defines conversion as sessions with a 'purchase'event divided by sessions with a 'department' event. 
-- A 'purchase' event is a click on "buy", not a completed order, so this rate is higher than a true order conversion (about 74% in September 2026). 
-- It is reported with its definition and is not used as a headline figure.

WITH sales AS (
  SELECT
    month,
    SUM(sale_price) AS revenue,
    SUM(sale_price - cogs) AS gross_profit,
    COUNT(DISTINCT order_id) AS orders,   -- distinct orders: one order can have many items
    COUNT(*) AS units                     -- one row per item sold
  FROM `peek-data-case.analysis.completed_order_items`
  GROUP BY month
),

sessions AS (
  SELECT
    DATE_TRUNC(DATE(created_at), MONTH) AS month,
    COUNT(DISTINCT IF(event_type = 'department', session_id, NULL)) AS department_sessions,
    COUNT(DISTINCT IF(event_type = 'purchase', session_id, NULL)) AS purchase_sessions
  FROM `bigquery-public-data.thelook_ecommerce.events`
  WHERE DATE(created_at) <= as_of_date
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
  -- MoM growth: this month vs. the previous month, using a window ordered by month
  ROUND(100 * SAFE_DIVIDE(s.revenue - LAG(s.revenue) OVER w, LAG(s.revenue) OVER w), 2) AS revenue_mom_growth_pct,
  ROUND(100 * SAFE_DIVIDE(c.purchase_sessions, c.department_sessions), 2) AS session_conversion_rate,
  s.orders < low_volume_threshold AS is_low_volume
FROM sales AS s
LEFT JOIN sessions AS c
  USING (month)
WINDOW w AS (ORDER BY s.month)
ORDER BY s.month;



-- A3 (supporting analysis). ORDER ATTRIBUTION TO A PURCHASE EVENT, BY YEAR
--
-- Purpose: the conversion above counts clicks, not orders. To measure how many orders can be linked to a purchase click, each order is matched to a purchase event from the same user in the 6 hours before the order.
-- Result: about 80% of orders match in every year, so the rate is stable. 
-- A 24-hour window gave almost the same result, so the 6-hour window is kept.

WITH orders_base AS (
  SELECT order_id, user_id, created_at AS order_at
  FROM `bigquery-public-data.thelook_ecommerce.orders`
  WHERE DATE(created_at) <= as_of_date
),

purchase_events AS (
  SELECT user_id, created_at AS event_at
  FROM `bigquery-public-data.thelook_ecommerce.events`
  WHERE event_type = 'purchase'
),

matched AS (
  -- one row per order, so the join cannot create duplicates when an order has several clicks
  SELECT
    o.order_id,
    o.order_at,
    MAX(IF(p.event_at IS NOT NULL, 1, 0)) AS has_purchase_event
  FROM orders_base AS o
  LEFT JOIN purchase_events AS p
    ON p.user_id = o.user_id
    AND p.event_at BETWEEN TIMESTAMP_SUB(o.order_at, INTERVAL 6 HOUR) AND o.order_at
  GROUP BY o.order_id, o.order_at
)

SELECT
  EXTRACT(YEAR FROM order_at) AS year,
  COUNT(*) AS orders_total,
  COUNTIF(has_purchase_event = 1) AS orders_matched,
  ROUND(100 * COUNTIF(has_purchase_event = 1) / COUNT(*), 1) AS pct_matched
FROM matched
GROUP BY year
ORDER BY year;


-- B1. NEW VS. RETURNING CUSTOMERS
--
-- Definitions:
--   New customer in a month: their first completed order falls in that month.
--   Returning customer in a month: they have an order that month, and their first order was in an earlier month.
--   A customer with several orders in one month is counted once.
--   Revenue follows the customer's status: all orders of a new customer in their first month are counted in revenue_new.
--
-- Thefirst month of the dataset (January 2019) shows 100% new customers only because there is no earlier history.

WITH first_orders AS ( 
  SELECT
    user_id,
    DATE_TRUNC(DATE(MIN(order_created_at)), MONTH) AS first_order_month
  FROM `peek-data-case.analysis.completed_order_items`
  GROUP BY user_id
),

base AS (
  SELECT
    c.month,
    c.user_id,
    c.sale_price,
    c.month = f.first_order_month AS is_new_month
  FROM `peek-data-case.analysis.completed_order_items` AS c
  JOIN first_orders AS f
    USING (user_id)
)

SELECT
  month,
  COUNT(DISTINCT user_id) AS active_customers,
  COUNT(DISTINCT IF(is_new_month, user_id, NULL)) AS new_customers,
  COUNT(DISTINCT IF(NOT is_new_month, user_id, NULL)) AS returning_customers,
  ROUND(SUM(IF(is_new_month, sale_price, 0)), 2) AS revenue_new,
  ROUND(SUM(IF(NOT is_new_month, sale_price, 0)), 2) AS revenue_returning,
  ROUND(100 * SAFE_DIVIDE(SUM(IF(NOT is_new_month, sale_price, 0)), SUM(sale_price)), 2) AS pct_revenue_from_returning
FROM base
GROUP BY month
ORDER BY month;



-- B2. 90-DAY CHURN
--
-- Definitions:
--   Active in month M: at least one completed order in M.
--   Churned (90 days): no completed order in the 90 days after the end of M.
--   Mature: the 90-day window closes on or before the cutoff. Only mature months have a valid churn rate.
--   Recent months are censored: the outcome is not yet known, so these customers are excluded, not counted as churn.
--
-- Known limitations:
--   90 days is the window defined in the case, not calibrated to purchase cycles.
--   Counts customers, not revenue: a high-volume buyer weighs the same as a one-time buyer.
--   A customer who returns after the window closes is still counted as churn.

WITH active AS (
  SELECT DISTINCT user_id, month
  FROM `peek-data-case.analysis.completed_order_items`
),

windowed AS (
  SELECT
    user_id,
    month,
    LAST_DAY(month) AS month_end,
    DATE_ADD(LAST_DAY(month), INTERVAL 90 DAY) AS window_end
  FROM active
),

flagged AS (
  SELECT
    w.user_id,
    w.month,
    w.window_end <= as_of_date AS is_mature,
    NOT EXISTS (
      SELECT 1
      FROM `peek-data-case.analysis.completed_order_items` AS c
      WHERE c.user_id = w.user_id
        AND DATE(c.order_created_at) > w.month_end
        AND DATE(c.order_created_at) <= w.window_end
    ) AS is_churn
  FROM windowed AS w
)

SELECT
  month,
  COUNT(*) AS active_customers,
  COUNTIF(is_mature) AS mature_customers,
  COUNTIF(is_mature AND is_churn) AS churned_customers_90d,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(is_mature AND is_churn), COUNTIF(is_mature)), 2) AS churn_rate_90d,
  COUNTIF(is_mature) > 0 AS has_mature_data
FROM flagged
GROUP BY month
ORDER BY month;
