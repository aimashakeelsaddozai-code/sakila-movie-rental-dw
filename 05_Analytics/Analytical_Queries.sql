--Analytical_Queries.sql - answers to the 14 business questions, run Views.sql first (Zahra Saeed)
SELECT (SELECT SUM(amount) FROM project_dw.fact_payment)                           AS total_revenue,  --kpis for the dashboard: revenue, rentals, customers
       (SELECT SUM(rental_count) FROM project_dw.fact_rental)                      AS total_rentals,
       (SELECT COUNT(*) FROM project_reporting.vw_customer_analysis)               AS total_customers,
       (SELECT ROUND(AVG(amount), 2) FROM project_dw.fact_payment)                 AS avg_payment,
       (SELECT ROUND(AVG(total_spent), 2)
          FROM project_reporting.vw_customer_analysis)                             AS avg_revenue_per_customer,
       (SELECT ROUND(100.0 * SUM(is_late) / SUM(is_returned), 1)  --late out of returned rentals
          FROM project_dw.fact_rental)                                             AS late_return_pct;

SELECT month_label,  --Q1 monthly rentals and revenue per store with growth
       store_name,
       rentals,
       revenue,
       prev_active_month,
       revenue_growth_pct
FROM project_reporting.vw_monthly_sales
ORDER BY store_id, year_month;

SELECT year_month,  --Q1b both stores together
       SUM(rentals)                                   AS rentals,
       SUM(revenue)                                   AS revenue,
       LAG(SUM(revenue)) OVER (ORDER BY year_month)   AS prev_month_revenue,  --last month's revenue
       ROUND(100.0 * (SUM(revenue) - LAG(SUM(revenue)) OVER (ORDER BY year_month))
             / NULLIF(LAG(SUM(revenue)) OVER (ORDER BY year_month), 0), 1) AS revenue_growth_pct
FROM project_reporting.vw_monthly_sales
GROUP BY year_month
ORDER BY year_month;

SELECT f.category_name,  --Q2 revenue by category
       SUM(p.amount)                                          AS revenue,
       COUNT(*)                                               AS payments,
       ROUND(100.0 * SUM(p.amount) / SUM(SUM(p.amount)) OVER (), 1) AS share_of_revenue_pct,  --share of total revenue
       RANK() OVER (ORDER BY SUM(p.amount) DESC)              AS revenue_rank  --1 = top category
FROM project_dw.fact_payment p
JOIN project_dw.dim_film f ON p.film_key = f.film_key
GROUP BY f.category_name
ORDER BY revenue DESC;

SELECT f.title,  --Q3 top 20 most rented films
       f.category_name,
       SUM(r.rental_count) AS rentals
FROM project_dw.fact_rental r
JOIN project_dw.dim_film f ON r.film_key = f.film_key
GROUP BY f.title, f.category_name
ORDER BY rentals DESC, f.title
LIMIT 20;

SELECT DISTINCT title, category_name  --Q3b stocked films that were never rented (comes back empty)
FROM project_reporting.vw_product_performance
WHERE copies_owned > 0
GROUP BY title, category_name
HAVING SUM(rentals) = 0;

SELECT title, category_name, rating  --Q3c films with no copies at all
FROM project_reporting.vw_product_performance
WHERE stock_status = 'Not stocked'
ORDER BY title;

SELECT spend_rank,  --Q4 top 10 customers by spend
       full_name,
       city,
       country,
       rentals,
       total_spent,
       value_segment
FROM project_reporting.vw_customer_analysis
ORDER BY spend_rank, full_name
LIMIT 10;

SELECT country,  --Q5 countries with the most customers and revenue (current address)
       COUNT(*)          AS customers,
       SUM(total_spent)  AS revenue,
       ROUND(AVG(total_spent), 2) AS avg_spent_per_customer
FROM project_reporting.vw_customer_analysis
GROUP BY country
ORDER BY revenue DESC
LIMIT 10;

SELECT city,  --Q5b same by city
       country,
       COUNT(*)         AS customers,
       SUM(total_spent) AS revenue
FROM project_reporting.vw_customer_analysis
GROUP BY city, country
ORDER BY revenue DESC
LIMIT 10;

SELECT category_name,  --Q6 late returns by category
       SUM(returned_rentals) AS returned_rentals,
       SUM(late_rentals)     AS late_rentals,
       ROUND(100.0 * SUM(late_rentals) / NULLIF(SUM(returned_rentals), 0), 1) AS late_pct  --late out of returned, not out of all
FROM project_reporting.vw_product_performance
GROUP BY category_name
ORDER BY late_pct DESC;

SELECT store_name,  --Q6b late returns by store
       SUM(returned_rentals) AS returned_rentals,
       SUM(late_rentals)     AS late_rentals,
       ROUND(100.0 * SUM(late_rentals) / NULLIF(SUM(returned_rentals), 0), 1) AS late_pct
FROM project_reporting.vw_product_performance
WHERE store_id IS NOT NULL
GROUP BY store_name
ORDER BY store_name;

SELECT f.allowed_rental_days,  --Q6c late rate by loan period, this is where the real cause shows
       SUM(r.is_returned) AS returned_rentals,
       ROUND(100.0 * SUM(r.is_late) / NULLIF(SUM(r.is_returned), 0), 1) AS late_pct,
       ROUND(AVG(r.days_rented), 1) AS avg_days_kept
FROM project_dw.fact_rental r
JOIN project_dw.dim_film f ON r.film_key = f.film_key
GROUP BY f.allowed_rental_days
ORDER BY f.allowed_rental_days;

SELECT title,  --Q7 overstocked films
       store_name,
       copies_owned,
       rentals,
       utilization_pct
