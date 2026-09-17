"""
Generates a realistic synthetic procurement dataset: 6 related tables
(suppliers, items, contracts, purchase_orders, deliveries, invoices).

Deliberate anomalies are injected so every analysis type has real signal:
- ~25% of POs have no matching contract -> maverick spend
- price_charged sometimes drifts from unit_price_ordered -> PPV / billing variance
- some deliveries are late, short, or split across multiple shipments -> OTIF
- some invoices are paid later than contract payment terms -> DPO
- a small number of duplicate invoices and same-day split POs -> fraud/anomaly detection
"""
import numpy as np
import pandas as pd
from faker import Faker
from datetime import timedelta

RNG = np.random.default_rng(42)
fake = Faker()
Faker.seed(42)

OUT_DIR = "../data"

CATEGORIES = [
    "Raw Materials", "Packaging", "IT Hardware", "Office Supplies", "MRO",
    "Logistics", "Professional Services", "Facilities", "Marketing", "Electronics",
]
SUB_CATEGORIES = {
    "Raw Materials": ["Steel", "Plastics", "Chemicals"],
    "Packaging": ["Cartons", "Labels", "Pallets"],
    "IT Hardware": ["Laptops", "Servers", "Networking"],
    "Office Supplies": ["Stationery", "Furniture"],
    "MRO": ["Spare Parts", "Tools", "Safety Equipment"],
    "Logistics": ["Freight", "Warehousing"],
    "Professional Services": ["Consulting", "Legal", "Staffing"],
    "Facilities": ["Cleaning", "Security", "Utilities"],
    "Marketing": ["Print Media", "Events", "Digital Ads"],
    "Electronics": ["Components", "Sensors", "PCBs"],
}
REGIONS = ["North", "South", "East", "West", "Central"]
BUSINESS_UNITS = ["Manufacturing", "R&D", "IT", "Marketing", "Operations", "Finance"]
SUPPLIER_TYPES = ["Manufacturer", "Distributor", "Service Provider"]

N_SUPPLIERS = 40
N_ITEMS = 60
N_CONTRACTS = 55
N_POS = 3000
START_DATE = pd.Timestamp("2024-01-01")
END_DATE = pd.Timestamp("2025-12-31")

def random_dates(start, end, n):
    days = (end - start).days
    offsets = RNG.integers(0, days, size=n)
    return [start + timedelta(days=int(d)) for d in offsets]

def gen_suppliers():
    rows = []
    for sid in range(1, N_SUPPLIERS + 1):
        rows.append({
            "supplier_id": sid,
            "supplier_name": fake.company(),
            "region": RNG.choice(REGIONS),
            "country": "India" if RNG.random() < 0.8 else fake.country(),
            "supplier_type": RNG.choice(SUPPLIER_TYPES, p=[0.5, 0.35, 0.15]),
            "risk_rating": RNG.choice(["Low", "Medium", "High"], p=[0.55, 0.30, 0.15]),
            "onboarded_date": fake.date_between(start_date="-6y", end_date="-1y"),
        })
    df = pd.DataFrame(rows)
    # each supplier can supply 1-3 categories
    df["capable_categories"] = [
        list(RNG.choice(CATEGORIES, size=RNG.integers(1, 4), replace=False)) for _ in range(len(df))
    ]
    return df

def gen_items():
    rows = []
    for iid in range(1, N_ITEMS + 1):
        cat = RNG.choice(CATEGORIES)
        sub = RNG.choice(SUB_CATEGORIES[cat])
        std_cost = round(float(RNG.lognormal(mean=4.5, sigma=1.2)), 2)  # wide cost spread
        rows.append({
            "item_id": iid,
            "item_name": f"{sub} - {fake.word().capitalize()}",
            "category": cat,
            "sub_category": sub,
            "unit_of_measure": RNG.choice(["Unit", "Box", "Kg", "Litre", "Hour"]),
            "standard_cost": std_cost,
        })
    return pd.DataFrame(rows)

