-- Portfolio-ready analysis queries for the Online Retail II cohort project.
-- Run after sql/cohort_analysis_mysql.sql has completed.

USE retail_analysis;

-- 1. Cleaning audit
SELECT *
FROM cleaning_summary
ORDER BY issue;

-- 2. Cohort sizes by first purchase month
SELECT
    cohort_month,
    cohort_size
FROM cohort_retention
WHERE month_number = 0
ORDER BY cohort_month;

-- 3. Month 1 retention by cohort
SELECT
    cohort_month,
    active_customers,
    cohort_size,
    retention_rate
FROM cohort_retention
WHERE month_number = 1
ORDER BY cohort_month;

-- 4. Month 3 retention by cohort
SELECT
    cohort_month,
    active_customers,
    cohort_size,
    retention_rate
FROM cohort_retention
WHERE month_number = 3
ORDER BY cohort_month;

-- 5. Average retention curve across all cohorts
SELECT
    month_number,
    ROUND(AVG(retention_rate), 4) AS avg_retention_rate,
    ROUND(AVG(revenue_per_customer), 2) AS avg_revenue_per_customer,
    ROUND(AVG(orders_per_customer), 2) AS avg_orders_per_customer
FROM cohort_retention
GROUP BY month_number
ORDER BY month_number;

-- 6. Best and worst cohorts at month 1
SELECT
    cohort_month,
    retention_rate
FROM cohort_retention
WHERE month_number = 1
ORDER BY retention_rate DESC;

-- 7. Best and worst cohorts at month 3
SELECT
    cohort_month,
    retention_rate
FROM cohort_retention
WHERE month_number = 3
ORDER BY retention_rate DESC;

-- 8. Revenue concentration: top decile vs everyone
SELECT
    segment,
    total_revenue,
    ROUND(total_revenue / SUM(total_revenue) OVER (), 4) AS revenue_share
FROM (
    SELECT
        'top_10_percent' AS segment,
        SUM(lifetime_revenue) AS total_revenue
    FROM top_10_percent_customers
    UNION ALL
    SELECT
        'remaining_90_percent' AS segment,
        SUM(lifetime_revenue) AS total_revenue
    FROM customer_lifetime_value
    WHERE customer_id NOT IN (
        SELECT customer_id
        FROM top_10_percent_customers
    )
) revenue_split;

-- 9. Summary profile of top-decile customers
SELECT
    COUNT(*) AS top_customer_count,
    ROUND(AVG(lifetime_revenue), 2) AS avg_lifetime_revenue,
    ROUND(AVG(lifetime_orders), 2) AS avg_lifetime_orders,
    ROUND(AVG(active_months), 2) AS avg_active_months,
    MIN(lifetime_revenue) AS min_lifetime_revenue,
    MAX(lifetime_revenue) AS max_lifetime_revenue
FROM top_10_percent_customers;

-- 10. Top products purchased by top-decile customers
SELECT
    description,
    units_sold,
    orders,
    revenue
FROM top_10_percent_product_mix
ORDER BY revenue DESC
LIMIT 20;

-- 11. Countries contributing most revenue in cleaned transactions
SELECT
    country,
    COUNT(DISTINCT customer_id) AS customers,
    COUNT(DISTINCT invoice_no) AS orders,
    ROUND(SUM(line_revenue), 2) AS total_revenue
FROM cleaned_transactions
GROUP BY country
ORDER BY total_revenue DESC
LIMIT 15;

-- 12. Repeat purchase rate by cohort
-- Repeat purchaser = customer with more than one lifetime order.
SELECT
    cohort_month,
    COUNT(*) AS cohort_customers,
    SUM(CASE WHEN lifetime_orders > 1 THEN 1 ELSE 0 END) AS repeat_customers,
    ROUND(SUM(CASE WHEN lifetime_orders > 1 THEN 1 ELSE 0 END) / COUNT(*), 4) AS repeat_purchase_rate
FROM customer_lifetime_value
GROUP BY cohort_month
ORDER BY cohort_month;

-- 13. Average time between first and last observed purchase by cohort
SELECT
    f.cohort_month,
    ROUND(AVG(TIMESTAMPDIFF(DAY, customer_span.first_purchase_ts, customer_span.last_purchase_ts)), 1) AS avg_customer_lifespan_days
FROM (
    SELECT
        customer_id,
        MIN(invoice_ts) AS first_purchase_ts,
        MAX(invoice_ts) AS last_purchase_ts
    FROM cleaned_transactions
    GROUP BY customer_id
) customer_span
JOIN customer_first_purchase f
  ON customer_span.customer_id = f.customer_id
GROUP BY f.cohort_month
ORDER BY f.cohort_month;

-- 14. Monthly sales trend in the cleaned dataset
SELECT
    DATE_FORMAT(invoice_ts, '%Y-%m-01') AS sales_month,
    COUNT(DISTINCT invoice_no) AS orders,
    COUNT(DISTINCT customer_id) AS customers,
    ROUND(SUM(line_revenue), 2) AS total_revenue,
    ROUND(AVG(line_revenue), 2) AS avg_line_revenue
FROM cleaned_transactions
GROUP BY DATE_FORMAT(invoice_ts, '%Y-%m-01')
ORDER BY sales_month;