FROM project_reporting.vw_product_performance
WHERE stock_status = 'Overstocked'
ORDER BY utilization_pct, title
LIMIT 15;

SELECT stock_status,  --Q7b how many films fall in each stock status
       COUNT(*)            AS film_store_pairs,
       SUM(copies_owned)   AS copies,
       SUM(rentals)        AS rentals
FROM project_reporting.vw_product_performance
GROUP BY stock_status
ORDER BY stock_status;

SELECT title,  --Q8 understocked films
       store_name,
       copies_owned,
       sold_out_days,
       days_tracked,
       sold_out_pct
FROM project_reporting.vw_product_performance
WHERE stock_status = 'Understocked'
ORDER BY sold_out_pct DESC, title
LIMIT 15;

SELECT copies_owned,  --Q8b sold out days by number of copies
       COUNT(*) AS film_store_pairs,
       ROUND(100.0 * SUM(sold_out_days) / SUM(days_tracked), 1) AS sold_out_pct,
       ROUND(100.0 * SUM(total_copies_rented_out) / SUM(total_copies_owned), 1) AS utilization_pct
FROM project_reporting.vw_product_performance
WHERE copies_owned > 0
GROUP BY copies_owned
ORDER BY copies_owned;

SELECT CASE d.is_weekend WHEN 'Y' THEN 'Weekend' ELSE 'Weekday' END AS day_type,  --Q9 weekend vs weekday, average per day not total
       SUM(r.rental_count)            AS rentals,
       COUNT(DISTINCT d.date_key)     AS days_with_rentals,
       ROUND(1.0 * SUM(r.rental_count) / COUNT(DISTINCT d.date_key), 1) AS avg_rentals_per_day
FROM project_dw.fact_rental r
JOIN project_dw.dim_date d ON r.rental_date_key = d.date_key
GROUP BY d.is_weekend
ORDER BY day_type;

SELECT d.day_of_week,  --Q9b by day of the week
       d.day_name,
       SUM(r.rental_count)        AS rentals,
       COUNT(DISTINCT d.date_key) AS days_with_rentals,
       ROUND(1.0 * SUM(r.rental_count) / COUNT(DISTINCT d.date_key), 1) AS avg_rentals_per_day
FROM project_dw.fact_rental r
JOIN project_dw.dim_date d ON r.rental_date_key = d.date_key
GROUP BY d.day_of_week, d.day_name
ORDER BY d.day_of_week;

WITH r AS (  --Q10 staff workload, rentals and payments summed separately first
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
       ROUND(100.0 * r.rentals / SUM(r.rentals) OVER (), 1) AS share_of_rentals_pct  --share of all rentals
FROM project_dw.dim_staff st
JOIN r ON r.staff_key = st.staff_key
JOIN p ON p.staff_key = st.staff_key
ORDER BY st.full_name;

SELECT rating,  --Q11 does rating matter, per film so bigger ratings dont win just by size
       COUNT(DISTINCT film_id) AS films,
       SUM(rentals)            AS rentals,
       SUM(revenue)            AS revenue,
       ROUND(1.0 * SUM(rentals) / COUNT(DISTINCT film_id), 1) AS rentals_per_film,
       ROUND(SUM(revenue) / COUNT(DISTINCT film_id), 2)       AS revenue_per_film
FROM project_reporting.vw_product_performance
GROUP BY rating
ORDER BY revenue_per_film DESC;

WITH film_rentals AS (  --Q12 actors in the most films vs the average film
    SELECT f.film_key,
           COALESCE(SUM(r.rental_count), 0) AS rentals  --films with 0 rentals count too
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
CROSS JOIN overall o  --same average on every row
GROUP BY a.actor_key, a.full_name, o.avg_rentals_per_film
ORDER BY films DESC, a.full_name
LIMIT 10;

WITH film_rentals AS (  --Q12b actors whose films rent the most (20+ films)
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

SELECT c.country,  --Q13 revenue by where the customer lived when they paid (scd2)
       c.city,
       SUM(p.amount) AS revenue_at_time_of_payment
FROM project_dw.fact_payment p
JOIN project_dw.dim_customer c ON p.customer_key = c.customer_key  --direct key join gives the old version
GROUP BY c.country, c.city
ORDER BY revenue_at_time_of_payment DESC
LIMIT 10;

WITH historical AS (  --Q13b where that differs from the current city
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
FULL OUTER JOIN current_city cc ON h.city = cc.city AND h.country = cc.country  --full join so cities on either side show up
WHERE COALESCE(h.revenue, 0) <> COALESCE(cc.revenue, 0)
ORDER BY city;

SELECT value_segment,  --Q14 high / medium / low value customers
       COUNT(*)                          AS customers,
       MIN(total_spent)                  AS min_spent,
       MAX(total_spent)                  AS max_spent,
       ROUND(AVG(total_spent), 2)        AS avg_spent,
       ROUND(AVG(rentals), 1)            AS avg_rentals,
       SUM(total_spent)                  AS revenue,
       ROUND(100.0 * SUM(total_spent) / SUM(SUM(total_spent)) OVER (), 1) AS share_of_revenue_pct,  --share of total revenue
       ROUND(100.0 * SUM(late_rentals) / NULLIF(SUM(returned_rentals), 0), 1) AS late_pct
FROM project_reporting.vw_customer_analysis
GROUP BY value_segment
ORDER BY avg_spent DESC;

SELECT favourite_category,  --Q14b favourite categories of high value customers
       COUNT(*) AS high_value_customers
FROM project_reporting.vw_customer_analysis
WHERE value_segment = 'High'
GROUP BY favourite_category
ORDER BY high_value_customers DESC, favourite_category
LIMIT 5;
