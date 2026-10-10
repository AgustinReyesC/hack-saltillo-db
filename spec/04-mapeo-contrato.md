# 04 — Mapeo contrato ↔ tablas

Referencia rápida para implementar consumidor y API sin reescribir el contrato.

## Eventos de entrada → tablas

| Evento | Tópico | Tablas |
|---|---|---|
| `part.upserted` | `shop.catalog` | `unit`, `part` |
| `location.upserted` | `shop.catalog` | `location` |
| `bom.upserted` | `shop.catalog` | `model`, `model_line` |
| `work_order.opened` | `shop.work_orders` | `work_order` |
| `work_order.stage_changed` | `shop.work_orders` | `work_order`, `work_order_stage` |
| `work_order.deleted` | `shop.work_orders` | `work_order`, `reservation`, `shortage` |
| `inspection.submitted` | `shop.inspections` | `inspection`, `inspection_item` |
| `inspection.approved` | `shop.inspections` | `inspection`, `inspection_item`, `reservation`, `shortage`, `stock_balance`, `reorder_suggestion` |
| `inspection.rejected` / `.discarded` / `.voided` | `shop.inspections` | `inspection` (+ `reservation`, `shortage` en `voided`) |
| `purchase.item_received` | `shop.purchasing` | `purchase_request`, `purchase_line`, `supplier`/`purchase_order` (opcional), `unmatched_receipt`, `movement`, `stock_balance`, `reservation`, `shortage` |

## Eventos de salida (`inventory.events`) → origen y llave

| Evento | `key` | Datos desde |
|---|---|---|
| `stock.received` | `part:<id>` | `movement` receipt + `purchase_line` |
| `stock.reserved` | código de orden | `reservation` |
| `stock.shortage_detected` | código de orden | `shortage` |
| `stock.shortage_resolved` | código de orden | faltante surtido |
| `stock.issued` | código de orden | `movement` issue |
| `stock.transferred` | `part:<id>` | `movement` transfer |
| `stock.adjusted` | `part:<id>` | `movement` adjustment |
| `stock.reorder_suggested` | `part:<id>` | `reorder_suggestion` |
| `stock.unmatched_receipt` | `purchase_line:<id>` | `unmatched_receipt` |

Todos con `source = "inventory"` y el mismo sobre (`event_id`, `event_type`,
`event_version`, `occurred_at`, `key`, `data`). Se encolan en `outbox_event` y el publicador
los manda al tópico y marca `published_at`.

## API HTTP → consultas

| Método y ruta | Devuelve | Fuente sugerida |
|---|---|---|
| `GET /parts/{part_id}/availability` | `on_hand`, `reserved`, `available` totales y por ubicación | `stock_balance` / `v_part_availability` |
| `GET /parts/{part_id}/ledger` | Movimientos con `balance` corrido, del más reciente al más antiguo | `v_part_ledger` (ordenar `occurred_at DESC`) |
| `GET /work-orders/{code}/materials` | Por `bom_line_id`: `required`, `reserved`, `issued`, `missing` | `inspection_item` + `reservation` + `movement` |
| `GET /shortages?work_order_code=&part_id=` | Faltantes abiertos | `v_open_shortages` |
| `GET /reorder-suggestions` | Sugerencias vigentes | `v_reorder_suggestions` |
| `GET /unmatched-receipts` | Pendientes de relacionar | `v_unmatched_receipts` |
| `POST /unmatched-receipts/{id}/resolve` | Relaciona y registra entrada | `unmatched_receipt`, `movement` |
| `POST /issues` | Salida contra orden | `movement`, `reservation` |
| `POST /transfers` | Transferencia | `movement` |
| `POST /counts` | Ajuste por diferencia (motivo obligatorio) | `movement` |

Convenciones de la API: listas como `{"items": [...]}`; errores `{"detail": "..."}`;
importes como texto decimal; sin autenticación.

## Notas de forma

- `Availability.locations[]` requiere `location_id`, `on_hand`, `reserved`, `available` (y
  opcional `code`). Si se reserva a nivel pieza, reportar `reserved = 0` por ubicación.
- `Movement.type` ∈ `receipt|issue|transfer_out|transfer_in|adjustment`; `quantity` con signo.
- `WorkOrderMaterials.lines[]` incluye `inspection_item_id`, `bom_line_id`, `part_id`, `name`,
  `required`, `reserved`, `issued`, `missing`.
- `Shortage.part_id` y `missing_quantity` pueden ser `null`.
