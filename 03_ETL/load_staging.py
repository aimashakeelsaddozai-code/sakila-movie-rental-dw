# Step 1 of the ETL pipeline: load the raw Sakila CSV files into project_staging.
# Needs: pip install pandas sqlalchemy psycopg2-binary
#
# Each CSV in 02_Data/raw_data becomes a text table project_staging.raw_<table>.
# Cleaning and type conversion happen in the next step (03_ETL/staging.sql).
#
# Settings (environment variables):
#   PGPASSWORD (required), PGDATABASE (required: your PostgreSQL database name),
#   PGUSER (default postgres), PGHOST (default localhost), PGPORT (default 5432)
#
# Run from the repo root:  python 03_ETL/load_staging.py
# Safe to re-run: the raw_ tables are replaced each time.

import os
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

RAW_DIR = Path(__file__).resolve().parent.parent / "02_Data" / "raw_data"

TABLES = ["actor", "address", "category", "city", "country", "customer",
          "film", "film_actor", "film_category", "inventory", "language",
          "payment", "rental", "staff", "store"]

# Out of scope (Project Proposal): staff password and picture, film full-text column
DROP = {"staff": ["password", "picture"], "film": ["fulltext"]}

engine = create_engine(URL.create(
    "postgresql+psycopg2",
    username=os.getenv("PGUSER", "postgres"),
    password=os.environ["PGPASSWORD"],
    host=os.getenv("PGHOST", "localhost"),
    port=int(os.getenv("PGPORT", "5432")),
    database=os.environ["PGDATABASE"],
))

with engine.begin() as conn:
    conn.execute(text("CREATE SCHEMA IF NOT EXISTS project_staging"))

for t in TABLES:
    # dtype=str keeps every value exactly as in the file; empty cells become NULL
    df = pd.read_csv(RAW_DIR / f"{t}.csv", dtype=str, keep_default_na=False, na_values=[""])
    df = df.drop(columns=[c for c in DROP.get(t, []) if c in df.columns])
    df.to_sql(f"raw_{t}", engine, schema="project_staging",
              if_exists="replace", index=False, chunksize=1000, method="multi")
    print(f"raw_{t}: {len(df)} rows loaded")
