# Optional step after staging.sql: export the cleaned staging tables to CSV.
# Writes project_staging.stg_<table> to 02_Data/cleaned_data/stg_<table>.csv
# so the cleaned data can be inspected without a database.
# Needs: pip install pandas sqlalchemy psycopg2-binary
#
# Same settings as load_staging.py (environment variables):
#   PGPASSWORD (required), PGDATABASE (required: your PostgreSQL database name),
#   PGUSER (default postgres), PGHOST (default localhost), PGPORT (default 5432)
#
# Run from the repo root:  python 03_ETL/export_cleaned.py

import os
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine
from sqlalchemy.engine import URL

OUT_DIR = Path(__file__).resolve().parent.parent / "02_Data" / "cleaned_data"

TABLES = ["actor", "address", "category", "city", "country", "customer",
          "film", "film_actor", "film_category", "inventory", "language",
          "payment", "rental", "staff", "store"]

engine = create_engine(URL.create(
    "postgresql+psycopg2",
    username=os.getenv("PGUSER", "postgres"),
    password=os.environ["PGPASSWORD"],
    host=os.getenv("PGHOST", "localhost"),
    port=int(os.getenv("PGPORT", "5432")),
    database=os.environ["PGDATABASE"],
))

OUT_DIR.mkdir(parents=True, exist_ok=True)
for t in TABLES:
    df = pd.read_sql_table(f"stg_{t}", engine, schema="project_staging")
    df.to_csv(OUT_DIR / f"stg_{t}.csv", index=False)
    print(f"stg_{t}.csv: {len(df)} rows")
