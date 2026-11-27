--checks.sql - data quality checks on the loaded warehouse, every row should say PASS (Romaisa Sajjad)
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

SET search_path = project_dw, project_staging, public;

SELECT 'Row Count & Unknown Check' AS check_category,  --1. every dim has rows and its -1 unknown row
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

SELECT 'Uniqueness Check' AS check_category,  --2. no duplicate ids in the dims
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
WHERE is_current = 'Y';  --for customers only the current rows count

SELECT 'Completeness Check' AS check_category,  --3. required fields are filled in
       'dim_film mandatory fields' AS check_description,
       COUNT(*) AS violations,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM project_dw.dim_film
WHERE film_key <> -1 AND (title IS NULL OR category_name IS NULL OR language IS NULL OR rental_rate IS NULL)  --unknown rows are skipped
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
SELECT 'Completeness Check', 'fact_rental unreturned rentals mapped to return_date_key = -1',  --unreturned rentals must all be -1
       ABS(
           (SELECT COUNT(*) FROM project_dw.fact_rental WHERE return_date_key = -1 AND is_returned = 0)
         - (SELECT COUNT(*) FROM project_staging.stg_rental WHERE return_date IS NULL)
       ),
       CASE WHEN (SELECT COUNT(*) FROM project_dw.fact_rental WHERE return_date_key = -1 AND is_returned = 0)
               = (SELECT COUNT(*) FROM project_staging.stg_rental WHERE return_date IS NULL)
            THEN 'PASS' ELSE 'FAIL' END;

SELECT 'Domain Validity' AS check_category,  --4. values are the allowed ones
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
WHERE date_key <> -1 AND date_key <> TO_CHAR(full_date, 'YYYYMMDD')::INT  --date key has to match the date
UNION ALL
SELECT 'Domain Validity', 'fact_inventory_daily stock balance (owned = rented + available)',  --stock has to add up
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.fact_inventory_daily
WHERE copies_owned <> copies_rented_out + copies_available
   OR copies_available < 0
   OR utilization_pct < 0 OR utilization_pct > 100;

SELECT 'Referential Integrity' AS check_category,  --5. no fact row points to a missing dim row
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
SELECT 'Referential Integrity', 'fact_payment orphan foreign keys',  --same for payments
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
SELECT 'Referential Integrity', 'fact_inventory_daily orphan foreign keys',  --same for the snapshot
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.fact_inventory_daily fi
LEFT JOIN project_dw.dim_date d   ON fi.snapshot_date_key = d.date_key
LEFT JOIN project_dw.dim_film df  ON fi.film_key          = df.film_key
LEFT JOIN project_dw.dim_store ds ON fi.store_key         = ds.store_key
WHERE d.date_key IS NULL OR df.film_key IS NULL OR ds.store_key IS NULL
UNION ALL
SELECT 'Referential Integrity', 'fact_film_cast orphan foreign keys',  --same for the cast table
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_dw.fact_film_cast fc
LEFT JOIN project_dw.dim_film df  ON fc.film_key  = df.film_key
LEFT JOIN project_dw.dim_actor da ON fc.actor_key = da.actor_key
WHERE df.film_key IS NULL OR da.actor_key IS NULL;

SELECT 'Accuracy & Reconciliation' AS check_category,  --6. warehouse matches staging
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
       'fact_payment total revenue (cents) vs stg_payment (67,416.51)',  --revenue compared in cents so rounding cant hide anything
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
SELECT 'SCD Type 2 Verification',  --every rental found its customer version
       'fact_rental transactions matched to historical (is_current=N) vs current (is_current=Y) customer rows',
       (SELECT COUNT(*) FROM project_dw.fact_rental fr JOIN project_dw.dim_customer dc ON fr.customer_key = dc.customer_key WHERE dc.is_current = 'N'),  --rentals linked to an old customer version
       (SELECT COUNT(*) FROM project_dw.fact_rental fr JOIN project_dw.dim_customer dc ON fr.customer_key = dc.customer_key WHERE dc.is_current = 'Y'),  --rentals linked to the current version
       CASE WHEN (SELECT COUNT(*) FROM project_dw.fact_rental fr JOIN project_dw.dim_customer dc ON fr.customer_key = dc.customer_key)
               = (SELECT COUNT(*) FROM project_dw.fact_rental)
            THEN 'PASS' ELSE 'FAIL' END;