def gen_contracts(suppliers):
    rows = []
    cid = 1
    for _, s in suppliers.iterrows():
        for cat in s["capable_categories"]:
            if RNG.random() < 0.7:  # not every capability has a live contract -> maverick spend later
                start = fake.date_between(start_date="-3y", end_date="-6m")
                rows.append({
                    "contract_id": cid,
                    "supplier_id": s["supplier_id"],
                    "category": cat,
                    "negotiated_price_factor": round(float(RNG.uniform(0.85, 1.05)), 3),  # vs standard_cost
                    "payment_terms_days": int(RNG.choice([30, 45, 60])),
                    "contract_start_date": start,
                    "contract_end_date": start + timedelta(days=int(RNG.integers(365, 900))),
                })
                cid += 1
            if cid > N_CONTRACTS:
                break
        if cid > N_CONTRACTS:
            break
    return pd.DataFrame(rows)

def gen_purchase_orders(suppliers, items, contracts):
    rows = []
    order_dates = random_dates(START_DATE, END_DATE, N_POS)
    for po_id in range(1, N_POS + 1):
        s = suppliers.sample(1, random_state=int(RNG.integers(1e9))).iloc[0]
        cat = RNG.choice(s["capable_categories"])
        cat_items = items[items["category"] == cat]
        item = cat_items.sample(1, random_state=int(RNG.integers(1e9))).iloc[0]

        match = contracts[(contracts["supplier_id"] == s["supplier_id"]) & (contracts["category"] == cat)]
        has_contract = len(match) > 0
        contract_id = int(match.iloc[0]["contract_id"]) if has_contract else None
        terms_days = int(match.iloc[0]["payment_terms_days"]) if has_contract else 30

        if has_contract:
            base_price = item["standard_cost"] * match.iloc[0]["negotiated_price_factor"]
            unit_price = round(base_price * RNG.uniform(0.95, 1.15), 2)  # price creep over time
        else:
            unit_price = round(item["standard_cost"] * RNG.uniform(0.90, 1.35), 2)  # no negotiation leverage

        order_date = order_dates[po_id - 1]
        requisition_date = order_date - timedelta(days=int(RNG.integers(0, 10)))
        lead_time = int(RNG.integers(7, 45))
        requested_delivery_date = order_date + timedelta(days=lead_time)
        qty = int(RNG.integers(10, 500))

        rows.append({
            "po_id": po_id,
            "supplier_id": int(s["supplier_id"]),
            "contract_id": contract_id,
            "item_id": int(item["item_id"]),
            "business_unit": RNG.choice(BUSINESS_UNITS),
            "requisition_date": requisition_date.date(),
            "order_date": order_date.date(),
            "requested_delivery_date": requested_delivery_date.date(),
            "ordered_qty": qty,
            "unit_price_ordered": unit_price,
            "ordered_amount": round(qty * unit_price, 2),
            "_terms_days": terms_days,  # helper, dropped before saving invoices join
        })
    return pd.DataFrame(rows)

def gen_deliveries(pos):
    rows = []
    delivery_id = 1
    for _, po in pos.iterrows():
        n_shipments = RNG.choice([1, 2, 3], p=[0.80, 0.15, 0.05])
        remaining = po["ordered_qty"]
        # ~10% of POs are short-delivered overall
        total_to_deliver = po["ordered_qty"] if RNG.random() > 0.10 else int(po["ordered_qty"] * RNG.uniform(0.5, 0.95))
        req_date = pd.Timestamp(po["requested_delivery_date"])
        for i in range(n_shipments):
            qty = total_to_deliver // n_shipments if i < n_shipments - 1 else total_to_deliver - (total_to_deliver // n_shipments) * (n_shipments - 1)
            delay_days = int(RNG.integers(-5, 20))  # negative = early, positive = late
            d_date = req_date + timedelta(days=delay_days + i * 3)
            quality = RNG.choice(["Accepted", "Accepted", "Accepted", "Partial", "Rejected"])
            rows.append({
                "delivery_id": delivery_id,
                "po_id": int(po["po_id"]),
                "delivery_date": d_date.date(),
                "delivered_qty": max(qty, 0),
                "quality_status": quality,
            })
            delivery_id += 1
    return pd.DataFrame(rows)

