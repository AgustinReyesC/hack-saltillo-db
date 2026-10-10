--liquibase formatted sql

--changeset hack-saltillo-db:007-commitments
-- Reservas y faltantes. La necesidad vive por (orden, bom_line_id) y se reemplaza, no se suma.

CREATE TABLE reservation (
    reservation_id     BIGSERIAL   PRIMARY KEY,
    work_order_id      INTEGER     NOT NULL REFERENCES work_order(work_order_id) ON DELETE CASCADE,
    part_id            INTEGER     NOT NULL REFERENCES part(part_id),
    inspection_item_id INTEGER     REFERENCES inspection_item(inspection_item_id),
    quantity           INTEGER     NOT NULL,
    status             TEXT        NOT NULL DEFAULT 'active', -- active|fulfilled|cancelled
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT reservation_quantity_positive CHECK (quantity > 0)
);
CREATE INDEX idx_reservation_wo          ON reservation (work_order_id);
CREATE INDEX idx_reservation_part_status ON reservation (part_id, status);

CREATE TABLE shortage (
    shortage_id        BIGSERIAL   PRIMARY KEY,
    work_order_id      INTEGER     NOT NULL REFERENCES work_order(work_order_id) ON DELETE CASCADE,
    part_id            INTEGER     REFERENCES part(part_id), -- null = faltante sin identificar
    name               TEXT        NOT NULL,
    missing_quantity   INTEGER,                            -- null si no se pudo determinar
    inspection_item_id INTEGER     REFERENCES inspection_item(inspection_item_id),
    status             TEXT        NOT NULL DEFAULT 'open', -- open|closed
    opened_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at          TIMESTAMPTZ
);
CREATE INDEX idx_shortage_wo   ON shortage (work_order_id);
CREATE INDEX idx_shortage_part ON shortage (part_id);
CREATE INDEX idx_shortage_open ON shortage (status) WHERE status = 'open';
--rollback DROP TABLE shortage;
--rollback DROP TABLE reservation;
