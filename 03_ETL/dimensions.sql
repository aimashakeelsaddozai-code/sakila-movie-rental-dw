--dimensions.sql - loads the 6 dimension tables from staging (Romaisa Sajjad)
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

SET search_path = project_dw, project_staging, public;

BEGIN;

TRUNCATE TABLE project_dw.fact_film_cast,  --empty everything first so the script can be re-run
               project_dw.fact_inventory_daily,
               project_dw.fact_payment,
               project_dw.fact_rental,
               project_dw.dim_actor,
               project_dw.dim_staff,
               project_dw.dim_store,
               project_dw.dim_film,
               project_dw.dim_customer,
               project_dw.dim_date
               RESTART IDENTITY CASCADE;  --also resets the identity numbers

INSERT INTO project_dw.dim_date (  --unknown rows first, key -1
    date_key, full_date, day_of_month, day_name, day_of_week,
    is_weekend, week_of_year, month_number, month_name, year_month, quarter, year
) VALUES (
    -1, '1900-01-01', 1, 'Unknown', 1,  ---1 = not returned / unknown date
    'N', 1, 1, 'Unknown', '1900-01', 1, 1900
);

INSERT INTO project_dw.dim_customer (
    customer_key, customer_id, first_name, last_name, full_name, email,
    address, district, city, country, postal_code, home_store_name,
    is_active, effective_from, effective_to, is_current
) VALUES (
    -1, -1, 'Unknown', 'Unknown', 'Unknown Customer', 'unknown@sakilacustomer.org',  --unknown customer
    'Unknown Address', 'Unknown', 'Unknown City', 'Unknown Country', 'Unknown', 'Unknown Store',
    'N', '1900-01-01', '9999-12-31', 'Y'  --valid forever
);

INSERT INTO project_dw.dim_film (
    film_key, film_id, title, category_name, rating, language,
    release_year, length_minutes, length_band, rental_rate,
    rental_rate_band, allowed_rental_days, replacement_cost, special_features
) VALUES (
    -1, -1, 'Unknown Film', 'Unknown', 'N/A', 'Unknown',  --unknown film, used if a payment has no rental
    1900, 0, 'Unknown', 0.00,
    'Unknown', 0, 0.00, 'None'
);

INSERT INTO project_dw.dim_store (
    store_key, store_id, store_address, city, country, manager_name
) VALUES (
    -1, -1, 'Unknown Store Address', 'Unknown City', 'Unknown Country', 'Unknown Manager'  --unknown store
);

INSERT INTO project_dw.dim_staff (
    staff_key, staff_id, full_name, email, home_store_name, is_active
) VALUES (
    -1, -1, 'Unknown Staff', 'unknown@sakilastaff.com', 'Unknown Store', 'N'  --unknown staff
);

INSERT INTO project_dw.dim_actor (
    actor_key, actor_id, first_name, last_name, full_name
) VALUES (
    -1, -1, 'Unknown', 'Unknown', 'Unknown Actor'  --unknown actor
);