def gen_invoices(pos, deliveries):
    rows = []
    invoice_id = 1
    last_delivery = deliveries.groupby("po_id")["delivery_date"].max()
    for _, po in pos.iterrows():
        last_d = last_delivery.get(po["po_id"])
        base_date = pd.Timestamp(last_d) if last_d is not None else pd.Timestamp(po["order_date"])
        n_installments = RNG.choice([1, 2], p=[0.85, 0.15])
        amount_left = po["ordered_amount"]
        price = po["unit_price_ordered"]
        if RNG.random() < 0.05:  # billing discrepancy vs PO price
            price = round(price * RNG.uniform(0.95, 1.10), 2)

        for i in range(n_installments):
            inv_date = base_date + timedelta(days=int(RNG.integers(1, 10)) + i * 15)
            inv_amount = round(amount_left / n_installments, 2)
            terms = int(po["_terms_days"])
            pay_delay = terms + int(RNG.normal(0, 12))  # sometimes early, often late vs terms
            pay_date = inv_date + timedelta(days=max(pay_delay, 1))
            rows.append({
                "invoice_id": invoice_id,
                "po_id": int(po["po_id"]),
                "invoice_date": inv_date.date(),
                "price_charged": price,
                "invoice_amount": inv_amount,
                "payment_date": pay_date.date(),
                "payment_amount": inv_amount,
                "installment_number": i + 1,
            })
            invoice_id += 1

        # inject occasional duplicate invoice (fraud/anomaly signal)
        if RNG.random() < 0.015:
            dup_date = inv_date + timedelta(days=int(RNG.integers(1, 4)))
            rows.append({
                "invoice_id": invoice_id,
                "po_id": int(po["po_id"]),
                "invoice_date": dup_date.date(),
                "price_charged": price,
                "invoice_amount": round(amount_left / n_installments, 2),
                "payment_date": (dup_date + timedelta(days=terms)).date(),
                "payment_amount": round(amount_left / n_installments, 2),
                "installment_number": n_installments,
            })
            invoice_id += 1
    return pd.DataFrame(rows)

def main():
    import os
    os.makedirs(OUT_DIR, exist_ok=True)

    suppliers = gen_suppliers()
    items = gen_items()
    contracts = gen_contracts(suppliers)
    pos = gen_purchase_orders(suppliers, items, contracts)
    deliveries = gen_deliveries(pos)
    invoices = gen_invoices(pos, deliveries)

    suppliers_out = suppliers.drop(columns=["capable_categories"])
    contracts_out = contracts.rename(columns={"negotiated_price_factor": "negotiated_price"})
    # negotiated_price stored as an absolute reference price (avg item std_cost * factor) for simplicity
    contracts_out["negotiated_price"] = (contracts_out["negotiated_price"] * items["standard_cost"].mean()).round(2)
    pos_out = pos.drop(columns=["_terms_days"])

    suppliers_out.to_csv(f"{OUT_DIR}/suppliers.csv", index=False)
    items.to_csv(f"{OUT_DIR}/items.csv", index=False)
    contracts_out.to_csv(f"{OUT_DIR}/contracts.csv", index=False)
    pos_out.to_csv(f"{OUT_DIR}/purchase_orders.csv", index=False)
    deliveries.to_csv(f"{OUT_DIR}/deliveries.csv", index=False)
    invoices.to_csv(f"{OUT_DIR}/invoices.csv", index=False)

    print(f"suppliers: {len(suppliers_out)}")
    print(f"items: {len(items)}")
    print(f"contracts: {len(contracts_out)}")
    print(f"purchase_orders: {len(pos_out)}")
    print(f"deliveries: {len(deliveries)}")
    print(f"invoices: {len(invoices)}")

if __name__ == "__main__":
    main()
