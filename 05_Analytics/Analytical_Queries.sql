-- ============================================================================
-- DL3004 Movie Rental DW - Phase 3: Analytical SQL
-- Author : Zahra Saeed (Roll No: 24L-2512)
--
-- One query for each of the 14 business questions in our Business Questions
-- document, plus a summary of the headline KPIs. The queries use the star schema
-- in project_dw and the reporting views in project_reporting (run Views.sql first).
--
-- Techniques used: SUM / AVG / COUNT aggregation, GROUP BY, HAVING, CASE,
-- window functions (LAG, RANK, ROW_NUMBER), CTEs, and drill-across queries that
-- combine two fact tables through shared dimensions.
--
-- Works in pgAdmin's Query Tool (run one query at a time with F5 after
-- selecting it) or all at once with psql:
--   psql -U postgres -h localhost -d sakila_dw -f 05_Analytics/Analytical_Queries.sql
-- ============================================================================


-- ----------------------------------------------------------------------------
-- KPI summary: the headline numbers for the executive dashboard page
-- ----------------------------------------------------------------------------
SELECT (SELECT SUM(amount) FROM project_dw.fact_payment)                           AS total_revenue,
       (SELECT SUM(rental_count) FROM project_dw.fact_rental)                      AS total_rentals,
       (SELECT COUNT(*) FROM project_reporting.vw_customer_analysis)               AS total_customers,
       (SELECT ROUND(AVG(amount), 2) FROM project_dw.fact_payment)                 AS avg_payment,
       (SELECT ROUND(AVG(total_spent), 2)
          FROM project_reporting.vw_customer_analysis)                             AS avg_revenue_per_customer,
       (SELECT ROUND(100.0 * SUM(is_late) / SUM(is_returned), 1)
          FROM project_dw.fact_rental)                                             AS late_return_pct;


-- ----------------------------------------------------------------------------
-- Q1. Monthly rentals and revenue for each store, with month-on-month growth
--     (drill-across: rentals from fact_rental, revenue from fact_payment,
--      combined in vw_monthly_sales; growth uses the LAG window function)
-- ----------------------------------------------------------------------------
SELECT month_label,
       store_name,
       rentals,
       revenue,
       prev_active_month,
       revenue_growth_pct
FROM project_reporting.vw_monthly_sales
ORDER BY store_id, year_month;

-- Q1b. Both stores together, month by month, with growth
SELECT year_month,
       SUM(rentals)                                   AS rentals,
       SUM(revenue)                                   AS revenue,
       LAG(SUM(revenue)) OVER (ORDER BY year_month)   AS prev_month_revenue,
       ROUND(100.0 * (SUM(revenue) - LAG(SUM(revenue)) OVER (ORDER BY year_month))
             / NULLIF(LAG(SUM(revenue)) OVER (ORDER BY year_month), 0), 1) AS revenue_growth_pct
FROM project_reporting.vw_monthly_sales
GROUP BY year_month
ORDER BY year_month;


-- ----------------------------------------------------------------------------
-- Q2. Which film categories bring in the most revenue?
-- ----------------------------------------------------------------------------
SELECT f.category_name,
       SUM(p.amount)                                          AS revenue,
       COUNT(*)                                               AS payments,
       ROUND(100.0 * SUM(p.amount) / SUM(SUM(p.amount)) OVER (), 1) AS share_of_revenue_pct,
       RANK() OVER (ORDER BY SUM(p.amount) DESC)              AS revenue_rank
FROM project_dw.fact_payment p
JOIN project_dw.dim_film f ON p.film_key = f.film_key
GROUP BY f.category_name
ORDER BY revenue DESC;


-- ----------------------------------------------------------------------------
-- Q3. The 20 most rented films, and films that are never rented
-- ----------------------------------------------------------------------------
SELECT f.title,
       f.category_name,
       SUM(r.rental_count) AS rentals
FROM project_dw.fact_rental r
JOIN project_dw.dim_film f ON r.film_key = f.film_key
GROUP BY f.title, f.category_name
ORDER BY rentals DESC, f.title
LIMIT 20;

-- Q3b. Films with copies on the shelf that were never rented
SELECT DISTINCT title, category_name
FROM project_reporting.vw_product_performance
WHERE copies_owned > 0
GROUP BY title, category_name
HAVING SUM(rentals) = 0;

