-- ============================================================================
-- DL3004 Movie Rental DW - Phase 3: Reporting views
-- Schema : project_reporting (PostgreSQL)
-- Author : Zahra Saeed (Roll No: 24L-2512)
--
-- Three views that sit on top of the star schema in project_dw. The Power BI
-- dashboard and the analysis reports read from these views, so nobody has to
-- rewrite the joins.
--
--   vw_monthly_sales        one row per month per store     (Q1, Q9 + dashboard KPIs and trend)
--   vw_product_performance  one row per film per store      (Q2, Q3, Q6, Q7, Q8, Q11)
--   vw_customer_analysis    one row per customer            (Q4, Q5, Q14)
--
-- Ratios (late %, utilization %) are given, but so are the counts behind them.
-- When you add rows together (for example several stores or months in Power BI),
-- rebuild the ratio from the counts, for example SUM(late_rentals) / SUM(returned_rentals),
-- instead of adding or averaging the percentages.
--
-- Run after the warehouse is loaded (warehouse.sql, dimensions.sql, facts.sql).
-- Works in pgAdmin's Query Tool or with psql:
--   psql -U postgres -h localhost -d sakila_dw -f 05_Analytics/Views.sql
-- Safe to re-run: every view is dropped and created again.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS project_reporting;

DROP VIEW IF EXISTS project_reporting.vw_monthly_sales;
DROP VIEW IF EXISTS project_reporting.vw_product_performance;
DROP VIEW IF EXISTS project_reporting.vw_customer_analysis;


-- ----------------------------------------------------------------------------
-- 1. vw_monthly_sales  (grain: one month at one store)
--
-- Rentals come from fact_rental and revenue from fact_payment. The two fact
-- tables are summarised separately by month and store and then joined on those
-- shared (conformed) dimensions. This is a drill-across: the fact tables are
-- never joined to each other directly.
--
-- Revenue growth compares each month with the previous month that had activity
-- at the same store. Sakila has no data between September 2005 and January 2006,
-- so February 2006 is compared with August 2005 (prev_active_month says which).
-- ----------------------------------------------------------------------------
CREATE VIEW project_reporting.vw_monthly_sales AS
WITH rentals AS (
    SELECT d.year_month,
           s.store_id,
           SUM(r.rental_count)                                          AS rentals,
           SUM(r.is_returned)                                           AS returned_rentals,
           SUM(r.is_late)                                               AS late_rentals,
           SUM(CASE WHEN d.is_weekend = 'Y' THEN r.rental_count ELSE 0 END) AS weekend_rentals,
           SUM(CASE WHEN d.is_weekend = 'N' THEN r.rental_count ELSE 0 END) AS weekday_rentals,
           COUNT(DISTINCT c.customer_id)                                AS active_customers
    FROM project_dw.fact_rental r
    JOIN project_dw.dim_date d     ON r.rental_date_key = d.date_key
    JOIN project_dw.dim_store s    ON r.store_key = s.store_key
    JOIN project_dw.dim_customer c ON r.customer_key = c.customer_key
    GROUP BY d.year_month, s.store_id
),
payments AS (
    SELECT d.year_month,
           s.store_id,
           COUNT(*)      AS payments,
           SUM(p.amount) AS revenue
    FROM project_dw.fact_payment p
    JOIN project_dw.dim_date d  ON p.payment_date_key = d.date_key
    JOIN project_dw.dim_store s ON p.store_key = s.store_key
    GROUP BY d.year_month, s.store_id
),
combined AS (
    SELECT COALESCE(r.year_month, p.year_month) AS year_month,
           COALESCE(r.store_id, p.store_id)     AS store_id,
           COALESCE(r.rentals, 0)               AS rentals,
           COALESCE(r.returned_rentals, 0)      AS returned_rentals,
           COALESCE(r.late_rentals, 0)          AS late_rentals,
           COALESCE(r.weekend_rentals, 0)       AS weekend_rentals,
           COALESCE(r.weekday_rentals, 0)       AS weekday_rentals,
           COALESCE(r.active_customers, 0)      AS active_customers,
           COALESCE(p.payments, 0)              AS payments,
           COALESCE(p.revenue, 0)               AS revenue
    FROM rentals r
    FULL OUTER JOIN payments p
      ON r.year_month = p.year_month AND r.store_id = p.store_id
)
SELECT c.year_month,
       LEFT(c.year_month, 4)::INT                     AS year,
       RIGHT(c.year_month, 2)::INT                    AS month_number,
       TO_CHAR(TO_DATE(c.year_month, 'YYYY-MM'), 'FMMonth YYYY') AS month_label,
       c.store_id,
       'Store ' || c.store_id || ' - ' || s.city      AS store_name,
       c.rentals,
       c.returned_rentals,
       c.late_rentals,
       ROUND(100.0 * c.late_rentals / NULLIF(c.returned_rentals, 0), 1) AS late_pct,
       c.weekend_rentals,
       c.weekday_rentals,
       c.active_customers,
       c.payments,
       c.revenue,
       ROUND(c.revenue / NULLIF(c.payments, 0), 2)    AS avg_payment,
       LAG(c.year_month) OVER w                       AS prev_active_month,
       LAG(c.revenue)    OVER w                       AS prev_month_revenue,
       ROUND(100.0 * (c.revenue - LAG(c.revenue) OVER w) / NULLIF(LAG(c.revenue) OVER w, 0), 1) AS revenue_growth_pct
