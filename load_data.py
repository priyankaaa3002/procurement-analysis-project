"""
Creates the procurement_analysis database (if missing), applies sql/schema.sql,
then loads the CSVs from data/ into their matching tables.

Reads connection details from environment variables so no password is hardcoded:
  PGUSER (default: postgres)
  PGPASSWORD (required)
  PGHOST (default: localhost)
  PGPORT (default: 5432)
  PGDATABASE (default: procurement_analysis)
"""
import os
import pandas as pd
import psycopg2
from urllib.parse import quote_plus
from sqlalchemy import create_engine

PGUSER = os.environ.get("PGUSER", "postgres")
PGPASSWORD = os.environ["PGPASSWORD"]
PGHOST = os.environ.get("PGHOST", "localhost")
PGPORT = os.environ.get("PGPORT", "5432")
PGDATABASE = os.environ.get("PGDATABASE", "procurement_analysis")

TABLES_IN_ORDER = [
    ("suppliers", "data/suppliers.csv"),
    ("items", "data/items.csv"),
    ("contracts", "data/contracts.csv"),
    ("purchase_orders", "data/purchase_orders.csv"),
    ("deliveries", "data/deliveries.csv"),
    ("invoices", "data/invoices.csv"),
]

def ensure_database_exists():
    conn = psycopg2.connect(dbname="postgres", user=PGUSER, password=PGPASSWORD, host=PGHOST, port=PGPORT)
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (PGDATABASE,))
    if not cur.fetchone():
        cur.execute(f'CREATE DATABASE "{PGDATABASE}"')
        print(f"Created database {PGDATABASE}")
    cur.close()
    conn.close()

def apply_schema():
    conn = psycopg2.connect(dbname=PGDATABASE, user=PGUSER, password=PGPASSWORD, host=PGHOST, port=PGPORT)
    conn.autocommit = True
    with open("sql/schema.sql") as f:
        ddl = f.read()
    cur = conn.cursor()
    cur.execute(ddl)
    cur.close()
    conn.close()
    print("Schema applied.")

def load_tables():
    engine = create_engine(f"postgresql+psycopg2://{PGUSER}:{quote_plus(PGPASSWORD)}@{PGHOST}:{PGPORT}/{PGDATABASE}")
    for table, path in TABLES_IN_ORDER:
        df = pd.read_csv(path)
        df.to_sql(table, engine, if_exists="append", index=False)
        print(f"Loaded {len(df)} rows into {table}")

if __name__ == "__main__":
    ensure_database_exists()
    apply_schema()
    load_tables()
    print("Done.")
