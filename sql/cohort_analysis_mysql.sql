-- Online Retail II cohort and churn analysis in MySQL 8.0+.
-- Assumes you are connected to the target database first.
--
-- Typical run order:
-- 1. Create the database if needed:
--    CREATE DATABASE retail_analysis;
--    USE retail_analysis;
-- 2. If your MySQL server allows local infile:
--    SET GLOBAL local_infile = 1;
-- 3. Load the CSV from your local machine:
--    mysql --local-infile=1 -u <user> -p retail_analysis < sql/cohort_analysis_mysql.sql
--
-- If LOAD DATA LOCAL INFILE is disabled by policy, import the CSV with MySQL Workbench
-- or enable local_infile on both client and server.

DROP TABLE IF EXISTS raw_online_retail;
CREATE TABLE raw_online_retail (
    row_id BIGINT NOT NULL AUTO_INCREMENT,
    invoice_no VARCHAR(20),
    stock_code VARCHAR(20),
    description VARCHAR(255),
    quantity INT,
    invoice_ts DATETIME,
    unit_price DECIMAL(10,2),
    customer_id BIGINT NULL,
    country VARCHAR(100),
    PRIMARY KEY (row_id),
    KEY idx_customer_id (customer_id),
    KEY idx_invoice_ts (invoice_ts),
    KEY idx_invoice_no (invoice_no),
    KEY idx_stock_code (stock_code)
);

LOAD DATA LOCAL INFILE '/Users/bergasanargya/retail_e-commerce_ghost_analysis/online_retail_II.csv'
INTO TABLE raw_online_retail
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    @invoice_no,
    @stock_code,
    @description,
    @quantity,
    @invoice_date,
    @unit_price,
    @customer_id,
    @country
)
SET
    invoice_no = NULLIF(TRIM(@invoice_no), ''),
    stock_code = NULLIF(TRIM(@stock_code), ''),
    description = NULLIF(TRIM(@description), ''),
    quantity = NULLIF(TRIM(@quantity), ''),
    invoice_ts = STR_TO_DATE(TRIM(@invoice_date), '%Y-%m-%d %H:%i:%s'),
    unit_price = NULLIF(TRIM(@unit_price), ''),
    customer_id = CASE
        WHEN NULLIF(TRIM(@customer_id), '') IS NULL THEN NULL
        ELSE CAST(TRIM(TRAILING '.0' FROM TRIM(@customer_id)) AS UNSIGNED)
    END,
    country = NULLIF(TRIM(@country), '');

DROP TABLE IF EXISTS cleaned_transactions;
CREATE TABLE cleaned_transactions AS
SELECT invoice_no,
       stock_code,
       description,
       quantity,
       invoice_ts,
       unit_price,
       customer_id,
       country,
       quantity * unit_price AS line_revenue
FROM (
    SELECT DISTINCT
        invoice_no,
        stock_code,
        description,
        quantity,
        invoice_ts,
        unit_price,
        customer_id,
        country
    FROM raw_online_retail
    WHERE customer_id IS NOT NULL
      AND quantity > 0
      AND unit_price > 0
      AND invoice_no NOT LIKE 'C%'
      AND stock_code NOT IN ('POST', 'D', 'M', 'BANK CHARGES')
) deduped;

ALTER TABLE cleaned_transactions
    ADD KEY idx_clean_customer_id (customer_id),
    ADD KEY idx_clean_invoice_ts (invoice_ts),
    ADD KEY idx_clean_invoice_no (invoice_no);

DROP TABLE IF EXISTS customer_first_purchase;
CREATE TABLE customer_first_purchase AS
SELECT
    customer_id,
    DATE_FORMAT(MIN(invoice_ts), '%Y-%m-01') AS cohort_month,
    MIN(invoice_ts) AS first_purchase_ts
FROM cleaned_transactions
GROUP BY customer_id;

ALTER TABLE customer_first_purchase
    ADD KEY idx_cohort_customer_id (customer_id),
    ADD KEY idx_cohort_month (cohort_month);

DROP TABLE IF EXISTS monthly_customer_activity;
CREATE TABLE monthly_customer_activity AS
SELECT
    t.customer_id,
    f.cohort_month,
    DATE_FORMAT(t.invoice_ts, '%Y-%m-01') AS activity_month,
    TIMESTAMPDIFF(
        MONTH,
        STR_TO_DATE(f.cohort_month, '%Y-%m-%d'),
        STR_TO_DATE(DATE_FORMAT(t.invoice_ts, '%Y-%m-01'), '%Y-%m-%d')
    ) AS month_number,
    COUNT(DISTINCT t.invoice_no) AS order_count,
    ROUND(SUM(t.line_revenue), 2) AS revenue
