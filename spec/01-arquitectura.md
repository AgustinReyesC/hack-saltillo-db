# 01 — Arquitectura

## Proyecto

Servicio de inventario de un taller de reparación de husillos y motores. El taller ya existe y
**publica eventos en Kafka**; el equipo construye el inventario que los consume y responde con
existencias, reservas y faltantes en tiempo real.

## Piezas del sistema

```
              shop.catalog / shop.work_orders / shop.inspections / shop.purchasing
                          (broker Kafka · Redpanda)
                                     │
                                     ▼
                    ┌──────────────────────────────┐
                    │  Consumidor (otro repo)       │
                    │  · dedup por event_id         │
                    │  · procesa reglas de negocio  │
                    └──────────────┬───────────────┘
                                   │ escribe/lee
                                   ▼
        ┌───────────────────────────────────────────────────┐
        │        hack-saltillo-db  (ESTE REPOSITORIO)        │
        │  Postgres · esquema · migraciones Liquibase         │
        └──────────────┬───────────────────────┬────────────┘
                       │                       │
                       │ lee                   │ escribe outbox
                       ▼                       ▼
        ┌────────────────────────┐   inventory.events / inventory.dlq
        │  API HTTP (otro repo)  │──────────────▶ (broker)
        │  + Agente (otro repo)  │
        └────────────────────────┘
```

- **Este repo (DB)**: define el esquema, las migraciones y el catálogo. Es la fuente de verdad
  del estado del inventario.
- **Consumidor**: lee los tópicos de entrada, aplica las reglas y persiste en estas tablas;
  publica los eventos de salida usando `outbox_event`.
- **API**: expone consultas y comandos (`/issues`, `/transfers`, `/counts`, etc.) leyendo y
  escribiendo estas tablas.
- **Agente**: responde preguntas del tipo *"¿tengo X pieza?"* consultando vistas como
  `v_part_agent_summary`.

## Alcance de este repositorio

Incluye:

- Esquema y migraciones (Liquibase, SQL puro).
- Datos de referencia (unidades, estados) y catálogo semilla (productos, ubicaciones,
  modelos/BOM, proveedores, herramientas).
- Vistas de apoyo.

No incluye:

- Consumidor de Kafka.
- API HTTP.
- Agente conversacional.
- Infra en AWS (por ahora solo local; RDS queda para después).

## Garantías de entrega (del taller)

- **Al menos una vez**: un evento puede repetirse → deduplicar por `event_id`.
- **Orden por llave** dentro de un tópico.
- **Sin orden entre tópicos**: una inspección puede llegar antes que `part.upserted` o
  `work_order.opened`.
- **Retención completa**: se puede releer desde el inicio para reconstruir.

El esquema acompaña estas garantías con `event_inbox` (dedup + auditoría), `movement`
(inmutable) y `stock_balance` (proyección reconstruible).
