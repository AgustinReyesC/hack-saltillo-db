--liquibase formatted sql

--changeset hack-saltillo-db:002-catalog
-- Catálogo que llega por shop.catalog: unidades, piezas, ubicaciones, modelos y BOM.

CREATE TABLE unit (
    unit_id INTEGER PRIMARY KEY,
    name    TEXT    NOT NULL
);

CREATE TABLE part (
    part_id    INTEGER     PRIMARY KEY,
    sku        TEXT,                                        -- puede venir null o repetido
    sku_norm   TEXT GENERATED ALWAYS AS (lower(btrim(sku))) STORED, -- para relacionar compras
    name       TEXT        NOT NULL,
    family     TEXT,                                        -- REFACCIÓN | SERVICIO | ...
    group_name TEXT,
    subgroup   TEXT,
    unit_id    INTEGER     REFERENCES unit(unit_id),
    image_url  TEXT,
    is_service BOOLEAN     NOT NULL DEFAULT FALSE,          -- familia SERVICIO: no se inventaría
    active     BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_part_sku_norm ON part (sku_norm);
CREATE INDEX idx_part_active   ON part (active);

CREATE TABLE location (
    location_id  INTEGER     PRIMARY KEY,
    code         TEXT        NOT NULL UNIQUE,               -- código Code 128, ej. U-101
    name         TEXT        NOT NULL,
    is_workbench BOOLEAN     NOT NULL DEFAULT FALSE,        -- mesa de trabajo
    is_receiving BOOLEAN     NOT NULL DEFAULT FALSE,        -- U-100, ubicación de recepción
    active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE model (
    model_id   INTEGER     PRIMARY KEY,
    model_name TEXT        NOT NULL,
    brand      TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Lista de partes de un modelo. `bom.upserted` reemplaza la lista completa: las líneas que
-- ya no vienen se marcan active = FALSE (no se borran, por trazabilidad).
CREATE TABLE model_line (
    bom_line_id  INTEGER     PRIMARY KEY,
    model_id     INTEGER     NOT NULL REFERENCES model(model_id) ON DELETE CASCADE,
    part_id      INTEGER     REFERENCES part(part_id),
    name         TEXT        NOT NULL,
    group_name   TEXT,                                      -- mismo group_name = kit
    unit_id      INTEGER     REFERENCES unit(unit_id),
    qty_per_unit INTEGER,
    sort_order   INTEGER     NOT NULL DEFAULT 0,
    active       BOOLEAN     NOT NULL DEFAULT TRUE,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_model_line_model  ON model_line (model_id);
CREATE INDEX idx_model_line_part   ON model_line (part_id);
CREATE INDEX idx_model_line_active ON model_line (model_id) WHERE active;
--rollback DROP TABLE model_line;
--rollback DROP TABLE model;
--rollback DROP TABLE location;
--rollback DROP TABLE part;
--rollback DROP TABLE unit;