FROM cleaned_transactions t
JOIN customer_first_purchase f
  ON t.customer_id = f.customer_id
GROUP BY
    t.customer_id,
    f.cohort_month,
    DATE_FORMAT(t.invoice_ts, '%Y-%m-01'),
    TIMESTAMPDIFF(
        MONTH,
        STR_TO_DATE(f.cohort_month, '%Y-%m-%d'),
        STR_TO_DATE(DATE_FORMAT(t.invoice_ts, '%Y-%m-01'), '%Y-%m-%d')
    );

ALTER TABLE monthly_customer_activity
    ADD KEY idx_monthly_cohort_month (cohort_month),
    ADD KEY idx_monthly_month_number (month_number),
    ADD KEY idx_monthly_customer_id (customer_id);

DROP TABLE IF EXISTS cohort_sizes;
CREATE TABLE cohort_sizes AS
SELECT
    cohort_month,
    COUNT(DISTINCT customer_id) AS cohort_size
FROM customer_first_purchase
GROUP BY cohort_month;

DROP TABLE IF EXISTS cohort_retention;
CREATE TABLE cohort_retention AS
SELECT
    a.cohort_month,
    a.month_number,
    c.cohort_size,
    COUNT(DISTINCT a.customer_id) AS active_customers,
    ROUND(COUNT(DISTINCT a.customer_id) / c.cohort_size, 4) AS retention_rate,
    ROUND(SUM(a.revenue), 2) AS cohort_revenue,
    ROUND(SUM(a.revenue) / c.cohort_size, 2) AS revenue_per_customer,
    ROUND(SUM(a.order_count) / c.cohort_size, 2) AS orders_per_customer
FROM monthly_customer_activity a
JOIN cohort_sizes c
  ON a.cohort_month = c.cohort_month
GROUP BY
    a.cohort_month,
    a.month_number,
    c.cohort_size
ORDER BY
    a.cohort_month,
    a.month_number;

DROP TABLE IF EXISTS customer_lifetime_value;
CREATE TABLE customer_lifetime_value AS
SELECT
    t.customer_id,
    f.cohort_month,
    COUNT(DISTINCT t.invoice_no) AS lifetime_orders,
    ROUND(SUM(t.line_revenue), 2) AS lifetime_revenue,
    COUNT(DISTINCT DATE_FORMAT(t.invoice_ts, '%Y-%m-01')) AS active_months
FROM cleaned_transactions t
JOIN customer_first_purchase f
  ON t.customer_id = f.customer_id
GROUP BY
    t.customer_id,
    f.cohort_month;

DROP TABLE IF EXISTS top_10_percent_customers;
CREATE TABLE top_10_percent_customers AS
SELECT
    customer_id,
    cohort_month,
    lifetime_orders,
    lifetime_revenue,
    active_months,
    revenue_decile
FROM (
    SELECT
        customer_id,
        cohort_month,
        lifetime_orders,
        lifetime_revenue,
        active_months,
        NTILE(10) OVER (ORDER BY lifetime_revenue DESC) AS revenue_decile
    FROM customer_lifetime_value
) ranked_customers
WHERE revenue_decile = 1
ORDER BY lifetime_revenue DESC;

DROP TABLE IF EXISTS top_10_percent_product_mix;
CREATE TABLE top_10_percent_product_mix AS
SELECT
    t.stock_code,
    t.description,
    SUM(t.quantity) AS units_sold,
    COUNT(DISTINCT t.invoice_no) AS orders,
    ROUND(SUM(t.line_revenue), 2) AS revenue
FROM cleaned_transactions t
JOIN top_10_percent_customers c
  ON t.customer_id = c.customer_id
GROUP BY
    t.stock_code,
    t.description
ORDER BY revenue DESC, units_sold DESC;

DROP TABLE IF EXISTS cleaning_summary;
CREATE TABLE cleaning_summary AS
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
UNION ALL
SELECT 'raw_rows', COUNT(*)
FROM raw_online_retail
UNION ALL
SELECT 'cleaned_rows', COUNT(*)
FROM cleaned_transactions;

-- Helpful exports for Tableau or Power BI. Run these manually if FILE privilege is enabled.
-- SELECT * FROM cohort_retention ORDER BY cohort_month, month_number;
-- SELECT * FROM top_10_percent_customers ORDER BY lifetime_revenue DESC;
-- SELECT * FROM top_10_percent_product_mix ORDER BY revenue DESC, units_sold DESC;
