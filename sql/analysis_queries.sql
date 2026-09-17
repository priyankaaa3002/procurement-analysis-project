-- =====================================================================
-- Procurement Analysis Queries — one block per analysis type
-- =====================================================================

-- 1. SPEND ANALYSIS: where is money going, by category / region / BU / time
SELECT i.category, s.region, po.business_unit,
       DATE_PART('year', po.order_date) AS order_year,
       SUM(po.ordered_amount) AS total_spend
FROM purchase_orders po
JOIN items i ON po.item_id = i.item_id
JOIN suppliers s ON po.supplier_id = s.supplier_id
GROUP BY i.category, s.region, po.business_unit, order_year
ORDER BY total_spend DESC;

-- 2. ABC / PARETO ANALYSIS: which suppliers drive 80% of spend
WITH supplier_spend AS (
    SELECT s.supplier_id, s.supplier_name, SUM(po.ordered_amount) AS spend
    FROM purchase_orders po JOIN suppliers s ON po.supplier_id = s.supplier_id
    GROUP BY s.supplier_id, s.supplier_name
),
ranked AS (
    SELECT *,
           SUM(spend) OVER (ORDER BY spend DESC) / SUM(spend) OVER () AS cum_pct
    FROM supplier_spend
)
SELECT supplier_name, spend, ROUND(cum_pct * 100, 1) AS cumulative_pct,
       CASE WHEN cum_pct <= 0.8 THEN 'A' WHEN cum_pct <= 0.95 THEN 'B' ELSE 'C' END AS abc_class
FROM ranked
ORDER BY spend DESC;

-- 3. SUPPLIER PERFORMANCE (OTIF): on-time, in-full, quality-accepted
WITH delivery_summary AS (
    SELECT po_id,
           MAX(delivery_date) AS final_delivery_date,
           SUM(delivered_qty) AS total_delivered,
           BOOL_AND(quality_status = 'Accepted') AS all_accepted
    FROM deliveries
    GROUP BY po_id
)
SELECT s.supplier_name,
       COUNT(*) AS total_orders,
       ROUND(100.0 * SUM(CASE WHEN ds.final_delivery_date <= po.requested_delivery_date THEN 1 ELSE 0 END) / COUNT(*), 1) AS on_time_pct,
       ROUND(100.0 * SUM(CASE WHEN ds.total_delivered >= po.ordered_qty THEN 1 ELSE 0 END) / COUNT(*), 1) AS in_full_pct,
       ROUND(100.0 * SUM(CASE WHEN ds.all_accepted THEN 1 ELSE 0 END) / COUNT(*), 1) AS quality_pct,
       ROUND(100.0 * SUM(CASE WHEN ds.final_delivery_date <= po.requested_delivery_date
                               AND ds.total_delivered >= po.ordered_qty
                               AND ds.all_accepted THEN 1 ELSE 0 END) / COUNT(*), 1) AS otif_pct
FROM purchase_orders po
JOIN delivery_summary ds ON po.po_id = ds.po_id
JOIN suppliers s ON po.supplier_id = s.supplier_id
GROUP BY s.supplier_name
ORDER BY otif_pct ASC;

-- 4. PRICE / PURCHASE PRICE VARIANCE (PPV): actual vs negotiated contract price
SELECT s.supplier_name, i.category,
       AVG(po.unit_price_ordered - c.negotiated_price) AS avg_ppv_per_unit,
       SUM((po.unit_price_ordered - c.negotiated_price) * po.ordered_qty) AS total_ppv_impact
FROM purchase_orders po
JOIN contracts c ON po.contract_id = c.contract_id
JOIN suppliers s ON po.supplier_id = s.supplier_id
JOIN items i ON po.item_id = i.item_id
GROUP BY s.supplier_name, i.category
ORDER BY total_ppv_impact DESC;

-- 5. MAVERICK SPEND / CONTRACT COMPLIANCE: spend with no matching contract
SELECT business_unit,
       COUNT(*) AS maverick_po_count,
       SUM(ordered_amount) AS maverick_spend,
       ROUND(100.0 * SUM(ordered_amount) / (SELECT SUM(ordered_amount) FROM purchase_orders), 1) AS pct_of_total_spend
FROM purchase_orders
WHERE contract_id IS NULL
GROUP BY business_unit
ORDER BY maverick_spend DESC;

-- 6. SAVINGS TRACKING: negotiated price vs price actually billed on invoices, over time
SELECT DATE_TRUNC('quarter', inv.invoice_date) AS quarter, s.supplier_name,
       AVG(c.negotiated_price) AS avg_negotiated_price,
       AVG(inv.price_charged) AS avg_price_charged,
       AVG(c.negotiated_price - inv.price_charged) AS avg_savings_per_unit
FROM invoices inv
JOIN purchase_orders po ON inv.po_id = po.po_id
JOIN contracts c ON po.contract_id = c.contract_id
JOIN suppliers s ON po.supplier_id = s.supplier_id
GROUP BY quarter, s.supplier_name
ORDER BY quarter;