INSERT INTO project_dw.dim_date (  --now the real calendar
    date_key, full_date, day_of_month, day_name, day_of_week,
    is_weekend, week_of_year, month_number, month_name, year_month, quarter, year
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT AS date_key,  --20050715 style key
    d::DATE AS full_date,
    EXTRACT(DAY FROM d)::INT AS day_of_month,
    TRIM(TO_CHAR(d, 'FMDay')) AS day_name,
    EXTRACT(ISODOW FROM d)::INT AS day_of_week,  --1 = monday
    CASE WHEN EXTRACT(ISODOW FROM d) IN (6, 7) THEN 'Y' ELSE 'N' END AS is_weekend,  --sat and sun are weekend
    EXTRACT(WEEK FROM d)::INT AS week_of_year,
    EXTRACT(MONTH FROM d)::INT AS month_number,
    TRIM(TO_CHAR(d, 'FMMonth')) AS month_name,
    TO_CHAR(d, 'YYYY-MM') AS year_month,
    EXTRACT(QUARTER FROM d)::INT AS quarter,
    EXTRACT(YEAR FROM d)::INT AS year
FROM generate_series('2005-01-01'::DATE, '2006-12-31'::DATE, '1 day'::INTERVAL) AS d  --one row per day for 2005 and 2006
ORDER BY d;

INSERT INTO project_dw.dim_film (
    film_id, title, category_name, rating, language, release_year,
    length_minutes, length_band, rental_rate, rental_rate_band,
    allowed_rental_days, replacement_cost, special_features
)
SELECT
    f.film_id,
    f.title,
    COALESCE(c.name, 'Unknown') AS category_name,  --category name copied into the film row
    f.rating,
    COALESCE(l.name, 'Unknown') AS language,
    f.release_year,
    f.length AS length_minutes,
    CASE
        WHEN f.length < 90 THEN 'Short (< 90)'  --length bands
        WHEN f.length <= 120 THEN 'Medium (90-120)'
        WHEN f.length > 120 THEN 'Long (> 120)'
        ELSE 'Unknown'
    END AS length_band,
    f.rental_rate,
    CASE
        WHEN f.rental_rate <= 0.99 THEN 'Budget'  --price bands
        WHEN f.rental_rate <= 2.99 THEN 'Standard'
        ELSE 'Premium'
    END AS rental_rate_band,
    f.rental_duration AS allowed_rental_days,  --loan period, needed for days_late
    f.replacement_cost,
    COALESCE(f.special_features, 'None') AS special_features
FROM project_staging.stg_film f
LEFT JOIN project_staging.stg_film_category fc ON f.film_id = fc.film_id  --left join so no film gets lost
LEFT JOIN project_staging.stg_category c ON fc.category_id = c.category_id
LEFT JOIN project_staging.stg_language l ON f.language_id = l.language_id
ORDER BY f.film_id;

INSERT INTO project_dw.dim_store (
    store_id, store_address, city, country, manager_name
)
SELECT
    s.store_id,
    a.address AS store_address,
    c.city,
    co.country,
    st.first_name || ' ' || st.last_name AS manager_name  --manager name from staff
FROM project_staging.stg_store s
JOIN project_staging.stg_address a ON s.address_id = a.address_id
JOIN project_staging.stg_city c ON a.city_id = c.city_id
JOIN project_staging.stg_country co ON c.country_id = co.country_id
JOIN project_staging.stg_staff st ON s.manager_staff_id = st.staff_id
ORDER BY s.store_id;

INSERT INTO project_dw.dim_staff (
    staff_id, full_name, email, home_store_name, is_active
)
SELECT
    st.staff_id,
    st.first_name || ' ' || st.last_name AS full_name,
    st.email,
    'Store ' || st.store_id || ' - ' || c.city AS home_store_name,  --store name instead of store id
    CASE WHEN st.active THEN 'Y' ELSE 'N' END AS is_active  --true/false to Y/N
FROM project_staging.stg_staff st
JOIN project_staging.stg_store s ON st.store_id = s.store_id
JOIN project_staging.stg_address a ON s.address_id = a.address_id
JOIN project_staging.stg_city c ON a.city_id = c.city_id
ORDER BY st.staff_id;

INSERT INTO project_dw.dim_actor (
    actor_id, first_name, last_name, full_name
)
SELECT
    a.actor_id,
    a.first_name,
    a.last_name,
    a.first_name || ' ' || a.last_name AS full_name  --full name for reports
FROM project_staging.stg_actor a
ORDER BY a.actor_id;

INSERT INTO project_dw.dim_customer (
    customer_id, first_name, last_name, full_name, email,
    address, district, city, country, postal_code,
    home_store_name, is_active, effective_from, effective_to, is_current
)
SELECT
    cu.customer_id,
    cu.first_name,
    cu.last_name,
    cu.first_name || ' ' || cu.last_name AS full_name,
    cu.email,
    a.address,
    a.district,
    ci.city,
    co.country,
    a.postal_code,
    'Store ' || cu.store_id || ' - ' || sto_ci.city AS home_store_name,  --home store as a name
    CASE WHEN cu.active = 1 THEN 'Y' ELSE 'N' END AS is_active,
    '1900-01-01'::DATE AS effective_from,  --first version starts in 1900 so every old rental finds it
    '9999-12-31'::DATE AS effective_to,  --still valid
    'Y' AS is_current  --current row
FROM project_staging.stg_customer cu
JOIN project_staging.stg_address a ON cu.address_id = a.address_id
JOIN project_staging.stg_city ci ON a.city_id = ci.city_id
JOIN project_staging.stg_country co ON ci.country_id = co.country_id
JOIN project_staging.stg_store sto ON cu.store_id = sto.store_id
JOIN project_staging.stg_address sto_a ON sto.address_id = sto_a.address_id
JOIN project_staging.stg_city sto_ci ON sto_a.city_id = sto_ci.city_id
ORDER BY cu.customer_id;

COMMIT;  --save the loads

SELECT 'Row Count & Unknown Check' AS check_category,  --check 1: row counts and unknown rows
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

SELECT 'Uniqueness Check' AS check_category,  --check 2: no duplicate ids
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
WHERE is_current = 'Y';  --only current rows for customers

SELECT 'Completeness Check' AS check_category,  --check 3: required fields not empty
       'dim_film mandatory fields' AS check_description,
       COUNT(*) AS null_violations,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM project_dw.dim_film
WHERE film_key <> -1 AND (title IS NULL OR category_name IS NULL OR language IS NULL OR rental_rate IS NULL)  --unknown rows left out
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
WHERE date_key <> -1 AND (full_date IS NULL OR day_name IS NULL OR month_name IS NULL OR is_weekend IS NULL);

SELECT 'Domain Validity' AS check_category,  --check 4: values are allowed ones
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
WHERE date_key <> -1 AND date_key <> TO_CHAR(full_date, 'YYYYMMDD')::INT;  --key must match the date

SELECT 'Referential Integrity' AS check_category,  --check 5: every staging id can be found in the dims
       'stg_rental inventory to dim_film lookup' AS check_description,
       COUNT(*) AS orphaned_records,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM project_staging.stg_rental r
JOIN project_staging.stg_inventory i ON r.inventory_id = i.inventory_id
LEFT JOIN project_dw.dim_film f ON i.film_id = f.film_id
WHERE f.film_key IS NULL
UNION ALL
SELECT 'Referential Integrity', 'stg_rental customer to dim_customer lookup',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_staging.stg_rental r
LEFT JOIN project_dw.dim_customer c ON r.customer_id = c.customer_id AND c.is_current = 'Y'  --customer lookup on the current row
WHERE c.customer_key IS NULL
UNION ALL
SELECT 'Referential Integrity', 'stg_rental staff to dim_staff lookup',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_staging.stg_rental r
LEFT JOIN project_dw.dim_staff s ON r.staff_id = s.staff_id
WHERE s.staff_key IS NULL
UNION ALL
SELECT 'Referential Integrity', 'stg_rental date to dim_date lookup',
       COUNT(*),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM project_staging.stg_rental r
LEFT JOIN project_dw.dim_date d ON TO_CHAR(r.rental_date, 'YYYYMMDD')::INT = d.date_key
WHERE d.date_key IS NULL;
