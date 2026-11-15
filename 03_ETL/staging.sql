-- ============================================================================
-- DL3004 Movie Rental DW - Step 2 of the ETL pipeline: staging cleaning
-- Schema : project_staging (PostgreSQL)
-- Input  : project_staging.raw_<table>  (text copies of the CSV files,
--          created by 03_ETL/load_staging.py)
-- Output : project_staging.stg_<table>  (clean, typed tables)
--
-- Cleaning rules (Business Requirements Document, section 7):
--   1. Remove duplicates by natural key (keep the newest copy)
--   2. Handle NULLs   : blank postal code / district -> 'Unknown',
--                       payment.rental_id NULL -> -1,
--                       return_date NULL is kept (NULL = not returned yet)
--   3. Standardise    : names and titles -> proper case, text trimmed,
--                       emails -> lower case
--   4. Convert types  : text -> INT, DATE, TIMESTAMP, NUMERIC, BOOLEAN;
--                       special_features -> comma-separated text
--
-- Run from the repo root:
--   psql -U postgres -h localhost -d <your_database> -f 03_ETL/staging.sql
-- Safe to re-run: every stg_ table is dropped and rebuilt.
-- ============================================================================

\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

CREATE SCHEMA IF NOT EXISTS project_staging;
SET search_path = project_staging;

BEGIN;

DROP TABLE IF EXISTS stg_payment, stg_rental, stg_inventory, stg_film_actor,
                     stg_film_category, stg_film, stg_customer, stg_staff,
                     stg_store, stg_address, stg_city, stg_country,
                     stg_language, stg_category, stg_actor;

-- ----------------------------------------------------------------------------
-- Lookup tables
-- ----------------------------------------------------------------------------

-- ACTOR: names to proper case
CREATE TABLE stg_actor (
    actor_id   INT PRIMARY KEY,
    first_name VARCHAR(45) NOT NULL,
    last_name  VARCHAR(45) NOT NULL
);
INSERT INTO stg_actor
SELECT DISTINCT ON (actor_id::INT)
       actor_id::INT,
       INITCAP(TRIM(first_name)),
       INITCAP(TRIM(last_name))
FROM raw_actor
ORDER BY actor_id::INT, last_update::TIMESTAMP DESC;

-- CATEGORY
CREATE TABLE stg_category (
    category_id INT PRIMARY KEY,
    name        VARCHAR(25) NOT NULL
);
INSERT INTO stg_category
SELECT DISTINCT ON (category_id::INT)
       category_id::INT,
       TRIM(name)
FROM raw_category
ORDER BY category_id::INT, last_update::TIMESTAMP DESC;

-- COUNTRY
CREATE TABLE stg_country (
    country_id INT PRIMARY KEY,
    country    VARCHAR(50) NOT NULL
);
INSERT INTO stg_country
SELECT DISTINCT ON (country_id::INT)
       country_id::INT,
       TRIM(country)
FROM raw_country
ORDER BY country_id::INT, last_update::TIMESTAMP DESC;

-- CITY
CREATE TABLE stg_city (
    city_id    INT PRIMARY KEY,
    city       VARCHAR(50) NOT NULL,
    country_id INT NOT NULL
);
INSERT INTO stg_city
SELECT DISTINCT ON (city_id::INT)
       city_id::INT,
       TRIM(city),
       country_id::INT
FROM raw_city
ORDER BY city_id::INT, last_update::TIMESTAMP DESC;

-- LANGUAGE: the source column is CHAR(20), so names carry trailing spaces
CREATE TABLE stg_language (
    language_id INT PRIMARY KEY,
    name        VARCHAR(20) NOT NULL
);
INSERT INTO stg_language
SELECT DISTINCT ON (language_id::INT)
       language_id::INT,
       TRIM(name)
FROM raw_language
ORDER BY language_id::INT, last_update::TIMESTAMP DESC;

-- ADDRESS: blank postal code / district -> 'Unknown'. address2 and phone are
-- not used by the warehouse and are left out.
CREATE TABLE stg_address (
    address_id  INT PRIMARY KEY,
    address     VARCHAR(50) NOT NULL,
    district    VARCHAR(20) NOT NULL,
    city_id     INT NOT NULL,
    postal_code VARCHAR(10) NOT NULL
);
INSERT INTO stg_address
SELECT DISTINCT ON (address_id::INT)
       address_id::INT,
       TRIM(address),
       COALESCE(NULLIF(TRIM(district), ''), 'Unknown'),
       city_id::INT,
       COALESCE(NULLIF(TRIM(postal_code), ''), 'Unknown')
FROM raw_address
ORDER BY address_id::INT, last_update::TIMESTAMP DESC;

