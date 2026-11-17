# Movie Rental Data Warehouse (DL3004 Final Project)

An end-to-end data warehousing and BI project for a movie rental chain, built on the **Sakila** sample database (a DVD rental business with 2 stores, about 600 customers, 1,000 films and 16,000 rentals).

## Team

| Member | Roll No |
|---|---|
| Romaisa Sajjad | 24L-2608 |
| Zahra Saeed | 24L-2512 |
| Aima Shakeel | 24L-2531 |

## Pipeline

```
Sakila CSV files  ->  project_staging  ->  project_dw  ->  project_reporting  ->  Power BI
 (source files)       (load + clean)       (star schema)    (analysis views)       (dashboard)
```

## Data source

The source system is the Sakila sample database, PostgreSQL version from the public [jOOQ/sakila](https://github.com/jOOQ/sakila) repository (`postgres-sakila-db`). Each of its 15 tables was exported to CSV and saved in `02_Data/raw_data`. These files are the input to the ETL pipeline.

| Data | Rows |
|---|---|
| Rentals | 16,044 (24 May 2005 to 14 Feb 2006) |
| Payments | 16,049 (total 67,416.51) |
| Customers | 599 |
| Films | 1,000 |
| Inventory copies | 4,581 |
| Actors | 200 |

## Warehouse design

Star schema with 4 fact tables sharing 6 dimensions.

| Fact table | Type | Grain (one row = ...) |
|---|---|---|
| fact_rental | Transaction | one rental |
| fact_payment | Transaction | one payment |
| fact_inventory_daily | Periodic snapshot | one film, at one store, on one day |
| fact_film_cast | Factless | one actor in one film |

**Dimensions:** dim_date, dim_customer (SCD Type 2), dim_film, dim_store, dim_staff, dim_actor. Every dimension has a surrogate key and an Unknown row (key -1).

Full details are in `01_Project_Documentation`.

## Repository structure

```
01_Project_Documentation/
    Project_Proposal.pdf, Business_Requirements_Document.pdf, Business_Questions.pdf,
    Fact_and_Dimension_Identification.pdf, Grain_Definition_Document.pdf,
    Star_Schema_Design.pdf, Star_Schema.png, Star_Schema.dbml   Phase 1 design
    Data_Dictionary.xlsx                                       Tables, columns, rules
    Data_Cleaning_Report.pdf                                   Phase 2 cleaning results
    Data_Quality_Report.pdf                                    Phase 2 quality check results
    Business_Insights_Report.pdf                               Phase 3 findings and recommendations
02_Data/
    raw_data/               Sakila tables exported as CSV (source files)
    cleaned_data/           Cleaned staging tables exported as CSV (stg_<table>.csv)
03_ETL/
    load_staging.py         Loads the CSV files into project_staging.raw_<table>
    staging.sql             Cleans raw_ tables into typed project_staging.stg_<table>
    export_cleaned.py       Exports the stg_ tables to 02_Data/cleaned_data (optional)
    dimensions.sql          Loads the 6 dimensions (Unknown rows, dim_date, SCD2 baseline)
    facts.sql               SCD2 customer changes and the 4 fact table loads
    checks.sql              Data quality and reconciliation checks (31 checks)
04_Data_Warehouse/
    warehouse.sql           Creates project_dw (6 dimensions, 4 facts, keys, indexes)
                            and the project_reporting schema
05_Analytics/
    Views.sql               Reporting views in project_reporting (run this first)
    Analytical_Queries.sql  Answers to the 14 business questions
    OLAP.sql                OLAP queries with ROLLUP and CUBE
06_Dashboard/
    PowerBI.pbix            Power BI dashboard (Phase 3)
README.md
```

## Tools

PostgreSQL, pgAdmin, Python (Pandas, SQLAlchemy), Power BI Desktop, dbdiagram.io, GitHub.

## Project status

| Phase | Weeks | Content | Status |
|---|---|---|---|
| 1. Design | 1-3 | Business analysis, requirements, dimensional model, data dictionary | Done |
| 2. Implementation | 4-6 | PostgreSQL schemas, staging and cleaning, ETL, data quality checks | Done |
| 3. Analytics and BI | 7-8 | Analytical and OLAP SQL, reporting views, indexing, Power BI dashboard | In progress (views, analytical SQL and insights report done) |

## How to run

Requirements: PostgreSQL with pgAdmin, Python 3, and
`pip install pandas sqlalchemy psycopg2-binary`

1. **Create a database** in pgAdmin (any name, for example `sakila_dw`).
2. **Load the CSV files into staging.** From the repo folder, in Command Prompt (Windows):
   ```
   set PGPASSWORD=your_postgres_password
   set PGDATABASE=sakila_dw
   python 03_ETL/load_staging.py
   ```
   This creates `project_staging.raw_<table>` for all 15 files.
3. **Clean the staging data.** Run `03_ETL/staging.sql` with **psql** or pgAdmin's **PSQL Tool** (not the Query Tool, because the script uses the psql command `\set`):
   ```
   psql -U postgres -h localhost -d sakila_dw -f 03_ETL/staging.sql
   ```
   This builds the cleaned `project_staging.stg_<table>` tables and prints before/after row counts.
4. **(Optional) Export the cleaned data** to `02_Data/cleaned_data`:
   ```
   python 03_ETL/export_cleaned.py
   ```
5. **Create the warehouse, load it and check it.** Run these four scripts in order, with psql or the PSQL Tool:
   ```
   psql -U postgres -h localhost -d sakila_dw -f 04_Data_Warehouse/warehouse.sql
   psql -U postgres -h localhost -d sakila_dw -f 03_ETL/dimensions.sql
   psql -U postgres -h localhost -d sakila_dw -f 03_ETL/facts.sql
   psql -U postgres -h localhost -d sakila_dw -f 03_ETL/checks.sql
   ```
   `checks.sql` prints the data quality results; every row should say PASS.
6. **Create the reporting views** with `05_Analytics/Views.sql` (works in the Query Tool too), then run
   `05_Analytics/Analytical_Queries.sql` to answer the business questions:
   ```
   psql -U postgres -h localhost -d sakila_dw -f 05_Analytics/Views.sql
   psql -U postgres -h localhost -d sakila_dw -f 05_Analytics/Analytical_Queries.sql
   ```
7. **Open the dashboard** `06_Dashboard/PowerBI.pbix` and point it at your database (Phase 3).

## Phase 2 results

| Table | Rows |
|---|---|
| dim_date / dim_customer / dim_film | 731 / 603 / 1,001 |
| dim_store / dim_staff / dim_actor | 3 / 3 / 201 |
| fact_rental | 16,044 |
| fact_payment | 16,049 (total 67,416.51, matches the source) |
| fact_inventory_daily | 136,890 (90 days x 1,521 film-store pairs) |
| fact_film_cast | 5,462 |

All 31 checks in `checks.sql` pass (completeness, uniqueness, domain validity, integrity, accuracy, SCD Type 2). Details are in `01_Project_Documentation/Data_Quality_Report.pdf`.

## Reporting views (Phase 3)

All three views are in the `project_reporting` schema. Ratio columns (late %, utilization %) are included, but when you
combine rows (several months, stores or films) rebuild the ratio from the count columns, for example
`SUM(late_rentals) / SUM(returned_rentals)`, rather than adding or averaging the percentages.

**vw_monthly_sales** - one row per month per store (10 rows)
year_month, year, month_number, month_label, store_id, store_name, rentals, returned_rentals, late_rentals, late_pct,
weekend_rentals, weekday_rentals, active_customers, payments, revenue, avg_payment, prev_active_month,
prev_month_revenue, revenue_growth_pct

**vw_product_performance** - one row per film per store (1,563 rows; films with no copies have store_name 'Not stocked')
film_id, title, category_name, rating, length_band, rental_rate, rental_rate_band, actor_count, store_id, store_name,
copies_owned, rentals, returned_rentals, late_rentals, late_pct, avg_days_kept, revenue, revenue_per_copy,
days_tracked, sold_out_days, sold_out_pct, total_copies_rented_out, total_copies_owned, utilization_pct,
stock_status (Balanced / Understocked / Overstocked / Not stocked)

**vw_customer_analysis** - one row per customer, current details (599 rows)
customer_id, full_name, email, city, country, home_store_name, is_active, rentals, returned_rentals, late_rentals,
first_rental_date, last_rental_date, payments, total_spent, favourite_category, late_pct, avg_payment, spend_rank,
value_segment (High / Medium / Low, by total spend)

Totals that reconcile with the warehouse: rentals 16,044 and revenue 67,416.51 in each view. For the total number of
customers use `vw_customer_analysis` (599); `active_customers` in vw_monthly_sales counts customers per month and store,
so it cannot be added up.

All scripts are safe to re-run: they drop and rebuild their tables.