-- Q3c. Films with no copies at any store (cannot be rented at all)
SELECT title, category_name, rating
FROM project_reporting.vw_product_performance
WHERE stock_status = 'Not stocked'
ORDER BY title;


-- ----------------------------------------------------------------------------
-- Q4. Top 10 customers by total amount spent
--     (grouped by customer_id, so a customer with several SCD2 rows is counted once)
-- ----------------------------------------------------------------------------
SELECT spend_rank,
       full_name,
       city,
       country,
       rentals,
       total_spent,
       value_segment
FROM project_reporting.vw_customer_analysis
ORDER BY spend_rank, full_name
LIMIT 10;


-- ----------------------------------------------------------------------------
-- Q5. Countries and cities with the most customers and revenue
--     (where customers live now)
-- ----------------------------------------------------------------------------
SELECT country,
       COUNT(*)          AS customers,
       SUM(total_spent)  AS revenue,
       ROUND(AVG(total_spent), 2) AS avg_spent_per_customer
FROM project_reporting.vw_customer_analysis
GROUP BY country
ORDER BY revenue DESC
LIMIT 10;

SELECT city,
       country,
       COUNT(*)         AS customers,
       SUM(total_spent) AS revenue
FROM project_reporting.vw_customer_analysis
GROUP BY city, country
ORDER BY revenue DESC
LIMIT 10;


-- ----------------------------------------------------------------------------
-- Q6. Percentage of returned rentals that came back late, by category and by store
--     (late % = late rentals / returned rentals; unreturned films are not counted)
-- ----------------------------------------------------------------------------
SELECT category_name,
       SUM(returned_rentals) AS returned_rentals,
       SUM(late_rentals)     AS late_rentals,
       ROUND(100.0 * SUM(late_rentals) / NULLIF(SUM(returned_rentals), 0), 1) AS late_pct
FROM project_reporting.vw_product_performance
GROUP BY category_name
ORDER BY late_pct DESC;

SELECT store_name,
       SUM(returned_rentals) AS returned_rentals,
       SUM(late_rentals)     AS late_rentals,
       ROUND(100.0 * SUM(late_rentals) / NULLIF(SUM(returned_rentals), 0), 1) AS late_pct
FROM project_reporting.vw_product_performance
WHERE store_id IS NOT NULL
GROUP BY store_name
ORDER BY store_name;

-- Q6b. Late rate by allowed rental period: is the short loan period the cause?
SELECT f.allowed_rental_days,
       SUM(r.is_returned) AS returned_rentals,
       ROUND(100.0 * SUM(r.is_late) / NULLIF(SUM(r.is_returned), 0), 1) AS late_pct,
       ROUND(AVG(r.days_rented), 1) AS avg_days_kept
FROM project_dw.fact_rental r
JOIN project_dw.dim_film f ON r.film_key = f.film_key
GROUP BY f.allowed_rental_days
ORDER BY f.allowed_rental_days;


-- ----------------------------------------------------------------------------
-- Q7. Overstocked films: many copies but rarely rented out
-- ----------------------------------------------------------------------------
SELECT title,
       store_name,
       copies_owned,
       rentals,
       utilization_pct
FROM project_reporting.vw_product_performance
WHERE stock_status = 'Overstocked'
ORDER BY utilization_pct, title
LIMIT 15;

-- Q7b. How many film-store pairs fall into each stock status
SELECT stock_status,
       COUNT(*)            AS film_store_pairs,
       SUM(copies_owned)   AS copies,
       SUM(rentals)        AS rentals
FROM project_reporting.vw_product_performance
GROUP BY stock_status
ORDER BY stock_status;


-- ----------------------------------------------------------------------------
-- Q8. Understocked films: often no copies left on the shelf
-- ----------------------------------------------------------------------------
SELECT title,
       store_name,
       copies_owned,
       sold_out_days,
       days_tracked,
       sold_out_pct
FROM project_reporting.vw_product_performance
WHERE stock_status = 'Understocked'
ORDER BY sold_out_pct DESC, title
LIMIT 15;

-- Q8b. Sold-out rate by number of copies held
SELECT copies_owned,
       COUNT(*) AS film_store_pairs,
       ROUND(100.0 * SUM(sold_out_days) / SUM(days_tracked), 1) AS sold_out_pct,
       ROUND(100.0 * SUM(total_copies_rented_out) / SUM(total_copies_owned), 1) AS utilization_pct
