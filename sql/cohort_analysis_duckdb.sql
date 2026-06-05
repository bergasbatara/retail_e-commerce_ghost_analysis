-- Online Retail II cohort and churn analysis in DuckDB.
-- Run with: duckdb retail_analysis.duckdb < sql/cohort_analysis_duckdb.sql

CREATE OR REPLACE TABLE raw_online_retail AS
SELECT
    CAST(Invoice AS VARCHAR) AS invoice_no,
    TRIM(CAST(StockCode AS VARCHAR)) AS stock_code,
    TRIM(CAST(Description AS VARCHAR)) AS description,
    CAST(Quantity AS INTEGER) AS quantity,
    CAST(InvoiceDate AS TIMESTAMP) AS invoice_ts,
    CAST(Price AS DECIMAL(18,2)) AS unit_price,
    CAST(CAST("Customer ID" AS DOUBLE) AS BIGINT) AS customer_id,
    TRIM(CAST(Country AS VARCHAR)) AS country
FROM read_csv_auto('online_retail_II.csv', header = true);

CREATE OR REPLACE VIEW cleaned_transactions AS
SELECT DISTINCT
    invoice_no,
    stock_code,
    description,
    quantity,
    invoice_ts,
    unit_price,
    customer_id,
    country,
    quantity * unit_price AS line_revenue
FROM raw_online_retail
WHERE customer_id IS NOT NULL
  AND quantity > 0
  AND unit_price > 0
  AND invoice_no NOT LIKE 'C%'
  AND stock_code NOT IN ('POST', 'D', 'M', 'BANK CHARGES');

CREATE OR REPLACE TABLE customer_first_purchase AS
SELECT
    customer_id,
    DATE_TRUNC('month', MIN(invoice_ts)) AS cohort_month,
    MIN(invoice_ts) AS first_purchase_ts
FROM cleaned_transactions
GROUP BY 1;

CREATE OR REPLACE TABLE monthly_customer_activity AS
SELECT
    t.customer_id,
    f.cohort_month,
    DATE_TRUNC('month', t.invoice_ts) AS activity_month,
    DATE_DIFF('month', f.cohort_month, DATE_TRUNC('month', t.invoice_ts)) AS month_number,
    COUNT(DISTINCT t.invoice_no) AS order_count,
    SUM(t.line_revenue) AS revenue
FROM cleaned_transactions t
JOIN customer_first_purchase f
  ON t.customer_id = f.customer_id
GROUP BY 1, 2, 3, 4;

CREATE OR REPLACE TABLE cohort_retention AS
WITH cohort_sizes AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_id) AS cohort_size
    FROM customer_first_purchase
    GROUP BY 1
)
SELECT
    a.cohort_month,
    a.month_number,
    c.cohort_size,
    COUNT(DISTINCT a.customer_id) AS active_customers,
    ROUND(COUNT(DISTINCT a.customer_id) * 1.0 / c.cohort_size, 4) AS retention_rate,
    SUM(a.revenue) AS cohort_revenue,
    ROUND(SUM(a.revenue) * 1.0 / c.cohort_size, 2) AS revenue_per_customer,
    ROUND(SUM(a.order_count) * 1.0 / c.cohort_size, 2) AS orders_per_customer
FROM monthly_customer_activity a
JOIN cohort_sizes c
  ON a.cohort_month = c.cohort_month
GROUP BY 1, 2, 3
ORDER BY 1, 2;

CREATE OR REPLACE TABLE customer_lifetime_value AS
SELECT
    customer_id,
    MIN(cohort_month) AS cohort_month,
    COUNT(DISTINCT invoice_no) AS lifetime_orders,
    SUM(line_revenue) AS lifetime_revenue,
    COUNT(DISTINCT DATE_TRUNC('month', invoice_ts)) AS active_months
FROM cleaned_transactions t
JOIN customer_first_purchase f
  USING (customer_id)
GROUP BY 1;

CREATE OR REPLACE TABLE top_10_percent_customers AS
WITH ranked_customers AS (
    SELECT
        customer_id,
        cohort_month,
        lifetime_orders,
        lifetime_revenue,
        active_months,
        NTILE(10) OVER (ORDER BY lifetime_revenue DESC) AS revenue_decile
    FROM customer_lifetime_value
)
SELECT *
FROM ranked_customers
WHERE revenue_decile = 1
ORDER BY lifetime_revenue DESC;

CREATE OR REPLACE TABLE top_10_percent_product_mix AS
SELECT
    t.stock_code,
    t.description,
    SUM(t.quantity) AS units_sold,
    COUNT(DISTINCT t.invoice_no) AS orders,
    ROUND(SUM(t.line_revenue), 2) AS revenue
FROM cleaned_transactions t
JOIN top_10_percent_customers c
  USING (customer_id)
GROUP BY 1, 2
ORDER BY revenue DESC, units_sold DESC;

CREATE OR REPLACE TABLE cleaning_summary AS
WITH raw_counts AS (
    SELECT COUNT(*) AS raw_rows FROM raw_online_retail
),
clean_counts AS (
    SELECT COUNT(*) AS cleaned_rows FROM cleaned_transactions
),
issues AS (
    SELECT 'missing_customer_id' AS issue, COUNT(*) AS affected_rows
    FROM raw_online_retail
    WHERE customer_id IS NULL
    UNION ALL
    SELECT 'cancel_invoice_prefix_c', COUNT(*)
    FROM raw_online_retail
    WHERE invoice_no LIKE 'C%'
    UNION ALL
    SELECT 'non_positive_quantity', COUNT(*)
    FROM raw_online_retail
    WHERE quantity <= 0
    UNION ALL
    SELECT 'non_positive_unit_price', COUNT(*)
    FROM raw_online_retail
    WHERE unit_price <= 0
    UNION ALL
    SELECT 'non_product_stock_codes', COUNT(*)
    FROM raw_online_retail
    WHERE stock_code IN ('POST', 'D', 'M', 'BANK CHARGES')
)
SELECT * FROM issues
UNION ALL
SELECT 'raw_rows', raw_rows FROM raw_counts
UNION ALL
SELECT 'cleaned_rows', cleaned_rows FROM clean_counts;

COPY (
    SELECT * FROM cleaned_transactions
) TO 'output/cleaned_transactions.csv' (HEADER, DELIMITER ',');

COPY (
    SELECT * FROM cohort_retention
) TO 'output/cohort_retention.csv' (HEADER, DELIMITER ',');

COPY (
    SELECT * FROM top_10_percent_customers
) TO 'output/top_10_percent_customers.csv' (HEADER, DELIMITER ',');

COPY (
    SELECT * FROM top_10_percent_product_mix
) TO 'output/top_10_percent_product_mix.csv' (HEADER, DELIMITER ',');
