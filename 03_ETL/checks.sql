-- ============================================================================
-- DL3004 Movie Rental DW - Step 6: Unified Data Quality & Reconciliation Suite
-- Schema : project_dw & project_staging (PostgreSQL)
-- Author : Romaisa Sajjad (Roll No: 24L-2608)
--
-- Single comprehensive validation script covering all Dimension & Fact tables
-- across the 4 Data Quality Pillars (BRD Section 8):
--   1. Row Counts & Unknown (-1) Sentinel Verification
--   2. Uniqueness Checks (Natural Keys & Current SCD2 Versions)
--   3. Completeness Checks (Zero Illegal NULLs & Unreturned Rental Mapping)
--   4. Domain Validity & Business Logic Checks (Bands, Dates, Stock Balance)
--   5. Referential Integrity Checks (Zero Orphan Foreign Keys)
--   6. Accuracy, Financial Reconciliation & SCD2 Historical Join Verification
--
-- Run from repo root (after warehouse.sql, dimensions.sql, and facts.sql):
--   psql -U postgres -h localhost -d sakila_dw -f 03_ETL/checks.sql
-- ============================================================================

\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

SET search_path = project_dw, project_staging, public;

-- ----------------------------------------------------------------------------
-- 1. Dimension Row Counts & Unknown (-1) Sentinel Row Verification
-- ----------------------------------------------------------------------------
SELECT 'Row Count & Unknown Check' AS check_category,
       dim_table,
       total_rows,
       has_unknown_row,
       CASE WHEN total_rows >= expected_min AND has_unknown_row = 'YES' THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
    SELECT 'dim_date' AS dim_table, COUNT(*) AS total_rows,
           CASE WHEN COUNT(*) FILTER (WHERE date_key = -1) = 1 THEN 'YES' ELSE 'NO' END AS has_unknown_row,
           731 AS expected_min
    FROM project_dw.dim_date
    UNION ALL
    SELECT 'dim_film', COUNT(*),
           CASE WHEN COUNT(*) FILTER (WHERE film_key = -1) = 1 THEN 'YES' ELSE 'NO' END,
           1001
    FROM project_dw.dim_film
    UNION ALL
    SELECT 'dim_store', COUNT(*),
           CASE WHEN COUNT(*) FILTER (WHERE store_key = -1) = 1 THEN 'YES' ELSE 'NO' END,
           3
    FROM project_dw.dim_store
    UNION ALL
    SELECT 'dim_staff', COUNT(*),
           CASE WHEN COUNT(*) FILTER (WHERE staff_key = -1) = 1 THEN 'YES' ELSE 'NO' END,
           3
    FROM project_dw.dim_staff
    UNION ALL
    SELECT 'dim_actor', COUNT(*),
           CASE WHEN COUNT(*) FILTER (WHERE actor_key = -1) = 1 THEN 'YES' ELSE 'NO' END,
           201
    FROM project_dw.dim_actor
    UNION ALL
    SELECT 'dim_customer', COUNT(*),
           CASE WHEN COUNT(*) FILTER (WHERE customer_key = -1) = 1 THEN 'YES' ELSE 'NO' END,
           600
    FROM project_dw.dim_customer
) qc1
ORDER BY dim_table;

-- ----------------------------------------------------------------------------
-- 2. Uniqueness Checks (Natural Keys & SCD2 Current Flag Uniqueness)
-- ----------------------------------------------------------------------------
SELECT 'Uniqueness Check' AS check_category,
       'dim_film' AS table_name,
       COUNT(*) - COUNT(DISTINCT film_id) AS duplicate_keys,
       CASE WHEN COUNT(*) - COUNT(DISTINCT film_id) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM project_dw.dim_film
UNION ALL
SELECT 'Uniqueness Check', 'dim_store',
       COUNT(*) - COUNT(DISTINCT store_id),
       CASE WHEN COUNT(*) - COUNT(DISTINCT store_id) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.dim_store
UNION ALL
SELECT 'Uniqueness Check', 'dim_staff',
       COUNT(*) - COUNT(DISTINCT staff_id),
       CASE WHEN COUNT(*) - COUNT(DISTINCT staff_id) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.dim_staff
UNION ALL
SELECT 'Uniqueness Check', 'dim_actor',
       COUNT(*) - COUNT(DISTINCT actor_id),
       CASE WHEN COUNT(*) - COUNT(DISTINCT actor_id) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.dim_actor
UNION ALL
SELECT 'Uniqueness Check', 'dim_customer (current)',
       COUNT(*) - COUNT(DISTINCT customer_id),
       CASE WHEN COUNT(*) - COUNT(DISTINCT customer_id) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.dim_customer