FROM combined c
JOIN project_dw.dim_store s ON s.store_id = c.store_id
WINDOW w AS (PARTITION BY c.store_id ORDER BY c.year_month);

COMMENT ON VIEW project_reporting.vw_monthly_sales IS
  'One row per month per store: rentals, late returns, weekend/weekday split, active customers, revenue and month-on-month revenue growth.';


-- ----------------------------------------------------------------------------
-- 2. vw_product_performance  (grain: one film at one store)
--
-- Combines all three film-related facts: rentals (fact_rental), revenue
-- (fact_payment) and stock (fact_inventory_daily). Films that are not stocked
-- at any store appear once, with store_id = NULL and stock_status = 'Not stocked'.
--
-- stock_status rules (based on the 90 tracked days):
--   Understocked : sold out (0 copies on the shelf) on 10% or more of the days
--   Overstocked  : holds 4 copies but fewer than 15% are rented out on average
--   Balanced     : everything else
-- ----------------------------------------------------------------------------
CREATE VIEW project_reporting.vw_product_performance AS
WITH stock AS (
    SELECT film_key,
           store_key,
           MAX(copies_owned)                                      AS copies_owned,
           COUNT(*)                                               AS days_tracked,
           SUM(CASE WHEN copies_available = 0 THEN 1 ELSE 0 END)  AS sold_out_days,
           SUM(copies_rented_out)                                 AS total_copies_rented_out,
           SUM(copies_owned)                                      AS total_copies_owned
    FROM project_dw.fact_inventory_daily
    GROUP BY film_key, store_key
),
rentals AS (
    SELECT film_key,
           store_key,
           SUM(rental_count) AS rentals,
           SUM(is_returned)  AS returned_rentals,
           SUM(is_late)      AS late_rentals,
           ROUND(AVG(days_rented), 1) AS avg_days_kept
    FROM project_dw.fact_rental
    GROUP BY film_key, store_key
),
revenue AS (
    SELECT film_key,
           store_key,
           SUM(amount) AS revenue
    FROM project_dw.fact_payment
    GROUP BY film_key, store_key
),
cast_size AS (
    SELECT film_key, COUNT(*) AS actor_count
    FROM project_dw.fact_film_cast
    GROUP BY film_key
),
film_store AS (
    -- every film-store pair that has stock, plus one row for each film with no stock
    SELECT film_key, store_key FROM stock
    UNION
    SELECT f.film_key, NULL::INT
    FROM project_dw.dim_film f
    WHERE f.film_key <> -1
      AND NOT EXISTS (SELECT 1 FROM stock st WHERE st.film_key = f.film_key)
)
SELECT f.film_id,
       f.title,
       f.category_name,
       f.rating,
       f.length_band,
       f.rental_rate,
       f.rental_rate_band,
       COALESCE(cs.actor_count, 0)                     AS actor_count,
       s.store_id,
       CASE WHEN s.store_id IS NULL THEN 'Not stocked'
            ELSE 'Store ' || s.store_id || ' - ' || s.city END AS store_name,
       COALESCE(st.copies_owned, 0)                    AS copies_owned,
       COALESCE(r.rentals, 0)                          AS rentals,
       COALESCE(r.returned_rentals, 0)                 AS returned_rentals,
       COALESCE(r.late_rentals, 0)                     AS late_rentals,
       ROUND(100.0 * r.late_rentals / NULLIF(r.returned_rentals, 0), 1) AS late_pct,
       r.avg_days_kept,
       COALESCE(rv.revenue, 0)                         AS revenue,
       ROUND(rv.revenue / NULLIF(st.copies_owned, 0), 2) AS revenue_per_copy,
       COALESCE(st.days_tracked, 0)                    AS days_tracked,
       COALESCE(st.sold_out_days, 0)                   AS sold_out_days,
       ROUND(100.0 * st.sold_out_days / NULLIF(st.days_tracked, 0), 1) AS sold_out_pct,
       COALESCE(st.total_copies_rented_out, 0)         AS total_copies_rented_out,
       COALESCE(st.total_copies_owned, 0)              AS total_copies_owned,
       ROUND(100.0 * st.total_copies_rented_out / NULLIF(st.total_copies_owned, 0), 1) AS utilization_pct,
       CASE
           WHEN st.film_key IS NULL THEN 'Not stocked'
           WHEN 100.0 * st.sold_out_days / st.days_tracked >= 10 THEN 'Understocked'
           WHEN st.copies_owned >= 4
            AND 100.0 * st.total_copies_rented_out / st.total_copies_owned < 15 THEN 'Overstocked'
           ELSE 'Balanced'
       END                                             AS stock_status
