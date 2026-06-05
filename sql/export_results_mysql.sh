#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/output"
MYSQL_BIN="/opt/homebrew/opt/mysql@8.4/bin/mysql"
DB_NAME="${1:-retail_analysis}"

mkdir -p "$OUT_DIR"

"$MYSQL_BIN" -u root -D "$DB_NAME" --batch --raw -e "SELECT * FROM raw_online_retail LIMIT 1000" > "$OUT_DIR/raw_online_retail_sample.tsv"
"$MYSQL_BIN" -u root -D "$DB_NAME" --batch --raw -e "SELECT * FROM cleaned_transactions" > "$OUT_DIR/cleaned_transactions.tsv"
"$MYSQL_BIN" -u root -D "$DB_NAME" --batch --raw -e "SELECT * FROM customer_first_purchase ORDER BY cohort_month, customer_id" > "$OUT_DIR/customer_first_purchase.tsv"
"$MYSQL_BIN" -u root -D "$DB_NAME" --batch --raw -e "SELECT * FROM monthly_customer_activity ORDER BY cohort_month, month_number, customer_id" > "$OUT_DIR/monthly_customer_activity.tsv"
"$MYSQL_BIN" -u root -D "$DB_NAME" --batch --raw -e "SELECT * FROM cohort_sizes ORDER BY cohort_month" > "$OUT_DIR/cohort_sizes.tsv"
"$MYSQL_BIN" -u root -D "$DB_NAME" --batch --raw -e "SELECT * FROM cohort_retention ORDER BY cohort_month, month_number" > "$OUT_DIR/cohort_retention.tsv"
"$MYSQL_BIN" -u root -D "$DB_NAME" --batch --raw -e "SELECT * FROM customer_lifetime_value ORDER BY lifetime_revenue DESC" > "$OUT_DIR/customer_lifetime_value.tsv"
"$MYSQL_BIN" -u root -D "$DB_NAME" --batch --raw -e "SELECT * FROM top_10_percent_customers ORDER BY lifetime_revenue DESC" > "$OUT_DIR/top_10_percent_customers.tsv"
"$MYSQL_BIN" -u root -D "$DB_NAME" --batch --raw -e "SELECT * FROM top_10_percent_product_mix ORDER BY revenue DESC" > "$OUT_DIR/top_10_percent_product_mix.tsv"
"$MYSQL_BIN" -u root -D "$DB_NAME" --batch --raw -e "SELECT * FROM cleaning_summary ORDER BY issue" > "$OUT_DIR/cleaning_summary.tsv"

"$MYSQL_BIN" -u root "$DB_NAME" --batch --raw < "$ROOT_DIR/sql/analysis_queries_mysql.sql" > "$OUT_DIR/analysis_queries_output.tsv"
