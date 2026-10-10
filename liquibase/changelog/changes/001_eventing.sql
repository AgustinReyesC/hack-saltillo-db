--liquibase formatted sql

--changeset hack-saltillo-db:001-eventing
-- Capa de eventos: entrada cruda para idempotencia y replay, salida (outbox) y DLQ.
-- Regla del reto: deduplicar por event_id; reconstruir desde cero releyendo los tópicos.

CREATE TABLE event_inbox (
    event_id      UUID        PRIMARY KEY,          -- deduplicación (al menos una vez)
    event_type    TEXT        NOT NULL,
    event_version INTEGER     NOT NULL DEFAULT 1,
    occurred_at   TIMESTAMPTZ NOT NULL,             -- cuándo pasó, no cuándo llegó
    source        TEXT        NOT NULL DEFAULT 'shop-floor',
    event_key     TEXT        NOT NULL,             -- llave de partición del tópico
    topic         TEXT,                             -- shop.catalog | shop.work_orders | ...
    payload       JSONB       NOT NULL,             -- sobre completo del evento
    status        TEXT        NOT NULL DEFAULT 'processed', -- received | processed | failed
    error         TEXT,
    received_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at  TIMESTAMPTZ
);
CREATE INDEX idx_event_inbox_type     ON event_inbox (event_type);
CREATE INDEX idx_event_inbox_occurred ON event_inbox (occurred_at);
CREATE INDEX idx_event_inbox_status   ON event_inbox (status) WHERE status <> 'processed';

CREATE TABLE outbox_event (
    event_id      UUID        PRIMARY KEY,
    event_type    TEXT        NOT NULL,
    event_version INTEGER     NOT NULL DEFAULT 1,
    occurred_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    source        TEXT        NOT NULL DEFAULT 'inventory',
    event_key     TEXT        NOT NULL,
    topic         TEXT        NOT NULL DEFAULT 'inventory.events',
    payload       JSONB       NOT NULL,             -- sobre completo a publicar
    published_at  TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_outbox_unpublished ON outbox_event (created_at) WHERE published_at IS NULL;

CREATE TABLE dead_letter_event (
    id                BIGSERIAL   PRIMARY KEY,
    original_event_id UUID,
    event_type        TEXT,
    topic             TEXT,
    event_key         TEXT,
    payload           JSONB       NOT NULL,
    error             TEXT,
    retries           INTEGER     NOT NULL DEFAULT 0,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_dlq_event_type ON dead_letter_event (event_type);
--rollback DROP TABLE dead_letter_event;
--rollback DROP TABLE outbox_event;
--rollback DROP TABLE event_inbox;