FROM film_store fs
JOIN project_dw.dim_film f        ON f.film_key = fs.film_key
LEFT JOIN project_dw.dim_store s  ON s.store_key = fs.store_key
LEFT JOIN stock st                ON st.film_key = fs.film_key AND st.store_key = fs.store_key
LEFT JOIN rentals r               ON r.film_key = fs.film_key AND r.store_key = fs.store_key
LEFT JOIN revenue rv              ON rv.film_key = fs.film_key AND rv.store_key = fs.store_key
LEFT JOIN cast_size cs            ON cs.film_key = fs.film_key;

COMMENT ON VIEW project_reporting.vw_product_performance IS
  'One row per film per store: rentals, late returns, revenue, stock utilization, sold-out days and a stock status label.';


-- ----------------------------------------------------------------------------
-- 3. vw_customer_analysis  (grain: one customer)
--
-- Totals are added up by customer_id, not customer_key, because a customer whose
-- details changed has more than one row in dim_customer (SCD Type 2). Location
-- columns show where the customer lives now (the current row).
--
-- value_segment splits customers into three equal groups by total spend:
--   High   = top third, Medium = middle third, Low = bottom third.
-- ----------------------------------------------------------------------------
CREATE VIEW project_reporting.vw_customer_analysis AS
WITH current_customer AS (
    SELECT customer_id, full_name, email, city, country, home_store_name, is_active
    FROM project_dw.dim_customer
    WHERE is_current = 'Y' AND customer_key <> -1
),
rentals AS (
    SELECT c.customer_id,
           SUM(r.rental_count) AS rentals,
           SUM(r.is_returned)  AS returned_rentals,
           SUM(r.is_late)      AS late_rentals,
           MIN(d.full_date)    AS first_rental_date,
           MAX(d.full_date)    AS last_rental_date
    FROM project_dw.fact_rental r
    JOIN project_dw.dim_customer c ON r.customer_key = c.customer_key
    JOIN project_dw.dim_date d     ON r.rental_date_key = d.date_key
    GROUP BY c.customer_id
),
payments AS (
    SELECT c.customer_id,
           COUNT(*)      AS payments,
           SUM(p.amount) AS total_spent
    FROM project_dw.fact_payment p
    JOIN project_dw.dim_customer c ON p.customer_key = c.customer_key
    GROUP BY c.customer_id
),
favourite AS (
    -- the category each customer rents most (ties broken alphabetically)
    SELECT DISTINCT ON (c.customer_id)
           c.customer_id,
           f.category_name AS favourite_category
    FROM project_dw.fact_rental r
    JOIN project_dw.dim_customer c ON r.customer_key = c.customer_key
    JOIN project_dw.dim_film f     ON r.film_key = f.film_key
    GROUP BY c.customer_id, f.category_name
    ORDER BY c.customer_id, COUNT(*) DESC, f.category_name
),
base AS (
    SELECT cc.customer_id,
           cc.full_name,
           cc.email,
           cc.city,
           cc.country,
           cc.home_store_name,
           cc.is_active,
           COALESCE(r.rentals, 0)          AS rentals,
           COALESCE(r.returned_rentals, 0) AS returned_rentals,
           COALESCE(r.late_rentals, 0)     AS late_rentals,
           r.first_rental_date,
           r.last_rental_date,
           COALESCE(p.payments, 0)         AS payments,
           COALESCE(p.total_spent, 0)      AS total_spent,
           fav.favourite_category
    FROM current_customer cc
    LEFT JOIN rentals r     ON r.customer_id = cc.customer_id
    LEFT JOIN payments p    ON p.customer_id = cc.customer_id
    LEFT JOIN favourite fav ON fav.customer_id = cc.customer_id
)
SELECT b.*,
       ROUND(100.0 * b.late_rentals / NULLIF(b.returned_rentals, 0), 1) AS late_pct,
       ROUND(b.total_spent / NULLIF(b.payments, 0), 2)                  AS avg_payment,
       RANK() OVER (ORDER BY b.total_spent DESC)                        AS spend_rank,
       CASE NTILE(3) OVER (ORDER BY b.total_spent DESC)
            WHEN 1 THEN 'High'
            WHEN 2 THEN 'Medium'
            ELSE 'Low'
       END                                                              AS value_segment
FROM base b;

COMMENT ON VIEW project_reporting.vw_customer_analysis IS
  'One row per customer (current details): rentals, late returns, total spent, favourite category, spend rank and High/Medium/Low value segment.';


-- ----------------------------------------------------------------------------
-- Quick check: row counts of the three views
-- ----------------------------------------------------------------------------
SELECT 'vw_monthly_sales' AS view_name, COUNT(*) AS row_count FROM project_reporting.vw_monthly_sales
UNION ALL
SELECT 'vw_product_performance', COUNT(*) FROM project_reporting.vw_product_performance
UNION ALL
SELECT 'vw_customer_analysis', COUNT(*) FROM project_reporting.vw_customer_analysis;
