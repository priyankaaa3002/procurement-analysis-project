# Procurement Analytics Pipeline

A full-stack procurement analytics project: **Python (generate/clean) → PostgreSQL (relational model) → Power BI (dashboard)**.

Covers 13 procurement analysis types on a synthetic but realistic dataset with deliberately injected anomalies (maverick spend, price variance, late/partial deliveries, duplicate invoices, split purchase orders).

## Architecture

```
Python (data_generation/generate_data.py)
    → generates 6 related CSVs into data/
PostgreSQL (load_data.py + sql/schema.sql)
    → loads CSVs into a fact/dimension schema
SQL (sql/analysis_queries.sql, sql/views.sql)
    → one query/view per analysis type
Power BI (powerbi/procurement_dashboard.pbix)
    → dashboard built on the exported views (exports/*.csv)
```

## Schema

**Dimensions** (describe a business object, rarely change): `suppliers`, `items`, `contracts`
**Facts** (events with numbers to aggregate): `purchase_orders`, `deliveries`, `invoices`

`purchase_orders.contract_id` is nullable by design — an order with no linked contract is the maverick-spend signal. `deliveries` and `invoices` are children of `purchase_orders` (one order can have multiple partial shipments or installment payments).

## Analysis types covered

Spend analysis, ABC/Pareto, supplier OTIF performance, purchase price variance (PPV), maverick spend/contract compliance, savings tracking, Kraljic supplier segmentation, supplier concentration/risk, DPO/payment terms, cycle time, should-cost modeling, demand forecasting input, and anomaly detection (duplicate invoices, split POs).

## Dashboard

**Page 1 — Spend & Compliance** (spend by category/BU, maverick spend, Kraljic segmentation, supplier OTIF)
![Page 1](screenshots/page1-spend-compliance.png)

**Page 2 — Demand & Anomalies** (monthly demand by category, split-PO candidates, duplicate invoices, ABC/Pareto)
![Page 2](screenshots/page2-demand-anomalies.png)

**Page 3 — Pricing & Risk** (PPV, DPO, savings tracking, cycle time)
![Page 3](screenshots/page3-pricing-risk.png)

**Page 4 — Supplier Concentration** (single-source risk by category)
![Page 4](screenshots/page4-supplier-concentration.png)

**Page 5 — Should-Cost Benchmark** (actual price vs. should-cost, by item)
![Page 5](screenshots/page5-should-cost.png)

## Running it

```bash
cd data_generation
python -m venv ../venv && source ../venv/Scripts/activate
pip install -r ../requirements.txt
python generate_data.py

cd ..
PGUSER=postgres PGPASSWORD=yourpassword PGHOST=localhost PGPORT=5433 PGDATABASE=procurement_analysis python load_data.py
```

Then open `powerbi/procurement_dashboard.pbix` in Power BI Desktop, or run the queries in `sql/analysis_queries.sql` directly against the database.
