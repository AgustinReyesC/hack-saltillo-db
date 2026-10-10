--liquibase formatted sql

--changeset hack-saltillo-db:006-ledger
-- Libro mayor inmutable. El stock nunca se edita directo: se calcula sumando movimientos.
-- `stock_balance` es la proyección por (pieza, ubicación).

CREATE TABLE movement (
    movement_id  BIGSERIAL     PRIMARY KEY,
    type         TEXT          NOT NULL,  -- receipt|issue|transfer_out|transfer_in|adjustment
    part_id      INTEGER       NOT NULL REFERENCES part(part_id),
    location_id  INTEGER       NOT NULL REFERENCES location(location_id),
    quantity     INTEGER       NOT NULL,  -- con signo: negativo cuando sale
    unit_cost    NUMERIC(14,2),
    currency     TEXT,
    reference    TEXT,                    -- orden, línea de compra o motivo
    occurred_at  TIMESTAMPTZ   NOT NULL,
    event_id     UUID,                    -- evento de entrada/salida que lo originó
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT movement_quantity_nonzero CHECK (quantity <> 0)
);
CREATE INDEX idx_movement_part           ON movement (part_id);
CREATE INDEX idx_movement_part_occurred  ON movement (part_id, occurred_at DESC);
CREATE INDEX idx_movement_location       ON movement (location_id);
CREATE INDEX idx_movement_type           ON movement (type);

CREATE TABLE stock_balance (
    part_id     INTEGER     NOT NULL REFERENCES part(part_id),
    location_id INTEGER     NOT NULL REFERENCES location(location_id),
    on_hand     INTEGER     NOT NULL DEFAULT 0,
    reserved    INTEGER     NOT NULL DEFAULT 0,
    available   INTEGER GENERATED ALWAYS AS (on_hand - reserved) STORED,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (part_id, location_id)
);
-- Nota: NO se restringe available >= 0 aquí. Las reservas y salidas nunca deben dejar
-- available negativo (lo garantiza la aplicación), pero un conteo cíclico autorizado
-- (POST /counts) sí puede dejarlo negativo (regla 17 del contrato).
CREATE INDEX idx_stock_balance_part ON stock_balance (part_id);
--rollback DROP TABLE stock_balance;
--rollback DROP TABLE movement;
