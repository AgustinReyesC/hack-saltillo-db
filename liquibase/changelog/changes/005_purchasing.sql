--liquibase formatted sql

--changeset hack-saltillo-db:005-purchasing
-- Compras. El contrato solo trae purchase_request_id/line_id/part_number; aquí se modela
-- el catálogo completo (proveedor, requisición y orden de compra) para el agente.

CREATE TABLE supplier (
    supplier_id  SERIAL      PRIMARY KEY,
    code         TEXT        UNIQUE,
    name         TEXT        NOT NULL,
    contact_name TEXT,
    email        TEXT,
    phone        TEXT,
    active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE purchase_request (
    purchase_request_id INTEGER     PRIMARY KEY,            -- id del catálogo del taller
    request_number      TEXT        NOT NULL UNIQUE,        -- llave "PR-" + request_number
    supplier_id         INTEGER     REFERENCES supplier(supplier_id),
    work_order_id       INTEGER     REFERENCES work_order(work_order_id),
    status              TEXT        NOT NULL DEFAULT 'received',
    requested_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_purchase_request_supplier ON purchase_request (supplier_id);
CREATE INDEX idx_purchase_request_wo       ON purchase_request (work_order_id);

CREATE TABLE purchase_order (
    purchase_order_id   SERIAL      PRIMARY KEY,
    po_number           TEXT        NOT NULL UNIQUE,
    supplier_id         INTEGER     REFERENCES supplier(supplier_id),
    purchase_request_id INTEGER     REFERENCES purchase_request(purchase_request_id),
    status              TEXT        NOT NULL DEFAULT 'open',-- draft|open|partial|received|cancelled
    currency            TEXT        NOT NULL DEFAULT 'MXN',
    ordered_at          TIMESTAMPTZ,
    expected_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_purchase_order_supplier ON purchase_order (supplier_id);

CREATE TABLE purchase_line (
    line_id             INTEGER       PRIMARY KEY,          -- line_id del evento
    purchase_request_id INTEGER       NOT NULL REFERENCES purchase_request(purchase_request_id) ON DELETE CASCADE,
    purchase_order_id   INTEGER       REFERENCES purchase_order(purchase_order_id),
    part_number         TEXT          NOT NULL,             -- texto libre del proveedor
    part_id             INTEGER       REFERENCES part(part_id), -- relación con el catálogo
    description         TEXT,
    quantity            INTEGER       NOT NULL,
    unit_price          NUMERIC(14,2) NOT NULL DEFAULT 0,
    currency            TEXT          NOT NULL DEFAULT 'MXN',
    purpose             TEXT          NOT NULL DEFAULT 'restock', -- restock|customer_order
    work_order_code     TEXT,
    match_status        TEXT          NOT NULL DEFAULT 'pending', -- pending|matched|unmatched|resolved
    received_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_purchase_line_part  ON purchase_line (part_id);
CREATE INDEX idx_purchase_line_match ON purchase_line (match_status);
CREATE INDEX idx_purchase_line_pr    ON purchase_line (purchase_request_id);

CREATE TABLE unmatched_receipt (
    id                   BIGSERIAL   PRIMARY KEY,
    purchase_line_id     INTEGER     NOT NULL UNIQUE REFERENCES purchase_line(line_id) ON DELETE CASCADE,
    part_number          TEXT        NOT NULL,
    description          TEXT,
    quantity             INTEGER     NOT NULL,
    unit_price           NUMERIC(14,2),
    currency             TEXT,
    received_at          TIMESTAMPTZ NOT NULL,
    work_order_code      TEXT,
    status               TEXT        NOT NULL DEFAULT 'pending', -- pending|resolved
    resolved_part_id     INTEGER     REFERENCES part(part_id),
    resolved_location_id INTEGER     REFERENCES location(location_id),
    resolved_at          TIMESTAMPTZ,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_unmatched_status ON unmatched_receipt (status) WHERE status = 'pending';
--rollback DROP TABLE unmatched_receipt;
--rollback DROP TABLE purchase_line;
--rollback DROP TABLE purchase_order;
--rollback DROP TABLE purchase_request;
--rollback DROP TABLE supplier;