-- 7. SUPPLIER SEGMENTATION (Kraljic matrix proxy): spend impact vs supplier availability per category
WITH cat_spend AS (
    SELECT i.category, SUM(po.ordered_amount) AS category_spend, COUNT(DISTINCT po.supplier_id) AS supplier_count
    FROM purchase_orders po JOIN items i ON po.item_id = i.item_id
    GROUP BY i.category
)
SELECT category, category_spend, supplier_count,
       CASE
           WHEN category_spend > (SELECT AVG(category_spend) FROM cat_spend) AND supplier_count <= 3 THEN 'Strategic'
           WHEN category_spend > (SELECT AVG(category_spend) FROM cat_spend) AND supplier_count > 3 THEN 'Leverage'
           WHEN category_spend <= (SELECT AVG(category_spend) FROM cat_spend) AND supplier_count <= 3 THEN 'Bottleneck'
           ELSE 'Routine'
       END AS kraljic_quadrant
FROM cat_spend
ORDER BY category_spend DESC;

-- 8. SUPPLIER CONCENTRATION / RISK: categories over-reliant on one supplier (>50% share)
WITH cat_supplier_spend AS (
    SELECT i.category, s.supplier_name, SUM(po.ordered_amount) AS spend
    FROM purchase_orders po
    JOIN items i ON po.item_id = i.item_id
    JOIN suppliers s ON po.supplier_id = s.supplier_id
    GROUP BY i.category, s.supplier_name
),
cat_total AS (
    SELECT category, SUM(spend) AS total_category_spend FROM cat_supplier_spend GROUP BY category
)
SELECT css.category, css.supplier_name, css.spend,
       ROUND(100.0 * css.spend / ct.total_category_spend, 1) AS pct_of_category_spend
FROM cat_supplier_spend css
JOIN cat_total ct ON css.category = ct.category
WHERE css.spend / ct.total_category_spend > 0.5
ORDER BY pct_of_category_spend DESC;

-- 9. DPO / PAYMENT TERMS: actual days-to-pay vs contracted terms
SELECT s.supplier_name, c.payment_terms_days,
       ROUND(AVG(inv.payment_date - inv.invoice_date), 1) AS avg_actual_days_to_pay,
       ROUND(AVG((inv.payment_date - inv.invoice_date) - c.payment_terms_days), 1) AS avg_days_over_terms
FROM invoices inv
JOIN purchase_orders po ON inv.po_id = po.po_id
JOIN suppliers s ON po.supplier_id = s.supplier_id
LEFT JOIN contracts c ON po.contract_id = c.contract_id
WHERE inv.payment_date IS NOT NULL AND c.payment_terms_days IS NOT NULL
GROUP BY s.supplier_name, c.payment_terms_days
ORDER BY avg_days_over_terms DESC;

-- 10. CYCLE TIME: requisition -> order -> delivery -> invoice -> payment, by business unit
WITH cycle AS (
    SELECT po.po_id, po.business_unit, po.requisition_date, po.order_date,
           MIN(d.delivery_date) AS first_delivery_date,
           MIN(inv.invoice_date) AS first_invoice_date,
           MIN(inv.payment_date) AS first_payment_date
    FROM purchase_orders po
    LEFT JOIN deliveries d ON po.po_id = d.po_id
    LEFT JOIN invoices inv ON po.po_id = inv.po_id
    GROUP BY po.po_id, po.business_unit, po.requisition_date, po.order_date
)
SELECT business_unit,
       ROUND(AVG(order_date - requisition_date), 1) AS avg_req_to_order_days,
       ROUND(AVG(first_delivery_date - order_date), 1) AS avg_order_to_delivery_days,
       ROUND(AVG(first_invoice_date - first_delivery_date), 1) AS avg_delivery_to_invoice_days,
       ROUND(AVG(first_payment_date - first_invoice_date), 1) AS avg_invoice_to_payment_days
FROM cycle
GROUP BY business_unit;

-- 11. SHOULD-COST MODELING: actual price paid vs standard/should-cost benchmark
SELECT i.category, i.item_name, i.standard_cost,
       ROUND(AVG(po.unit_price_ordered), 2) AS avg_actual_price,
       ROUND(100.0 * (AVG(po.unit_price_ordered) - i.standard_cost) / i.standard_cost, 1) AS pct_over_should_cost
FROM purchase_orders po
JOIN items i ON po.item_id = i.item_id
GROUP BY i.category, i.item_name, i.standard_cost
ORDER BY pct_over_should_cost DESC;

-- 12. DEMAND FORECASTING (input series): monthly ordered quantity by category
-- (feed this into Python/Excel/BI for a moving average or trend line)
SELECT DATE_TRUNC('month', order_date) AS month, i.category, SUM(po.ordered_qty) AS total_qty_ordered
FROM purchase_orders po
JOIN items i ON po.item_id = i.item_id
GROUP BY month, i.category
ORDER BY month;

-- 13a. ANOMALY DETECTION: duplicate invoices (same PO, same amount, close dates)
SELECT a.po_id, a.invoice_id AS invoice_1, b.invoice_id AS invoice_2,
       a.invoice_amount, a.invoice_date AS date_1, b.invoice_date AS date_2
FROM invoices a
JOIN invoices b ON a.po_id = b.po_id
                AND a.invoice_id < b.invoice_id
                AND a.invoice_amount = b.invoice_amount
                AND ABS(a.invoice_date - b.invoice_date) <= 5;

-- 13b. ANOMALY DETECTION: possible split POs (same supplier/BU/day, multiple small POs)
SELECT supplier_id, business_unit, order_date, COUNT(*) AS po_count, SUM(ordered_amount) AS combined_amount
FROM purchase_orders
WHERE ordered_amount < 50000
GROUP BY supplier_id, business_unit, order_date
HAVING COUNT(*) >= 2
ORDER BY combined_amount DESC;
