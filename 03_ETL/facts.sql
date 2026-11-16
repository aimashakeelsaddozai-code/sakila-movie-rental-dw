-- ============================================================================
-- DL3004 Movie Rental DW - Step 5: SCD2 Customer History & Fact Table Loads
-- Schema : project_dw (PostgreSQL)
-- Author : Romaisa Sajjad (Roll No: 24L-2608)
--
-- Deliverables covered:
--   1. Customer SCD Type 2 History Update (dim_customer):
--        - Tracks address, district, city, country, postal_code,
--          home_store_name, and is_active (BRD BR-09 & Section 11).
--        - Applies simulated customer attribute changes and expires old rows.
--   2. Fact Table Loads:
--        - fact_rental          (Transaction fact: 16,044 rows)
--        - fact_payment         (Transaction fact: 16,049 rows, total = 67,416.51)
--        - fact_inventory_daily (Periodic snapshot fact for active trading days)
--        - fact_film_cast       (Factless bridge table: 5,462 film-actor links)
--
-- Run from repo root (after warehouse.sql and dimensions.sql):
--   psql -U postgres -h localhost -d sakila_dw -f 03_ETL/facts.sql
--
-- Safe to re-run: Resets SCD2 simulated history and truncates fact tables.
-- ============================================================================

\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

SET search_path = project_dw, project_staging, public;

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Reset Fact Tables & Simulated SCD2 History (Safe Re-run)
-- ----------------------------------------------------------------------------
TRUNCATE TABLE project_dw.fact_film_cast,
               project_dw.fact_inventory_daily,
               project_dw.fact_payment,
               project_dw.fact_rental;

DELETE FROM project_dw.dim_customer
WHERE customer_key <> -1
  AND effective_from > '1900-01-01'::DATE;

UPDATE project_dw.dim_customer
SET effective_to = '9999-12-31'::DATE,
    is_current   = 'Y'
WHERE customer_key <> -1
  AND effective_from = '1900-01-01'::DATE;

-- ----------------------------------------------------------------------------
-- 2. Customer SCD Type 2 Merge (Simulated History per BRD Section 11)
--    - Customer 1 (Mary Smith): Moved address on 2005-07-01
--    - Customer 2 (Patricia Johnson): Transferred home store on 2005-07-15
--    - Customer 3 (Linda Williams): Account deactivated on 2005-08-01
-- ----------------------------------------------------------------------------
CREATE TEMP TABLE tmp_customer_incoming ON COMMIT DROP AS
SELECT
    cu.customer_id,
    cu.first_name,
    cu.last_name,
    cu.first_name || ' ' || cu.last_name AS full_name,
    cu.email,
    CASE WHEN cu.customer_id = 1 THEN '742 Evergreen Terrace' ELSE a.address END AS address,
    a.district,
    ci.city,
    co.country,
    CASE WHEN cu.customer_id = 1 THEN '90210' ELSE a.postal_code END AS postal_code,
    CASE WHEN cu.customer_id = 2 THEN 'Store 2 - Woodridge'
         ELSE 'Store ' || cu.store_id || ' - ' || sto_ci.city END AS home_store_name,
    CASE WHEN cu.customer_id = 3 THEN 'N'
         WHEN cu.active = 1 THEN 'Y' ELSE 'N' END AS is_active,
    CASE
        WHEN cu.customer_id = 1 THEN '2005-07-01'::DATE
        WHEN cu.customer_id = 2 THEN '2005-07-15'::DATE
        WHEN cu.customer_id = 3 THEN '2005-08-01'::DATE
        ELSE CURRENT_DATE
    END AS change_effective_date
FROM project_staging.stg_customer cu
JOIN project_staging.stg_address a     ON cu.address_id = a.address_id
JOIN project_staging.stg_city ci       ON a.city_id     = ci.city_id
JOIN project_staging.stg_country co    ON ci.country_id = co.country_id
JOIN project_staging.stg_store sto     ON cu.store_id   = sto.store_id
JOIN project_staging.stg_address sto_a ON sto.address_id = sto_a.address_id
JOIN project_staging.stg_city sto_ci   ON sto_a.city_id  = sto_ci.city_id;

WITH changed_customers AS (
    SELECT inc.*
    FROM tmp_customer_incoming inc
    JOIN project_dw.dim_customer dim
      ON inc.customer_id = dim.customer_id
     AND dim.is_current = 'Y'
    WHERE (dim.address, dim.district, dim.city, dim.country, dim.postal_code, dim.home_store_name, dim.is_active)
       IS DISTINCT FROM
          (inc.address, inc.district, inc.city, inc.country, inc.postal_code, inc.home_store_name, inc.is_active)
)
UPDATE project_dw.dim_customer dim
SET effective_to = (chg.change_effective_date - INTERVAL '1 day')::DATE,
    is_current   = 'N'
FROM changed_customers chg
WHERE dim.customer_id = chg.customer_id
  AND dim.is_current  = 'Y';

