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
02_Data/
    raw_data/               Sakila tables exported as CSV (source files)
    cleaned_data/           Cleaned output (if exported)
03_ETL/
    load_staging.py         Loads the CSV files into project_staging.raw_<table>
    staging.sql             Cleans raw_ tables into typed project_staging.stg_<table>
    dimensions.sql          Dimension loads (to be added)
    facts.sql               Fact loads (to be added)
04_Data_Warehouse/
    warehouse.sql           Warehouse tables in project_dw (to be added)
05_Analytics/
    OLAP.sql                Analytical and OLAP queries, ROLLUP and CUBE (Phase 3)
    Views.sql               Reporting views in project_reporting (Phase 3)
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
| 2. Implementation | 4-6 | PostgreSQL schemas, staging and cleaning, ETL, data quality checks | In progress (staging and cleaning done) |
| 3. Analytics and BI | 7-8 | Analytical and OLAP SQL, reporting views, indexing, Power BI dashboard | Planned |

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
4. **Create the warehouse** with `04_Data_Warehouse/warehouse.sql`, then load it with `03_ETL/dimensions.sql` followed by `03_ETL/facts.sql` (to be added).
5. **Create the reporting views** with `05_Analytics/Views.sql` (Phase 3).
6. **Open the dashboard** `06_Dashboard/PowerBI.pbix` and point it at your database (Phase 3).

All scripts are safe to re-run: they drop and rebuild their tables.
