--liquibase formatted sql

--changeset hack-saltillo-db:003-work-orders
-- Órdenes de trabajo y su historial de etapas (shop.work_orders).

CREATE TABLE work_order (
    work_order_id INTEGER     PRIMARY KEY,
    code          TEXT        NOT NULL UNIQUE,              -- R + DDMMYY + consecutivo
    model_id      INTEGER     REFERENCES model(model_id),
    department    TEXT,                                     -- spindles|motors|electronics|torque_center
    stage         TEXT        NOT NULL DEFAULT 'awaiting_quick_inspection',
    received_at   TIMESTAMPTZ,
    deleted       BOOLEAN     NOT NULL DEFAULT FALSE,       -- work_order.deleted
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_work_order_model   ON work_order (model_id);
CREATE INDEX idx_work_order_deleted ON work_order (deleted) WHERE NOT deleted;

CREATE TABLE work_order_stage (
    id            BIGSERIAL   PRIMARY KEY,
    work_order_id INTEGER     NOT NULL REFERENCES work_order(work_order_id) ON DELETE CASCADE,
    from_stage    TEXT,
    to_stage      TEXT        NOT NULL,
    occurred_at   TIMESTAMPTZ NOT NULL,
    event_id      UUID,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_work_order_stage_wo ON work_order_stage (work_order_id);
--rollback DROP TABLE work_order_stage;
--rollback DROP TABLE work_order;