INSERT INTO project_dw.dim_customer (
    customer_id, first_name, last_name, full_name, email,
    address, district, city, country, postal_code,
    home_store_name, is_active, effective_from, effective_to, is_current
)
SELECT
    inc.customer_id,
    inc.first_name,
    inc.last_name,
    inc.full_name,
    inc.email,
    inc.address,
    inc.district,
    inc.city,
    inc.country,
    inc.postal_code,
    inc.home_store_name,
    inc.is_active,
    inc.change_effective_date AS effective_from,
    '9999-12-31'::DATE        AS effective_to,
    'Y'                       AS is_current
FROM tmp_customer_incoming inc
WHERE EXISTS (
    SELECT 1
    FROM project_dw.dim_customer dim
    WHERE dim.customer_id  = inc.customer_id
      AND dim.is_current   = 'N'
      AND dim.effective_to = (inc.change_effective_date - INTERVAL '1 day')::DATE
);

-- ----------------------------------------------------------------------------
-- 3. Load fact_rental (Transaction Fact)
--    - Resolves point-in-time customer_key via SCD2 date range
--    - Maps NULL return_date to return_date_key = -1
--    - Computes days_rented, allowed_days, days_late, is_returned, is_late
-- ----------------------------------------------------------------------------
INSERT INTO project_dw.fact_rental (
    rental_id,
    rental_date_key,
    return_date_key,
    customer_key,
    film_key,
    store_key,
    staff_key,
    rental_count,
    days_rented,
    allowed_days,
    days_late,
    is_returned,
    is_late
)
SELECT
    r.rental_id,
    COALESCE(d_rent.date_key, -1) AS rental_date_key,
    CASE
        WHEN r.return_date IS NULL THEN -1
        ELSE COALESCE(d_ret.date_key, -1)
    END AS return_date_key,
    COALESCE(dc.customer_key, -1) AS customer_key,
    COALESCE(df.film_key, -1)     AS film_key,
    COALESCE(ds.store_key, -1)    AS store_key,
    COALESCE(dst.staff_key, -1)   AS staff_key,
    1                             AS rental_count,
    CASE
        WHEN r.return_date IS NOT NULL
        THEN GREATEST(0, (r.return_date::DATE - r.rental_date::DATE))
        ELSE NULL
    END AS days_rented,
    COALESCE(df.allowed_rental_days, 3) AS allowed_days,
    CASE
        WHEN r.return_date IS NOT NULL
        THEN GREATEST(0, (r.return_date::DATE - r.rental_date::DATE) - COALESCE(df.allowed_rental_days, 3))
        ELSE NULL
    END AS days_late,
    CASE WHEN r.return_date IS NOT NULL THEN 1 ELSE 0 END AS is_returned,
    CASE
        WHEN r.return_date IS NOT NULL
         AND (r.return_date::DATE - r.rental_date::DATE) > COALESCE(df.allowed_rental_days, 3)
        THEN 1
        ELSE 0
    END AS is_late
FROM project_staging.stg_rental r
LEFT JOIN project_staging.stg_inventory inv
       ON r.inventory_id = inv.inventory_id
LEFT JOIN project_dw.dim_date d_rent
       ON TO_CHAR(r.rental_date, 'YYYYMMDD')::INT = d_rent.date_key
LEFT JOIN project_dw.dim_date d_ret
       ON r.return_date IS NOT NULL
      AND TO_CHAR(r.return_date, 'YYYYMMDD')::INT = d_ret.date_key
LEFT JOIN project_dw.dim_customer dc
       ON r.customer_id = dc.customer_id
      AND r.rental_date::DATE BETWEEN dc.effective_from AND dc.effective_to
LEFT JOIN project_dw.dim_film df
       ON inv.film_id = df.film_id
LEFT JOIN project_dw.dim_store ds
       ON inv.store_id = ds.store_id
LEFT JOIN project_dw.dim_staff dst
       ON r.staff_id = dst.staff_id
ORDER BY r.rental_id;

-- ----------------------------------------------------------------------------
-- 4. Load fact_payment (Transaction Fact)
--    - Resolves point-in-time customer_key via SCD2 date range on payment_date
--    - Links film_key via rental -> inventory (-1 if payment has no rental)
--    - Links store_key via rental inventory store, falling back to staff store
-- ----------------------------------------------------------------------------
INSERT INTO project_dw.fact_payment (
    payment_id,
    rental_id,
    payment_date_key,
    customer_key,
    film_key,
    store_key,
    staff_key,
    amount
)
SELECT
    p.payment_id,
    p.rental_id,
    COALESCE(d_pay.date_key, -1)  AS payment_date_key,
    COALESCE(dc.customer_key, -1) AS customer_key,
    COALESCE(df.film_key, -1)     AS film_key,
    COALESCE(ds_inv.store_key, ds_stf.store_key, -1) AS store_key,
    COALESCE(dst.staff_key, -1)   AS staff_key,
    p.amount
FROM project_staging.stg_payment p
LEFT JOIN project_staging.stg_rental r
       ON p.rental_id = r.rental_id
      AND p.rental_id <> -1
