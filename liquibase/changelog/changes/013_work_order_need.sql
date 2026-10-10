--liquibase formatted sql

--changeset hack-saltillo-db:013-work-order-need
-- G3: necesidad vigente por (orden, bom_line_id). Cada aprobación la REEMPLAZA (no la suma).
CREATE TABLE work_order_need (
    work_order_id      INTEGER     NOT NULL REFERENCES work_order(work_order_id) ON DELETE CASCADE,
    bom_line_id        INTEGER     NOT NULL REFERENCES model_line(bom_line_id),
    part_id            INTEGER     REFERENCES part(part_id),
    quantity           INTEGER,                              -- NULL = no determinada
    inspection_item_id INTEGER     REFERENCES inspection_item(inspection_item_id),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (work_order_id, bom_line_id)
);
CREATE INDEX idx_work_order_need_part ON work_order_need (part_id);
--rollback DROP TABLE work_order_need;