WHERE is_current = 'Y';

-- ----------------------------------------------------------------------------
-- 3. Completeness Checks (Mandatory Dimension & Fact Attributes)
-- ----------------------------------------------------------------------------
SELECT 'Completeness Check' AS check_category,
       'dim_film mandatory fields' AS check_description,
       COUNT(*) AS violations,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM project_dw.dim_film
WHERE film_key <> -1 AND (title IS NULL OR category_name IS NULL OR language IS NULL OR rental_rate IS NULL)
UNION ALL
SELECT 'Completeness Check', 'dim_store mandatory fields',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.dim_store
WHERE store_key <> -1 AND (store_address IS NULL OR city IS NULL OR country IS NULL OR manager_name IS NULL)
UNION ALL
SELECT 'Completeness Check', 'dim_staff mandatory fields',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.dim_staff
WHERE staff_key <> -1 AND (full_name IS NULL OR email IS NULL OR home_store_name IS NULL OR is_active IS NULL)
UNION ALL
SELECT 'Completeness Check', 'dim_actor mandatory fields',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.dim_actor
WHERE actor_key <> -1 AND (first_name IS NULL OR last_name IS NULL OR full_name IS NULL)
UNION ALL
SELECT 'Completeness Check', 'dim_date mandatory fields',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.dim_date
WHERE date_key <> -1 AND (full_date IS NULL OR day_name IS NULL OR month_name IS NULL OR is_weekend IS NULL)
UNION ALL
SELECT 'Completeness Check', 'fact_rental unreturned rentals mapped to return_date_key = -1',
       ABS(
           (SELECT COUNT(*) FROM project_dw.fact_rental WHERE return_date_key = -1 AND is_returned = 0)
         - (SELECT COUNT(*) FROM project_staging.stg_rental WHERE return_date IS NULL)
       ),
       CASE WHEN (SELECT COUNT(*) FROM project_dw.fact_rental WHERE return_date_key = -1 AND is_returned = 0)
               = (SELECT COUNT(*) FROM project_staging.stg_rental WHERE return_date IS NULL)
            THEN 'PASS' ELSE 'FAIL' END;

-- ----------------------------------------------------------------------------
-- 4. Domain Validity & Business Logic Checks
-- ----------------------------------------------------------------------------
SELECT 'Domain Validity' AS check_category,
       'dim_film length_band coverage' AS check_description,
       COUNT(*) AS invalid_records,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM project_dw.dim_film
WHERE film_key <> -1 AND length_band NOT IN ('Short (< 90)', 'Medium (90-120)', 'Long (> 120)')
UNION ALL
SELECT 'Domain Validity', 'dim_film rental_rate_band coverage',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.dim_film
WHERE film_key <> -1 AND rental_rate_band NOT IN ('Budget', 'Standard', 'Premium')
UNION ALL
SELECT 'Domain Validity', 'dim_date weekend flag (Y/N)',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.dim_date
WHERE is_weekend NOT IN ('Y', 'N')
UNION ALL
SELECT 'Domain Validity', 'dim_date date_key consistency (YYYYMMDD)',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.dim_date
WHERE date_key <> -1 AND date_key <> TO_CHAR(full_date, 'YYYYMMDD')::INT
UNION ALL
SELECT 'Domain Validity', 'fact_inventory_daily stock balance (owned = rented + available)',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.fact_inventory_daily
WHERE copies_owned <> copies_rented_out + copies_available
   OR copies_available < 0
   OR utilization_pct < 0 OR utilization_pct > 100;

-- ----------------------------------------------------------------------------
-- 5. Referential Integrity Checks (Zero Orphan Foreign Keys)
-- ----------------------------------------------------------------------------
SELECT 'Referential Integrity' AS check_category,
       'fact_rental orphan foreign keys' AS check_description,
       COUNT(*) AS orphan_records,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM project_dw.fact_rental fr
LEFT JOIN project_dw.dim_date d1     ON fr.rental_date_key = d1.date_key
LEFT JOIN project_dw.dim_date d2     ON fr.return_date_key = d2.date_key
LEFT JOIN project_dw.dim_customer dc ON fr.customer_key    = dc.customer_key
LEFT JOIN project_dw.dim_film df     ON fr.film_key        = df.film_key
LEFT JOIN project_dw.dim_store ds    ON fr.store_key       = ds.store_key
LEFT JOIN project_dw.dim_staff dst   ON fr.staff_key       = dst.staff_key
WHERE d1.date_key IS NULL OR d2.date_key IS NULL OR dc.customer_key IS NULL
   OR df.film_key IS NULL OR ds.store_key IS NULL OR dst.staff_key IS NULL
