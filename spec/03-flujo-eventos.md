# 03 — Flujo de eventos

Guía para el **consumidor**: qué escribir en este esquema por cada evento de entrada, y qué
evento de salida encolar en `outbox_event`. Siempre: primero insertar en `event_inbox`
(idempotencia); si `event_id` ya existe, **no hacer nada**.

## Catálogo (`shop.catalog`)

### `part.upserted`
- `unit`: upsert por `unit_id`.
- `part`: upsert por `part_id`. `is_service = (family = 'SERVICIO')`. `sku_norm` es generada.
- Si la pieza aún no existía y algún evento anterior la referenciaba, reprocesar lo pendiente.

### `location.upserted`
- Upsert en `location`. `is_receiving = (code = 'U-100')`.

### `bom.upserted`
- Upsert en `model`.
- Reemplaza la lista: upsert de cada línea en `model_line` con `active = TRUE`; las líneas del
  modelo que ya no vengan pasan a `active = FALSE`.

> Al arrancar, y en cada reconstrucción, **consumir `shop.catalog` completo antes** de procesar
> el resto de tópicos; si no, las compras llegan antes que sus piezas y todas caen a revisión
> manual.

## Órdenes (`shop.work_orders`)

### `work_order.opened`
- Upsert en `work_order` (`stage = 'awaiting_quick_inspection'`, `deleted = FALSE`).

### `work_order.stage_changed`
- Actualiza `work_order.stage` e inserta fila en `work_order_stage`.

### `work_order.deleted`
- Marca `work_order.deleted = TRUE`.
- Libera reservas activas de la orden (`status = 'cancelled'`) y cierra faltantes abiertos
  (`status = 'closed'`, `closed_at = now()`).
- Si después llega una compra con ese `work_order_code`, entra como existencia general.

## Inspecciones (`shop.inspections`)

### `inspection.submitted`
- Upsert en `inspection` (`status = 'submitted'`, `submitted_at`).
- Reemplaza los `inspection_item` de esa inspección.

### `inspection.approved` — **la única que mueve inventario**
- `inspection.status = 'approved'`, `approved_by`, `approved_at`.
- Upsert de items.
- Por cada item con `action = 'buy'` (solo esos generan necesidad):
  - La necesidad vive por **(orden, `bom_line_id`)** y **se reemplaza**, no se suma.
  - `quantity = NULL` → usar `model_line.qty_per_unit` de esa línea vigente; si también es
    NULL → faltante con `missing_quantity = NULL`, sin reservar.
  - `part_id = NULL` → `stock.shortage_detected` con `part_id = NULL`, nunca reserva.
  - Reserva `min(available, necesidad)`:
    - Crea/actualiza `reservation` (`active`) → encola `stock.reserved`.
    - Lo que no alcance → `shortage` (`open`) → encola `stock.shortage_detected`.
  - Actualiza `stock_balance.reserved` (sin bajar `available` de 0).
- `action = 'repair'` y `condition = 'ok'` **no** reservan (pieza del cliente).
- Una inspección `full` con `items: []` no cambia nada.

### `inspection.rejected` / `inspection.discarded`
- `inspection.status` correspondiente + `reason`. No mueven inventario.

### `inspection.voided` (una inspección ya aprobada se anula)
- `inspection.status = 'voided'`.
- Libera sus reservas activas → `cancelled`, y cierra sus faltantes abiertos.

## Compras (`shop.purchasing`)

### `purchase.item_received`
- Upsert en `purchase_request` (`request_number`, `work_order_id` si el código existe).
- Upsert en `purchase_line` (`line_id`, `part_number`, cantidad, precio, `currency`,
  `purpose`, `work_order_code`).
- `purpose = 'customer_order'` → **no** entra al inventario, no surte faltantes, no emite nada.
- `purpose = 'restock'`:
  - Relacionar `part_number` con `part.sku_norm` (al menos sin mayúsculas ni espacios).
  - Si no coincide con ninguna, o coincide con más de una:
    - Insertar `unmatched_receipt` (`status = 'pending'`) → encola
      `stock.unmatched_receipt` (`key = "purchase_line:<id>"`).
  - Si coincide con exactamente una:
    - `purchase_line.part_id`, `match_status = 'matched'`.
- Registrar `movement` `receipt` (+) en la ubicación de recepción **`U-100`
  (`location_id = 100`)** con `purchase_line_id` y `unit_cost`/`currency`. El trigger
  `trg_movement_apply_balance` actualiza `stock_balance.on_hand` (la app **no** lo escribe).
    - Encolar `stock.received` (`key = "part:<id>"`).
    - Surtir faltantes de esa pieza: primero los de la orden en `work_order_code` (si sigue
      viva) y luego los demás, del más viejo al más nuevo. Cada faltante surtido:
      reserva (`stock.reserved`) + cierra faltante (`stock.shortage_resolved`).

## Comandos HTTP (los ejecuta la API, no llegan por Kafka)

- `POST /issues`: `movement` `issue` (−) con `work_order_id` e `issued_by`, consume primero la
  `reservation` de esa orden para esa pieza; si queda completa → `status = 'fulfilled'`. Encola
  `stock.issued`. Si no alcanza `on_hand` en la ubicación → **409**, no mueve nada.
- `POST /transfers`: `movement` `transfer_out` (−) y `transfer_in` (+) con el **mismo**
  `transfer_group_id`. Encola `stock.transferred`.
- `POST /counts`: un `movement` `adjustment` por diferencia con `reason` obligatorio. Encola
  `stock.adjusted`. Es la única operación que puede dejar `available` negativo.
- `POST /unmatched-receipts/{id}/resolve`: registra la entrada como si hubiera coincidido
  (movement `receipt`, `stock.received`, surte faltante) y marca `unmatched_receipt`
  `status = 'resolved'` (segundo intento → 409).

## Sugerencias de reabasto

Cuando una pieza tiene faltantes abiertos (o queda bajo su `reorder_policy.min_quantity`):
- Upsert en `reorder_suggestion` con `suggested_quantity ≥ suma de faltantes` y
  `work_order_ids` de las órdenes que la piden.
- Encola `stock.reorder_suggested` cuando nace o cambia.