FROM project_reporting.vw_product_performance
WHERE copies_owned > 0
GROUP BY copies_owned
ORDER BY copies_owned;


-- ----------------------------------------------------------------------------
-- Q9. Are weekends busier than weekdays?
--     (compare the average per day, because there are 5 weekdays and only 2 weekend days)
--     Note: Sakila only has rentals on 41 days, recorded in blocks of consecutive
--     days. Several blocks start or end on a Tuesday with very few rentals, which
--     pulls the Tuesday (and so the weekday) average down. See Q9b.
-- ----------------------------------------------------------------------------
SELECT CASE d.is_weekend WHEN 'Y' THEN 'Weekend' ELSE 'Weekday' END AS day_type,
       SUM(r.rental_count)            AS rentals,
       COUNT(DISTINCT d.date_key)     AS days_with_rentals,
       ROUND(1.0 * SUM(r.rental_count) / COUNT(DISTINCT d.date_key), 1) AS avg_rentals_per_day
FROM project_dw.fact_rental r
JOIN project_dw.dim_date d ON r.rental_date_key = d.date_key
GROUP BY d.is_weekend
ORDER BY day_type;

-- Q9b. The same by day of the week
SELECT d.day_of_week,
       d.day_name,
       SUM(r.rental_count)        AS rentals,
       COUNT(DISTINCT d.date_key) AS days_with_rentals,
       ROUND(1.0 * SUM(r.rental_count) / COUNT(DISTINCT d.date_key), 1) AS avg_rentals_per_day
FROM project_dw.fact_rental r
JOIN project_dw.dim_date d ON r.rental_date_key = d.date_key
GROUP BY d.day_of_week, d.day_name
ORDER BY d.day_of_week;


-- ----------------------------------------------------------------------------
-- Q10. Staff workload: rentals and payments handled by each staff member
--      (drill-across: each fact is summarised by staff first, then joined)
-- ----------------------------------------------------------------------------
WITH r AS (
    SELECT staff_key, SUM(rental_count) AS rentals
    FROM project_dw.fact_rental
    GROUP BY staff_key
),
p AS (
    SELECT staff_key, COUNT(*) AS payments, SUM(amount) AS amount_taken
    FROM project_dw.fact_payment
    GROUP BY staff_key
)
SELECT st.full_name,
       st.home_store_name,
       r.rentals,
       p.payments,
       p.amount_taken,
       ROUND(100.0 * r.rentals / SUM(r.rentals) OVER (), 1) AS share_of_rentals_pct
FROM project_dw.dim_staff st
JOIN r ON r.staff_key = st.staff_key
JOIN p ON p.staff_key = st.staff_key
ORDER BY st.full_name;


-- ----------------------------------------------------------------------------
-- Q11. Does the film rating affect rentals and revenue?
--      (divided by the number of films, since some ratings have more films)
-- ----------------------------------------------------------------------------
SELECT rating,
       COUNT(DISTINCT film_id) AS films,
       SUM(rentals)            AS rentals,
       SUM(revenue)            AS revenue,
       ROUND(1.0 * SUM(rentals) / COUNT(DISTINCT film_id), 1) AS rentals_per_film,
       ROUND(SUM(revenue) / COUNT(DISTINCT film_id), 2)       AS revenue_per_film
FROM project_reporting.vw_product_performance
GROUP BY rating
ORDER BY revenue_per_film DESC;


-- ----------------------------------------------------------------------------
-- Q12. Actors in the most films, and whether their films rent more than average
--      (uses the factless fact table fact_film_cast)
-- ----------------------------------------------------------------------------
WITH film_rentals AS (
    SELECT f.film_key,
           COALESCE(SUM(r.rental_count), 0) AS rentals
    FROM project_dw.dim_film f
    LEFT JOIN project_dw.fact_rental r ON r.film_key = f.film_key
    WHERE f.film_key <> -1
    GROUP BY f.film_key
),
overall AS (
    SELECT ROUND(AVG(rentals), 1) AS avg_rentals_per_film FROM film_rentals
)
SELECT a.full_name,
       COUNT(*)                     AS films,
       ROUND(AVG(fr.rentals), 1)    AS avg_rentals_per_film,
       o.avg_rentals_per_film       AS overall_avg,
       CASE WHEN AVG(fr.rentals) > o.avg_rentals_per_film THEN 'Above average'
            ELSE 'Below average' END AS compared_with_average