UNION ALL
SELECT 'Referential Integrity', 'fact_payment orphan foreign keys',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.fact_payment fp
LEFT JOIN project_dw.dim_date d      ON fp.payment_date_key = d.date_key
LEFT JOIN project_dw.dim_customer dc ON fp.customer_key     = dc.customer_key
LEFT JOIN project_dw.dim_film df     ON fp.film_key         = df.film_key
LEFT JOIN project_dw.dim_store ds    ON fp.store_key        = ds.store_key
LEFT JOIN project_dw.dim_staff dst   ON fp.staff_key        = dst.staff_key
WHERE d.date_key IS NULL OR dc.customer_key IS NULL OR df.film_key IS NULL
   OR ds.store_key IS NULL OR dst.staff_key IS NULL
UNION ALL
SELECT 'Referential Integrity', 'fact_inventory_daily orphan foreign keys',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.fact_inventory_daily fi
LEFT JOIN project_dw.dim_date d   ON fi.snapshot_date_key = d.date_key
LEFT JOIN project_dw.dim_film df  ON fi.film_key          = df.film_key
LEFT JOIN project_dw.dim_store ds ON fi.store_key         = ds.store_key
WHERE d.date_key IS NULL OR df.film_key IS NULL OR ds.store_key IS NULL
UNION ALL
SELECT 'Referential Integrity', 'fact_film_cast orphan foreign keys',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.fact_film_cast fc
LEFT JOIN project_dw.dim_film df  ON fc.film_key  = df.film_key
LEFT JOIN project_dw.dim_actor da ON fc.actor_key = da.actor_key
WHERE df.film_key IS NULL OR da.actor_key IS NULL;

-- ----------------------------------------------------------------------------
-- 6. Accuracy, Revenue Reconciliation & SCD Type 2 Verification
-- ----------------------------------------------------------------------------
SELECT 'Accuracy & Reconciliation' AS check_category,
       'fact_rental row count vs stg_rental' AS check_description,
       (SELECT COUNT(*) FROM project_dw.fact_rental) AS dw_value,
       (SELECT COUNT(*) FROM project_staging.stg_rental) AS stg_value,
       CASE WHEN (SELECT COUNT(*) FROM project_dw.fact_rental) = (SELECT COUNT(*) FROM project_staging.stg_rental)
            THEN 'PASS' ELSE 'FAIL' END AS status
UNION ALL
SELECT 'Accuracy & Reconciliation',
       'fact_payment row count vs stg_payment',
       (SELECT COUNT(*) FROM project_dw.fact_payment),
       (SELECT COUNT(*) FROM project_staging.stg_payment),
       CASE WHEN (SELECT COUNT(*) FROM project_dw.fact_payment) = (SELECT COUNT(*) FROM project_staging.stg_payment)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'Accuracy & Reconciliation',
       'fact_payment total revenue (cents) vs stg_payment (67,416.51)',
       (SELECT (SUM(amount) * 100)::BIGINT FROM project_dw.fact_payment),
       (SELECT (SUM(amount) * 100)::BIGINT FROM project_staging.stg_payment),
       CASE WHEN (SELECT SUM(amount) FROM project_dw.fact_payment) = (SELECT SUM(amount) FROM project_staging.stg_payment)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'Accuracy & Reconciliation',
       'fact_film_cast row count vs stg_film_actor',
       (SELECT COUNT(*) FROM project_dw.fact_film_cast),
       (SELECT COUNT(*) FROM project_staging.stg_film_actor),
       CASE WHEN (SELECT COUNT(*) FROM project_dw.fact_film_cast) = (SELECT COUNT(*) FROM project_staging.stg_film_actor)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'SCD Type 2 Verification',
       'fact_rental transactions matched to historical (is_current=N) vs current (is_current=Y) customer rows',
       (SELECT COUNT(*) FROM project_dw.fact_rental fr JOIN project_dw.dim_customer dc ON fr.customer_key = dc.customer_key WHERE dc.is_current = 'N'),
       (SELECT COUNT(*) FROM project_dw.fact_rental fr JOIN project_dw.dim_customer dc ON fr.customer_key = dc.customer_key WHERE dc.is_current = 'Y'),
       CASE WHEN (SELECT COUNT(*) FROM project_dw.fact_rental fr JOIN project_dw.dim_customer dc ON fr.customer_key = dc.customer_key)
               = (SELECT COUNT(*) FROM project_dw.fact_rental)
            THEN 'PASS' ELSE 'FAIL' END;