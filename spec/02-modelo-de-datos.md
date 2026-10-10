# 02 — Modelo de datos

Todas las tablas, agrupadas por dominio. Tipos: `TIMESTAMPTZ` en UTC, importes
`NUMERIC(14,2)`, IDs enteros como los manda el contrato.

## 1. Eventos y trazabilidad

### `event_inbox`
Registro crudo de cada evento de entrada. Es la base de la **idempotencia** y del **replay**.

| Columna | Tipo | Notas |
|---|---|---|
| `event_id` | UUID PK | Clave de deduplicación. |
| `event_type` | TEXT | `part.upserted`, `inspection.approved`, … |
| `event_version` | INT | 1. |
| `occurred_at` | TIMESTAMPTZ | Cuándo pasó en el taller (no cuándo llegó). |
| `source` | TEXT | `shop-floor`. |
| `event_key` | TEXT | Llave de partición del tópico. |
| `topic` | TEXT | `shop.catalog`, `shop.work_orders`, … |
| `payload` | JSONB | Sobre completo del evento. |
| `status` | TEXT | `received` \| `processed` \| `failed`. |
| `error` | TEXT | Motivo del fallo. |
| `received_at` / `processed_at` | TIMESTAMPTZ | Marcas de tiempo. |

### `outbox_event`
Eventos `stock.*` a publicar en `inventory.events`. El publicador toma las filas con
`published_at IS NULL` y las marca al confirmar.

| Columna | Tipo |
|---|---|
| `event_id` (PK), `event_type`, `event_version`, `occurred_at`, `source`, `event_key`, `topic`, `payload` (JSONB), `published_at`, `created_at` |

### `dead_letter_event`
Evento que no se pudo procesar tras reintentar (`inventory.dlq`).
`id`, `original_event_id`, `event_type`, `topic`, `event_key`, `payload`, `error`, `retries`,
`created_at`.

## 2. Catálogo

### `unit` — `unit_id`, `name`.
### `part`
| Columna | Notas |
|---|---|
| `part_id` PK | |
| `sku` | Puede ser `NULL` y puede repetirse. |
| `sku_norm` | Generada: `lower(btrim(sku))`; se usa para relacionar compras. |
| `name`, `family`, `group_name`, `subgroup` | |
| `unit_id` FK → `unit` | |
| `image_url` | |
| `is_service` | `TRUE` si `family = 'SERVICIO'` (no se inventaría). |
| `active` | `part.upserted` puede dar de baja. |

Índices: `sku_norm`, `active`.

### `location`
`location_id` PK, `code` (UNIQUE, Code 128), `name`, `is_workbench`, `is_receiving`
(`U-100`), `active`.

### `model` — `model_id` PK, `model_name`, `brand`.
### `model_line` (BOM)
`bom_line_id` PK, `model_id` FK, `part_id` FK (NULL permitido), `name`, `group_name`
(mismo valor = kit), `unit_id` FK, `qty_per_unit` (NULL), `sort_order`, `active`.

`bom.upserted` trae la lista **completa** del modelo: las líneas que ya no vengan se marcan
`active = FALSE` (no se borran).

## 3. Taller

### `work_order`
`work_order_id` PK, `code` UNIQUE (`R` + DDMMYY + consecutivo), `model_id` FK, `department`,
`stage`, `received_at`, `deleted`.

### `work_order_stage`
Historial: `id`, `work_order_id` FK, `from_stage`, `to_stage`, `occurred_at`, `event_id`.

### `inspection`
`inspection_id` PK, `work_order_id` FK, `kind` (`quick`/`full`),
`status` (`submitted`/`approved`/`rejected`/`discarded`/`voided`), `approved_by`,
`approved_at`, `reason`, `submitted_at`.

### `inspection_item`
`inspection_item_id` PK, `inspection_id` FK, `bom_line_id` FK, `part_id` FK (NULL = sin
identificar), `name`, `group_name`, `condition` (`ok`/`damaged`/`missing`),
`action` (`buy`/`repair`/NULL), `quantity` (NULL), `note`.

## 4. Compras

> El contrato solo trae `purchase_request_id`, `request_number`, `line_id`, `part_number`. El
> catálogo de proveedor y orden de compra es una **extensión** de este repo.

