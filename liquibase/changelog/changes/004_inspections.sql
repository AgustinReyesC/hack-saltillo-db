--liquibase formatted sql

--changeset hack-saltillo-db:004-inspections
-- Inspecciones y sus renglones (shop.inspections). Solo `approved` genera necesidad.

CREATE TABLE inspection (
    inspection_id INTEGER     PRIMARY KEY,
    work_order_id INTEGER     NOT NULL REFERENCES work_order(work_order_id) ON DELETE CASCADE,
    kind          TEXT        NOT NULL,                     -- quick | full
    status        TEXT        NOT NULL DEFAULT 'submitted', -- submitted|approved|rejected|discarded|voided
    approved_by   INTEGER,
    approved_at   TIMESTAMPTZ,
    reason        TEXT,                                     -- reject / void
    submitted_at  TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_inspection_wo     ON inspection (work_order_id);
CREATE INDEX idx_inspection_status ON inspection (status);

CREATE TABLE inspection_item (
    inspection_item_id INTEGER     PRIMARY KEY,
    inspection_id      INTEGER     NOT NULL REFERENCES inspection(inspection_id) ON DELETE CASCADE,
    bom_line_id        INTEGER     REFERENCES model_line(bom_line_id),
    part_id            INTEGER     REFERENCES part(part_id), -- null = faltante sin identificar
    name               TEXT        NOT NULL,
    group_name         TEXT,
    condition          TEXT        NOT NULL,                 -- ok | damaged | missing
    action             TEXT,                                 -- buy | repair | null
    quantity           INTEGER,
    note               TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_inspection_item_inspection ON inspection_item (inspection_id);
CREATE INDEX idx_inspection_item_part       ON inspection_item (part_id);
CREATE INDEX idx_inspection_item_condition  ON inspection_item (condition);
--rollback DROP TABLE inspection_item;
--rollback DROP TABLE inspection;