-- ----------------------------------------------------------------------------
-- Stores, staff, customers
-- ----------------------------------------------------------------------------

CREATE TABLE stg_store (
    store_id         INT PRIMARY KEY,
    manager_staff_id INT NOT NULL,
    address_id       INT NOT NULL
);
INSERT INTO stg_store
SELECT DISTINCT ON (store_id::INT)
       store_id::INT,
       manager_staff_id::INT,
       address_id::INT
FROM raw_store
ORDER BY store_id::INT, last_update::TIMESTAMP DESC;

-- STAFF: password and picture were already left out by the loader
CREATE TABLE stg_staff (
    staff_id   INT PRIMARY KEY,
    first_name VARCHAR(45) NOT NULL,
    last_name  VARCHAR(45) NOT NULL,
    address_id INT NOT NULL,
    email      VARCHAR(50) NOT NULL,
    store_id   INT NOT NULL,
    active     BOOLEAN NOT NULL
);
INSERT INTO stg_staff
SELECT DISTINCT ON (staff_id::INT)
       staff_id::INT,
       INITCAP(TRIM(first_name)),
       INITCAP(TRIM(last_name)),
       address_id::INT,
       LOWER(TRIM(email)),
       store_id::INT,
       (LOWER(TRIM(active)) IN ('t', 'true', '1'))
FROM raw_staff
ORDER BY staff_id::INT, last_update::TIMESTAMP DESC;

CREATE TABLE stg_customer (
    customer_id INT PRIMARY KEY,
    store_id    INT NOT NULL,
    first_name  VARCHAR(45) NOT NULL,
    last_name   VARCHAR(45) NOT NULL,
    email       VARCHAR(50) NOT NULL,
    address_id  INT NOT NULL,
    active      INT NOT NULL,
    create_date DATE NOT NULL
);
INSERT INTO stg_customer
SELECT DISTINCT ON (customer_id::INT)
       customer_id::INT,
       store_id::INT,
       INITCAP(TRIM(first_name)),
       INITCAP(TRIM(last_name)),
       LOWER(TRIM(email)),
       address_id::INT,
       active::INT,
       create_date::DATE
FROM raw_customer
ORDER BY customer_id::INT, last_update::TIMESTAMP DESC;

-- ----------------------------------------------------------------------------
-- Films
-- ----------------------------------------------------------------------------

-- FILM: special_features arrives as a PostgreSQL array literal text,
--   {"Deleted Scenes","Behind the Scenes"}  ->  Deleted Scenes,Behind the Scenes
CREATE TABLE stg_film (
    film_id          INT PRIMARY KEY,
    title            VARCHAR(255) NOT NULL,
    release_year     INT,
    language_id      INT NOT NULL,
    rental_duration  INT NOT NULL,
    rental_rate      NUMERIC(4,2) NOT NULL,
    length           INT,
    replacement_cost NUMERIC(5,2) NOT NULL,
    rating           VARCHAR(5),
    special_features VARCHAR(100)
);
INSERT INTO stg_film
SELECT DISTINCT ON (film_id::INT)
       film_id::INT,
       INITCAP(TRIM(title)),
       release_year::INT,
       language_id::INT,
       rental_duration::INT,
       rental_rate::NUMERIC(4,2),
       length::INT,
       replacement_cost::NUMERIC(5,2),
       TRIM(rating),
       NULLIF(REGEXP_REPLACE(TRIM(special_features), '[{}"]', '', 'g'), '')
FROM raw_film
ORDER BY film_id::INT, last_update::TIMESTAMP DESC;

CREATE TABLE stg_film_category (
    film_id     INT NOT NULL,
    category_id INT NOT NULL,
    PRIMARY KEY (film_id, category_id)
);
INSERT INTO stg_film_category
SELECT DISTINCT ON (film_id::INT, category_id::INT)
       film_id::INT,
       category_id::INT
FROM raw_film_category
ORDER BY film_id::INT, category_id::INT, last_update::TIMESTAMP DESC;

CREATE TABLE stg_film_actor (
    actor_id INT NOT NULL,
    film_id  INT NOT NULL,
    PRIMARY KEY (actor_id, film_id)
);
INSERT INTO stg_film_actor
SELECT DISTINCT ON (actor_id::INT, film_id::INT)
       actor_id::INT,
       film_id::INT
FROM raw_film_actor
ORDER BY actor_id::INT, film_id::INT, last_update::TIMESTAMP DESC;

-- ----------------------------------------------------------------------------
-- Inventory, rentals, payments
-- ----------------------------------------------------------------------------