### `supplier` — `supplier_id` PK, `code` UNIQUE, `name`, `contact_name`, `email`, `phone`, `active`.
### `purchase_request` — `purchase_request_id` PK, `request_number` UNIQUE, `supplier_id` FK, `work_order_id` FK, `status`, `requested_at`.
### `purchase_order` — `purchase_order_id` PK, `po_number` UNIQUE, `supplier_id` FK, `purchase_request_id` FK, `status`, `currency`, `ordered_at`, `expected_at`.
### `purchase_line`
`line_id` PK, `purchase_request_id` FK, `purchase_order_id` FK,
`part_number`, `part_id` FK (relación con catálogo), `description`, `quantity`,
`unit_price`, `currency`, `purpose` (`restock`/`customer_order`), `work_order_code`,
`match_status` (`pending`/`matched`/`unmatched`/`resolved`), `received_at`.

### `unmatched_receipt`
`id` PK, `purchase_line_id` FK UNIQUE, `part_number`, `description`, `quantity`,
`unit_price`, `currency`, `received_at`, `work_order_code`,
`status` (`pending`/`resolved`), `resolved_part_id` FK, `resolved_location_id` FK,
`resolved_at`.

## 5. Libro mayor

### `movement` (inmutable)
`movement_id` PK, `type` (`receipt`/`issue`/`transfer_out`/`transfer_in`/`adjustment`),
`part_id` FK, `location_id` FK, `quantity` (con signo, `<> 0`), `unit_cost`, `currency`,
`reference`, `occurred_at`, `event_id`.

Signo: `receipt` +, `issue` −, `transfer_out` −, `transfer_in` +, `adjustment` = delta (puede
ser ±).

### `stock_balance` (proyección)
PK `(part_id, location_id)`; `on_hand`, `reserved`, `available` (generada = `on_hand - reserved`),
`updated_at`.

> **No** hay `CHECK (available >= 0)`: el conteo cíclico autorizado puede dejarlo negativo.
> La app garantiza no negativo en reservas y salidas.

## 6. Compromisos

### `reservation`
`reservation_id` PK, `work_order_id` FK, `part_id` FK, `inspection_item_id` FK,
`quantity`, `status` (`active`/`fulfilled`/`cancelled`).

### `shortage`
`shortage_id` PK, `work_order_id` FK, `part_id` FK (NULL = sin identificar), `name`,
`missing_quantity` (NULL), `inspection_item_id` FK, `status` (`open`/`closed`),
`opened_at`, `closed_at`.

## 7. Reabasto

### `reorder_policy` — `part_id` PK, `min_quantity`, `max_quantity`, `reorder_quantity`, `lead_time_days`.
### `reorder_suggestion` — `part_id` PK, `suggested_quantity` (≥1), `work_order_ids` INT[].

## 8. Extensiones del agente

Cada **unidad física** se registra como una **instancia** independiente (buena o defectuosa),
con su propio estado y recetario de reparación. Ej.: dos motores iguales = dos `part_instance`,
aunque a uno le falte una banda y al otro un tornillo.

### `part_condition` — `condition_code` PK, `name`, `description`, `is_available`, `sort_order`.
Valores sembrados: `new`, `functional`, `defective`, `under_repair`, `scrapped`.

### `part_instance` — `instance_id` PK, `part_id` FK (tipo de producto), `condition_code` FK,
`location_id` FK, `work_order_id` FK, `inspection_item_id` FK, `serial_number`, `note`, timestamps.
Una fila por unidad física.

### `part_instance_repair_tool` — PK `(instance_id, tool_id)`; `quantity`, `notes`.
Herramientas necesarias para reparar **esa unidad**.

### `part_instance_repair_component` — PK `(instance_id, component_part_id)`; `quantity`, `notes`.
Repuestos que le faltan a **esa unidad** (banda, tornillo, …).

### `part_status_history` — `id` PK, `part_id` FK, `instance_id` FK (NULL), `condition_code` FK,
`work_order_id`, `note`, `changed_at`, `event_id`.

### `repair_tool` — `tool_id` PK, `code` UNIQUE, `name`, `description`, `active`.

## 9. Vistas

| Vista | Qué resuelve |
|---|---|
| `v_part_availability` | Saldo total por pieza (`on_hand`, `reserved`, `available`). |
| `v_part_agent_summary` | Por tipo: cuántas unidades hay en cada estado + saldo. |
| `v_part_instance_agent` | Por unidad: estado, `tools` (arreglo) y `missing_components`. |
| `v_open_shortages` | Faltantes abiertos (con `work_order_code`). |
| `v_unmatched_receipts` | Recepciones pendientes de relacionar. |
| `v_reorder_suggestions` | Sugerencias vigentes. |
| `v_part_ledger` | Movimientos con saldo corrido por pieza. |
