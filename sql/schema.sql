-- Procurement Analysis Project — Schema
-- Dimensions: suppliers, items, contracts (describe who/what, rarely change)
-- Facts: purchase_orders, deliveries, invoices (events with numbers to sum)

DROP TABLE IF EXISTS invoices;
DROP TABLE IF EXISTS deliveries;
DROP TABLE IF EXISTS purchase_orders;
DROP TABLE IF EXISTS contracts;
DROP TABLE IF EXISTS items;
DROP TABLE IF EXISTS suppliers;

CREATE TABLE suppliers (
    supplier_id     SERIAL PRIMARY KEY,
    supplier_name   VARCHAR(120) NOT NULL,
    region          VARCHAR(60)  NOT NULL,
    country         VARCHAR(60)  NOT NULL,
    supplier_type   VARCHAR(40)  NOT NULL,   -- Manufacturer / Distributor / Service Provider
    risk_rating     VARCHAR(20)  NOT NULL,   -- Low / Medium / High
    onboarded_date  DATE NOT NULL
);

CREATE TABLE items (
    item_id         SERIAL PRIMARY KEY,
    item_name       VARCHAR(120) NOT NULL,
    category        VARCHAR(60)  NOT NULL,
    sub_category    VARCHAR(60)  NOT NULL,
    unit_of_measure VARCHAR(20)  NOT NULL,
    standard_cost   NUMERIC(12,2) NOT NULL   -- should-cost benchmark per unit
);

CREATE TABLE contracts (
    contract_id       SERIAL PRIMARY KEY,
    supplier_id       INT NOT NULL REFERENCES suppliers(supplier_id),
    category          VARCHAR(60) NOT NULL,
    negotiated_price  NUMERIC(12,2) NOT NULL, -- benchmark price per unit for PPV/savings
    payment_terms_days INT NOT NULL,          -- e.g. 30 / 45 / 60
    contract_start_date DATE NOT NULL,
    contract_end_date   DATE NOT NULL
);

CREATE TABLE purchase_orders (
    po_id                   SERIAL PRIMARY KEY,
    supplier_id             INT NOT NULL REFERENCES suppliers(supplier_id),
    contract_id             INT REFERENCES contracts(contract_id),  -- NULL = maverick spend
    item_id                 INT NOT NULL REFERENCES items(item_id),
    business_unit           VARCHAR(60) NOT NULL,
    requisition_date        DATE NOT NULL,
    order_date              DATE NOT NULL,
    requested_delivery_date DATE NOT NULL,
    ordered_qty             INT NOT NULL,
    unit_price_ordered      NUMERIC(12,2) NOT NULL,
    ordered_amount          NUMERIC(14,2) NOT NULL
);

CREATE TABLE deliveries (
    delivery_id     SERIAL PRIMARY KEY,
    po_id           INT NOT NULL REFERENCES purchase_orders(po_id),
    delivery_date   DATE NOT NULL,
    delivered_qty   INT NOT NULL,
    quality_status  VARCHAR(20) NOT NULL     -- Accepted / Rejected / Partial
);

CREATE TABLE invoices (
    invoice_id          SERIAL PRIMARY KEY,
    po_id               INT NOT NULL REFERENCES purchase_orders(po_id),
    invoice_date        DATE NOT NULL,
    price_charged       NUMERIC(12,2) NOT NULL,  -- actual per-unit price billed (PPV vs negotiated_price)
    invoice_amount       NUMERIC(14,2) NOT NULL,
    payment_date        DATE,
    payment_amount      NUMERIC(14,2),
    installment_number  INT NOT NULL DEFAULT 1
);

CREATE INDEX idx_po_supplier ON purchase_orders(supplier_id);
CREATE INDEX idx_po_contract ON purchase_orders(contract_id);
CREATE INDEX idx_po_item ON purchase_orders(item_id);
CREATE INDEX idx_deliveries_po ON deliveries(po_id);
CREATE INDEX idx_invoices_po ON invoices(po_id);