CREATE TABLE stg_inventory (
    inventory_id INT PRIMARY KEY,
    film_id      INT NOT NULL,
    store_id     INT NOT NULL
);
INSERT INTO stg_inventory
SELECT DISTINCT ON (inventory_id::INT)
       inventory_id::INT,
       film_id::INT,
       store_id::INT
FROM raw_inventory
ORDER BY inventory_id::INT, last_update::TIMESTAMP DESC;

-- RENTAL: return_date stays NULL when the film has not come back yet. The
-- warehouse load turns that into return_date_key = -1 (see Data Dictionary).
CREATE TABLE stg_rental (
    rental_id    INT PRIMARY KEY,
    rental_date  TIMESTAMP NOT NULL,
    inventory_id INT NOT NULL,
    customer_id  INT NOT NULL,
    return_date  TIMESTAMP,
    staff_id     INT NOT NULL
);
INSERT INTO stg_rental
SELECT DISTINCT ON (rental_id::INT)
       rental_id::INT,
       rental_date::TIMESTAMP,
       inventory_id::INT,
       customer_id::INT,
       return_date::TIMESTAMP,
       staff_id::INT
FROM raw_rental
ORDER BY rental_id::INT, last_update::TIMESTAMP DESC;

-- PAYMENT: a payment without a rental gets rental_id = -1
CREATE TABLE stg_payment (
    payment_id   INT PRIMARY KEY,
    customer_id  INT NOT NULL,
    staff_id     INT NOT NULL,
    rental_id    INT NOT NULL,
    amount       NUMERIC(5,2) NOT NULL,
    payment_date TIMESTAMP NOT NULL
);
INSERT INTO stg_payment
SELECT DISTINCT ON (payment_id::INT)
       payment_id::INT,
       customer_id::INT,
       staff_id::INT,
       COALESCE(rental_id::INT, -1),
       amount::NUMERIC(5,2),
       payment_date::TIMESTAMP
FROM raw_payment
ORDER BY payment_id::INT, payment_date::TIMESTAMP DESC;

COMMIT;

-- ============================================================================
-- Before / after row counts (for the Data Cleaning Report)
-- duplicates_removed = rows_before - rows_after
-- ============================================================================
SELECT table_name, rows_before, rows_after, rows_before - rows_after AS duplicates_removed
FROM (
    SELECT 'actor' AS table_name, (SELECT COUNT(*) FROM raw_actor) AS rows_before, (SELECT COUNT(*) FROM stg_actor) AS rows_after UNION ALL
    SELECT 'address',       (SELECT COUNT(*) FROM raw_address),       (SELECT COUNT(*) FROM stg_address)       UNION ALL
    SELECT 'category',      (SELECT COUNT(*) FROM raw_category),      (SELECT COUNT(*) FROM stg_category)      UNION ALL
    SELECT 'city',          (SELECT COUNT(*) FROM raw_city),          (SELECT COUNT(*) FROM stg_city)          UNION ALL
    SELECT 'country',       (SELECT COUNT(*) FROM raw_country),       (SELECT COUNT(*) FROM stg_country)       UNION ALL
    SELECT 'customer',      (SELECT COUNT(*) FROM raw_customer),      (SELECT COUNT(*) FROM stg_customer)      UNION ALL
    SELECT 'film',          (SELECT COUNT(*) FROM raw_film),          (SELECT COUNT(*) FROM stg_film)          UNION ALL
    SELECT 'film_actor',    (SELECT COUNT(*) FROM raw_film_actor),    (SELECT COUNT(*) FROM stg_film_actor)    UNION ALL
    SELECT 'film_category', (SELECT COUNT(*) FROM raw_film_category), (SELECT COUNT(*) FROM stg_film_category) UNION ALL
    SELECT 'inventory',     (SELECT COUNT(*) FROM raw_inventory),     (SELECT COUNT(*) FROM stg_inventory)     UNION ALL
    SELECT 'language',      (SELECT COUNT(*) FROM raw_language),      (SELECT COUNT(*) FROM stg_language)      UNION ALL
    SELECT 'payment',       (SELECT COUNT(*) FROM raw_payment),       (SELECT COUNT(*) FROM stg_payment)       UNION ALL
    SELECT 'rental',        (SELECT COUNT(*) FROM raw_rental),        (SELECT COUNT(*) FROM stg_rental)        UNION ALL
    SELECT 'staff',         (SELECT COUNT(*) FROM raw_staff),         (SELECT COUNT(*) FROM stg_staff)         UNION ALL
    SELECT 'store',         (SELECT COUNT(*) FROM raw_store),         (SELECT COUNT(*) FROM stg_store)
) t
ORDER BY table_name;
