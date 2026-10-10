--liquibase formatted sql

--changeset hack-saltillo-db:009-agent-status-repair
-- Extensiones para el agente: estado de cada pieza (funcional / defectuoso / en reparación)
-- y el recetario de reparación (instrumentos y repuestos necesarios).

CREATE TABLE part_condition (
    condition_code TEXT        PRIMARY KEY,
    name           TEXT        NOT NULL,
    description    TEXT,
    is_available   BOOLEAN     NOT NULL DEFAULT FALSE,  -- ¿cuenta como stock disponible?
    sort_order     INTEGER     NOT NULL DEFAULT 0
);

-- Estado actual de una pieza (una fila por pieza).
CREATE TABLE part_status (
    part_id        INTEGER     PRIMARY KEY REFERENCES part(part_id) ON DELETE CASCADE,
    condition_code TEXT        NOT NULL REFERENCES part_condition(condition_code),
    work_order_id  INTEGER     REFERENCES work_order(work_order_id),
    note           TEXT,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Historial de cambios de estado (para responder "¿cuándo se dañó?").
CREATE TABLE part_status_history (
    id             BIGSERIAL   PRIMARY KEY,
    part_id        INTEGER     NOT NULL REFERENCES part(part_id) ON DELETE CASCADE,
    condition_code TEXT        NOT NULL REFERENCES part_condition(condition_code),
    work_order_id  INTEGER     REFERENCES work_order(work_order_id),
    note           TEXT,
    changed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    event_id       UUID
);
CREATE INDEX idx_part_status_history_part ON part_status_history (part_id);

-- Instrumentos / herramientas del taller.
CREATE TABLE repair_tool (
    tool_id     SERIAL      PRIMARY KEY,
    code        TEXT        UNIQUE,
    name        TEXT        NOT NULL,
    description TEXT,
    active      BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Qué instrumentos y en qué cantidad hacen falta para reparar una pieza.
CREATE TABLE part_repair_tool (
    part_id  INTEGER NOT NULL REFERENCES part(part_id) ON DELETE CASCADE,
    tool_id  INTEGER NOT NULL REFERENCES repair_tool(tool_id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL DEFAULT 1,
    notes    TEXT,
    PRIMARY KEY (part_id, tool_id)
);

-- Qué piezas/repuestos componen la reparación (además de las herramientas).
CREATE TABLE part_repair_component (
    part_id           INTEGER NOT NULL REFERENCES part(part_id) ON DELETE CASCADE,
    component_part_id INTEGER NOT NULL REFERENCES part(part_id) ON DELETE CASCADE,
    quantity          INTEGER NOT NULL DEFAULT 1,
    notes             TEXT,
    PRIMARY KEY (part_id, component_part_id),
    CONSTRAINT no_self_component CHECK (part_id <> component_part_id)
);
--rollback DROP TABLE part_repair_component;
--rollback DROP TABLE part_repair_tool;
--rollback DROP TABLE repair_tool;
--rollback DROP TABLE part_status_history;
--rollback DROP TABLE part_status;
--rollback DROP TABLE part_condition;
