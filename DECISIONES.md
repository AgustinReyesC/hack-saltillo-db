# Documento de decisiones (1 página)

Servicio de inventario — almacén inteligente para taller. Alcance de este repositorio: la
**base de datos** (Postgres). Responde a las cuatro decisiones que pide el reto.

## 1. Cómo relacionamos compras con el catálogo

`purchase.item_received` trae `part_number` (texto libre), no `part_id`. Normalizamos ambos
lados igual: `sku_norm = lower(btrim(sku))`. La función `match_part_by_sku(text)` devuelve el
`part_id` **si y solo si** hay **exactamente una** coincidencia.

- 1 coincidencia → entra al inventario en `U-100` (`movement` + `stock.received`) y surte faltantes.
- 0 coincidencias o **más de una** (sku ambiguo) → `unmatched_receipt` pendiente +
  `stock.unmatched_receipt`; se relaciona a mano con `POST /unmatched-receipts/{id}/resolve`.
- La vista `v_sku_matches` (`match_count`) permite distinguir "no coincide" de "ambiguo".

## 2. Cómo manejamos kits

Las líneas del BOM se agrupan por `model_line.group_name` (o por `name` si `group_name` es
`NULL`). **Decisión: se inventaría cada componente por separado** (`part`/`movement` por
`part_id`); el kit es una **agrupación para presentación**, no una unidad de stock distinta.
Así una línea `quantity: null` con `action = buy` reserva el `qty_per_unit` de su componente.

## 3. Cómo evitamos reservas dobles

- La **necesidad** vive por **(work_order, bom_line_id)** en `work_order_need` y cada aprobación
  la **reemplaza** (no la suma): si sube se reserva la diferencia; si baja se libera el excedente.
- Al reservar se toma siempre `min(available, necesidad)`.
- **En la BD** hay una guarda: `reserved` no puede superar `on_hand` (trigger
  `trg_stock_balance_reserved_guard`), y el consumidor toma la fila con
  `SELECT ... FOR UPDATE` sobre `stock_balance` antes de decidir, de modo que dos aprobaciones
  simultáneas no se llevan la misma última pieza.
- `POST /issues` consume primero la reserva de esa orden para esa pieza; al completarla pasa a
  `fulfilled`.

## 4. Cómo garantizamos idempotencia

- `event_inbox.event_id` es **clave primaria**: el consumidor inserta el evento **antes** de
  procesarlo; si ya existe, no hace nada (dedup por `event_id`).
- Un evento que referencia algo aún desconocido no se descarta: se reintenta/encola
  (`event_inbox.status`). Lo irrecuperable va a `dead_letter_event` (`inventory.dlq`).
- La base es **reconstruible**: `movement` es la fuente de verdad e **inmutable**
  (trigger `trg_movement_immutable`); `stock_balance.on_hand` es la **suma** de los movimientos
  (trigger `trg_movement_apply_balance`). Borrar `stock_balance` y reprocesar los movimientos
  reproduce el mismo saldo.

## Resumen del esquema

Catálogo (`part`, `location`, `model`, `model_line`), taller (`work_order`, `inspection`),
compras (`supplier`, `purchase_request`, `purchase_order`, `purchase_line`, `unmatched_receipt`),
libro mayor (`movement`, `stock_balance`), compromisos (`reservation`, `shortage`,
`work_order_need`), reabasto (`reorder_policy`, `reorder_suggestion`) y agente
(`part_condition`, `part_instance`, recetario de reparación).