LEFT JOIN project_staging.stg_inventory inv
       ON r.inventory_id = inv.inventory_id
LEFT JOIN project_staging.stg_staff stf
       ON p.staff_id = stf.staff_id
LEFT JOIN project_dw.dim_date d_pay
       ON TO_CHAR(p.payment_date, 'YYYYMMDD')::INT = d_pay.date_key
LEFT JOIN project_dw.dim_customer dc
       ON p.customer_id = dc.customer_id
      AND p.payment_date::DATE BETWEEN dc.effective_from AND dc.effective_to
LEFT JOIN project_dw.dim_film df
       ON inv.film_id = df.film_id
LEFT JOIN project_dw.dim_store ds_inv
       ON inv.store_id = ds_inv.store_id
LEFT JOIN project_dw.dim_store ds_stf
       ON stf.store_id = ds_stf.store_id
LEFT JOIN project_dw.dim_staff dst
       ON p.staff_id = dst.staff_id
ORDER BY p.payment_id;

-- ----------------------------------------------------------------------------
-- 5. Load fact_inventory_daily (Periodic Snapshot Fact)
--    - Built only for active trading days (dates with rental/return activity)
--      so empty gap months do not distort stock metrics (BRD Section 11)
--    - Grain: snapshot_date_key x film_key x store_key
-- ----------------------------------------------------------------------------
WITH active_days AS (
    SELECT DISTINCT rental_date::DATE AS active_date
    FROM project_staging.stg_rental
    UNION
    SELECT DISTINCT return_date::DATE AS active_date
    FROM project_staging.stg_rental
    WHERE return_date IS NOT NULL
),
owned_stock AS (
    SELECT
        df.film_key,
        ds.store_key,
        inv.film_id,
        inv.store_id,
        COUNT(inv.inventory_id)::INT AS copies_owned
    FROM project_staging.stg_inventory inv
    JOIN project_dw.dim_film df  ON inv.film_id  = df.film_id
    JOIN project_dw.dim_store ds ON inv.store_id = ds.store_id
    GROUP BY df.film_key, ds.store_key, inv.film_id, inv.store_id
),
rented_out_daily AS (
    SELECT
        ad.active_date,
        inv.film_id,
        inv.store_id,
        COUNT(r.rental_id)::INT AS copies_rented_out
    FROM active_days ad
    JOIN project_staging.stg_rental r
      ON r.rental_date::DATE <= ad.active_date
     AND (r.return_date IS NULL OR r.return_date::DATE > ad.active_date)
    JOIN project_staging.stg_inventory inv
      ON r.inventory_id = inv.inventory_id
    GROUP BY ad.active_date, inv.film_id, inv.store_id
)
INSERT INTO project_dw.fact_inventory_daily (
    snapshot_date_key,
    film_key,
    store_key,
    copies_owned,
    copies_rented_out,
    copies_available,
    utilization_pct
)
SELECT
    d.date_key AS snapshot_date_key,
    os.film_key,
    os.store_key,
    os.copies_owned,
    LEAST(os.copies_owned, COALESCE(ro.copies_rented_out, 0)) AS copies_rented_out,
    GREATEST(0, os.copies_owned - COALESCE(ro.copies_rented_out, 0)) AS copies_available,
    ROUND(
        (LEAST(os.copies_owned, COALESCE(ro.copies_rented_out, 0))::NUMERIC / NULLIF(os.copies_owned, 0)) * 100,
        2
    ) AS utilization_pct
FROM active_days ad
JOIN project_dw.dim_date d
  ON ad.active_date = d.full_date
CROSS JOIN owned_stock os
LEFT JOIN rented_out_daily ro
  ON ad.active_date = ro.active_date
 AND os.film_id     = ro.film_id
 AND os.store_id    = ro.store_id
ORDER BY d.date_key, os.film_key, os.store_key;

-- ----------------------------------------------------------------------------
-- 6. Load fact_film_cast (Factless Bridge Table)
-- ----------------------------------------------------------------------------
INSERT INTO project_dw.fact_film_cast (
    film_key,
    actor_key
)
SELECT DISTINCT
    df.film_key,
    da.actor_key
FROM project_staging.stg_film_actor fa
JOIN project_dw.dim_film df  ON fa.film_id  = df.film_id
JOIN project_dw.dim_actor da ON fa.actor_id = da.actor_id
ORDER BY df.film_key, da.actor_key;

COMMIT;

-- Summary of loaded fact tables
SELECT 'fact_rental'          AS fact_table, COUNT(*) AS row_count, NULL::NUMERIC(12,2) AS total_amount FROM project_dw.fact_rental
UNION ALL
SELECT 'fact_payment',         COUNT(*), SUM(amount) FROM project_dw.fact_payment
UNION ALL
SELECT 'fact_inventory_daily', COUNT(*), NULL FROM project_dw.fact_inventory_daily
UNION ALL
SELECT 'fact_film_cast',       COUNT(*), NULL FROM project_dw.fact_film_cast
ORDER BY fact_table;