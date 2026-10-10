--liquibase formatted sql

--changeset hack-saltillo-db:010-views
-- Vistas de apoyo para la API y el agente.

-- Saldo total por pieza (on_hand / reserved / available).
CREATE VIEW v_part_availability AS
SELECT p.part_id,
       p.sku,
       p.name,
       p.active,
       COALESCE(SUM(b.on_hand), 0)   AS on_hand,
       COALESCE(SUM(b.reserved), 0)  AS reserved,
       COALESCE(SUM(b.available), 0) AS available
FROM part p
LEFT JOIN stock_balance b ON b.part_id = p.part_id
GROUP BY p.part_id, p.sku, p.name, p.active;

-- Vista "de una pregunta" para el agente: ¿tengo esta pieza? ¿está defectuosa? ¿es reparable?
CREATE VIEW v_part_agent_summary AS
SELECT p.part_id,
       p.sku,
       p.name,
       p.family,
       p.active,
       ps.condition_code,
       pc.name AS condition_name,
       COALESCE(pc.is_available, FALSE) AS condition_is_available,
       COALESCE(a.on_hand, 0)   AS on_hand,
       COALESCE(a.reserved, 0)  AS reserved,
       COALESCE(a.available, 0) AS available,
       (SELECT COUNT(*) FROM part_repair_tool t WHERE t.part_id = p.part_id)          AS repair_tools_count,
       (SELECT COUNT(*) FROM part_repair_component c WHERE c.part_id = p.part_id)    AS repair_components_count,
       (SELECT COUNT(*) FROM shortage s WHERE s.part_id = p.part_id AND s.status = 'open') AS open_shortages
FROM part p
LEFT JOIN part_status ps    ON ps.part_id = p.part_id
LEFT JOIN part_condition pc ON pc.condition_code = ps.condition_code
LEFT JOIN v_part_availability a ON a.part_id = p.part_id;

-- Faltantes abiertos.
CREATE VIEW v_open_shortages AS
SELECT s.shortage_id,
       s.work_order_id,
       w.code AS work_order_code,
       s.part_id,
       COALESCE(p.name, s.name) AS name,
       s.missing_quantity,
       s.inspection_item_id,
       s.opened_at
FROM shortage s
JOIN work_order w ON w.work_order_id = s.work_order_id
LEFT JOIN part p  ON p.part_id = s.part_id
WHERE s.status = 'open';

-- Recepciones pendientes de relacionar.
CREATE VIEW v_unmatched_receipts AS
SELECT id,
       purchase_line_id,
       part_number,
       description,
       quantity,
       unit_price,
       currency,
       received_at,
       work_order_code
FROM unmatched_receipt
WHERE status = 'pending';

-- Sugerencias de reabasto vigentes.
CREATE VIEW v_reorder_suggestions AS
SELECT rs.part_id,
       p.sku,
       p.name,
       rs.suggested_quantity,
       rs.work_order_ids
FROM reorder_suggestion rs
JOIN part p ON p.part_id = rs.part_id;

-- Kardex por pieza (movimiento + saldo corrido acumulado).
CREATE VIEW v_part_ledger AS
SELECT m.part_id,
       m.movement_id,
       m.type,
       m.location_id,
       m.quantity,
       m.reference,
       m.occurred_at,
       SUM(m.quantity) OVER (PARTITION BY m.part_id ORDER BY m.occurred_at, m.movement_id) AS balance
FROM movement m;
--rollback DROP VIEW v_part_ledger;
--rollback DROP VIEW v_reorder_suggestions;
--rollback DROP VIEW v_unmatched_receipts;
--rollback DROP VIEW v_open_shortages;
--rollback DROP VIEW v_part_agent_summary;
--rollback DROP VIEW v_part_availability;