FROM project_dw.fact_film_cast fc
JOIN project_dw.dim_actor a ON fc.actor_key = a.actor_key
JOIN film_rentals fr        ON fc.film_key = fr.film_key
CROSS JOIN overall o
GROUP BY a.actor_key, a.full_name, o.avg_rentals_per_film
ORDER BY films DESC, a.full_name
LIMIT 10;

-- Q12b. Actors whose films are rented the most on average (at least 20 films)
WITH film_rentals AS (
    SELECT f.film_key, COALESCE(SUM(r.rental_count), 0) AS rentals
    FROM project_dw.dim_film f
    LEFT JOIN project_dw.fact_rental r ON r.film_key = f.film_key
    WHERE f.film_key <> -1
    GROUP BY f.film_key
)
SELECT a.full_name,
       COUNT(*)                  AS films,
       ROUND(AVG(fr.rentals), 1) AS avg_rentals_per_film
FROM project_dw.fact_film_cast fc
JOIN project_dw.dim_actor a ON fc.actor_key = a.actor_key
JOIN film_rentals fr        ON fc.film_key = fr.film_key
GROUP BY a.actor_key, a.full_name
HAVING COUNT(*) >= 20
ORDER BY avg_rentals_per_film DESC
LIMIT 10;


-- ----------------------------------------------------------------------------
-- Q13. Revenue by city using where the customer lived ON THE PAYMENT DATE
--      A direct join on customer_key gives the customer version that was valid
--      when the payment was made (SCD Type 2). Compare with Q5 (current city).
-- ----------------------------------------------------------------------------
SELECT c.country,
       c.city,
       SUM(p.amount) AS revenue_at_time_of_payment
FROM project_dw.fact_payment p
JOIN project_dw.dim_customer c ON p.customer_key = c.customer_key
GROUP BY c.country, c.city
ORDER BY revenue_at_time_of_payment DESC
LIMIT 10;

-- Q13b. Where the two methods give different answers (cities affected by a move)
WITH historical AS (
    SELECT c.city, c.country, SUM(p.amount) AS revenue
    FROM project_dw.fact_payment p
    JOIN project_dw.dim_customer c ON p.customer_key = c.customer_key
    GROUP BY c.city, c.country
),
current_city AS (
    SELECT city, country, SUM(total_spent) AS revenue
    FROM project_reporting.vw_customer_analysis
    GROUP BY city, country
)
SELECT COALESCE(h.city, cc.city)       AS city,
       COALESCE(h.country, cc.country) AS country,
       COALESCE(h.revenue, 0)          AS revenue_at_time_of_payment,
       COALESCE(cc.revenue, 0)         AS revenue_by_current_city,
       COALESCE(h.revenue, 0) - COALESCE(cc.revenue, 0) AS difference
FROM historical h
FULL OUTER JOIN current_city cc ON h.city = cc.city AND h.country = cc.country
WHERE COALESCE(h.revenue, 0) <> COALESCE(cc.revenue, 0)
ORDER BY city;


-- ----------------------------------------------------------------------------
-- Q14. Customer value segments: how many customers in each, and their revenue
-- ----------------------------------------------------------------------------
SELECT value_segment,
       COUNT(*)                          AS customers,
       MIN(total_spent)                  AS min_spent,
       MAX(total_spent)                  AS max_spent,
       ROUND(AVG(total_spent), 2)        AS avg_spent,
       ROUND(AVG(rentals), 1)            AS avg_rentals,
       SUM(total_spent)                  AS revenue,
       ROUND(100.0 * SUM(total_spent) / SUM(SUM(total_spent)) OVER (), 1) AS share_of_revenue_pct,
       ROUND(100.0 * SUM(late_rentals) / NULLIF(SUM(returned_rentals), 0), 1) AS late_pct
FROM project_reporting.vw_customer_analysis
GROUP BY value_segment
ORDER BY avg_spent DESC;

-- Q14b. Favourite category of the High value customers
SELECT favourite_category,
       COUNT(*) AS high_value_customers
FROM project_reporting.vw_customer_analysis
WHERE value_segment = 'High'
GROUP BY favourite_category
ORDER BY high_value_customers DESC, favourite_category
LIMIT 5;
