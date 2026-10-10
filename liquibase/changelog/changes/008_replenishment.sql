--liquibase formatted sql

--changeset hack-saltillo-db:008-replenishment
-- Políticas de reabasto (mínimo/máximo/reorden/lead time) y sugerencias vigentes.

CREATE TABLE reorder_policy (
    part_id          INTEGER     PRIMARY KEY REFERENCES part(part_id) ON DELETE CASCADE,
    min_quantity     INTEGER     NOT NULL DEFAULT 0,
    max_quantity     INTEGER,
    reorder_quantity INTEGER,
    lead_time_days   INTEGER,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE reorder_suggestion (
    part_id            INTEGER     PRIMARY KEY REFERENCES part(part_id) ON DELETE CASCADE,
    suggested_quantity INTEGER     NOT NULL,
    work_order_ids     INTEGER[]   NOT NULL DEFAULT '{}',
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT reorder_suggestion_positive CHECK (suggested_quantity >= 1)
);
--rollback DROP TABLE reorder_suggestion;
--rollback DROP TABLE reorder_policy;
