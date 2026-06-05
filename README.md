# E-Commerce Cohort and Churn Analysis

This project uses `online_retail_II.csv` to answer a core retention question:

Are we keeping the customers we acquire, and how does their value change after their first purchase month?

## Dataset issues confirmed in this file

The raw file has `1,067,371` rows. Quick profiling on the local CSV found:

- `243,007` rows (`22.77%`) with missing `Customer ID`
- `19,494` rows with cancellation invoices starting with `C`
- `22,950` rows with `Quantity <= 0`
- `6,207` rows with `Price <= 0`
- `34,335` exact duplicate rows
- Known non-product stock codes such as `POST`, `D`, `M`, and `BANK CHARGES`

Those issues are the reason cohort logic needs a cleaning layer before Tableau or Power BI touches the data.

## Recommended workflow

Use MySQL 8 first if you want traditional SQL practice and plan to discuss table design plus import steps in your project write-up.

Run the MySQL pipeline from [sql/cohort_analysis_mysql.sql](/Users/bergasanargya/retail_e-commerce_ghost_analysis/sql/cohort_analysis_mysql.sql:1).

Typical setup:

```sql
CREATE DATABASE retail_analysis;
USE retail_analysis;
SET GLOBAL local_infile = 1;
```

Then run:

```bash
mysql --local-infile=1 -u <user> -p retail_analysis < sql/cohort_analysis_mysql.sql
```

This script will create:

- `cleaned_transactions`
- `customer_first_purchase`
- `monthly_customer_activity`
- `cohort_retention`
- `customer_lifetime_value`
- `top_10_percent_customers`
- `top_10_percent_product_mix`
- `cleaning_summary`

If `LOAD DATA LOCAL INFILE` is blocked in your MySQL setup, import `online_retail_II.csv` through MySQL Workbench into `raw_online_retail`, then run the rest of the script from the `cleaned_transactions` section onward.

## Exporting result sets into this folder

The simplest local export method is to use the MySQL client in batch mode and redirect the output into files in this repo.

Examples:

```bash
cd /Users/bergasanargya/retail_e-commerce_ghost_analysis
mkdir -p output
mysql -u root -D retail_analysis --batch --raw -e "SELECT * FROM cleaning_summary" > output/cleaning_summary.tsv
mysql -u root -D retail_analysis --batch --raw -e "SELECT * FROM cohort_retention ORDER BY cohort_month, month_number" > output/cohort_retention.tsv
mysql -u root -D retail_analysis --batch --raw -e "SELECT * FROM top_10_percent_customers ORDER BY lifetime_revenue DESC" > output/top_10_percent_customers.tsv
mysql -u root -D retail_analysis --batch --raw -e "SELECT * FROM top_10_percent_product_mix ORDER BY revenue DESC" > output/top_10_percent_product_mix.tsv
```

If you want comma-separated files instead of tab-separated output:

```bash
mysql -u root -D retail_analysis --batch --raw -e "SELECT cohort_month, month_number, cohort_size, active_customers, retention_rate, cohort_revenue, revenue_per_customer, orders_per_customer FROM cohort_retention ORDER BY cohort_month, month_number" | sed 's/\t/,/g' > output/cohort_retention.csv
```

You can also run the portfolio analysis query pack:

```bash
mysql -u root retail_analysis < sql/analysis_queries_mysql.sql
```

## Optional DuckDB path

DuckDB is still included as a simpler local alternative because it can query the CSV directly and export flat files without a database server.

```bash
mkdir -p output
duckdb retail_analysis.duckdb < sql/cohort_analysis_duckdb.sql
```

## SQL logic

The cleaning view applies the three business rules you listed:

- Drop ghost customers: `customer_id IS NOT NULL`
- Exclude returns/cancellations: `quantity > 0`, `unit_price > 0`, `invoice_no NOT LIKE 'C%'`
- Exclude non-product activity: `stock_code NOT IN ('POST', 'D', 'M', 'BANK CHARGES')`

`SELECT DISTINCT` is used in the cleaned layer to remove exact duplicate transaction rows.

The MySQL script also includes:

- a raw staging table: `raw_online_retail`
- a `LOAD DATA LOCAL INFILE` import step
- cohort calculations using `DATE_FORMAT()` and `TIMESTAMPDIFF()`
- top-decile customer ranking using `NTILE(10)`

## Tableau build

### 1. Cohort retention heatmap

Connect Tableau to `output/cohort_retention.csv`.

Use these fields:

- Rows: `cohort_month`
- Columns: `month_number`
- Text/Color: `retention_rate`

Format:

- Set `cohort_month` to discrete month
- Format `retention_rate` as percentage
- Use a sequential color scale

This gives you the month `0, 1, 2...` retention heatmap for each acquisition cohort.

### 2. Cohort LTV trend

Use the same `cohort_retention.csv`.

Fields:

- Rows: `revenue_per_customer`
- Columns: `month_number`
- Color: `cohort_month`

This shows how average revenue per acquired customer evolves over time by cohort.

### 3. Top 10% customer analysis

Connect Tableau to:

- `output/top_10_percent_customers.csv`
- `output/top_10_percent_product_mix.csv`

Suggested views:

- Bar chart of top customers by `lifetime_revenue`
- Product mix chart using `description` by `revenue`
- Optional Pareto chart comparing top decile revenue vs remaining customer base

## Deliverables mapping

Your requested weekend deliverables map directly to these outputs:

1. Cleaned dataset
   - `output/cleaned_transactions.csv`
2. Cohort heatmap
   - built in Tableau from `output/cohort_retention.csv`
3. Top 10% customer revenue and buying behavior
   - `output/top_10_percent_customers.csv`
   - `output/top_10_percent_product_mix.csv`

## What to say in the project narrative

Frame the project around business impact:

- Customer acquisition is only valuable if cohorts repeat purchase after month 0.
- Retention is measured only on real shopping events, not returns or admin rows.
- Revenue concentration matters because e-commerce revenue is usually driven by a small customer segment.

A concise case-study structure:

1. Define the retention question
2. Clean the raw transaction log
3. Build first-purchase cohorts
4. Measure month-over-month active customers and revenue per acquired customer
5. Identify top-decile customers and their product preferences

## Next step

If you want, I can add a second script for PostgreSQL/BigQuery syntax or generate a Tableau dashboard outline with sheet-by-sheet titles and calculated fields.
