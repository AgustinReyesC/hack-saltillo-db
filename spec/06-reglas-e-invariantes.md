# 06 — Reglas e invariantes

Invariantes que el esquema asume y que el consumidor/API **deben** respetar.

## Idempotencia
- `event_inbox.event_id` es PK. Procesar dos veces el mismo `event_id` no cambia nada ni
  emite salidas nuevas. **Insertar en `event_inbox` primero; si ya existe, salir.**
- El test de contrato reenvía eventos para verificarlo.

## Sin stock negativo
- `available = on_hand - reserved` nunca debe bajar de 0 por una **reserva** ni por una
  **salida**. Lo garantiza la app al calcular `min(available, necesidad)` y al validar salidas
  (409 si no alcanza); además, la BD tiene la guarda `reserved <= on_hand`
  (`trg_stock_balance_reserved_guard`).
- **Excepción**: `POST /counts` (conteo cíclico autorizado) es la única operación que puede
  dejar `available` negativo. Por eso no hay `CHECK (available >= 0)` en `stock_balance`, y la
  guarda de `reserved` no se dispara cuando `on_hand` baja por un ajuste.

## Integridad en la base (triggers)
- `movement` es **inmutable**: `trg_movement_immutable` rechaza `UPDATE`/`DELETE`.
- `stock_balance.on_hand` lo calcula `trg_movement_apply_balance` = **suma** de `movement`.
  La app **no** debe escribir `on_hand`; solo administra `reserved`.
- `reserved <= on_hand`: `trg_stock_balance_reserved_guard` (evita sobre-reservar la última
  pieza). El consumidor además debe tomar la fila con `SELECT ... FOR UPDATE` para la carrera
  de concurrencia.

## Necesidad que se reemplaza (no se suma)
- La necesidad vive por **(work_order, bom_line_id)** en `work_order_need` y la fija la última
  aprobación que trae esa línea.
- Si sube → reservar la diferencia; si baja → liberar el excedente.
- Una línea que una aprobación posterior **no menciona** conserva su necesidad.
- `inspection.full` con `items: []` no cambia nada.

## Qué reserva y qué no
| Caso | ¿Reserva? |
|---|---|
| `condition` `damaged`/`missing` con `action = 'buy'` | Sí |
| `action = 'repair'` | No (pieza del cliente) |
| `condition = 'ok'` | No |
| `part_id = null` | No (faltante sin identificar) |
| `quantity = null` | Usa `qty_per_unit`; si también null → faltante con `missing_quantity = null`, sin reservar |

## Recepciones
- `purpose = 'customer_order'`: **no** entra al inventario, no surte faltantes, no emite nada.
- `purpose = 'restock'`: relaciona `part_number` con `part.sku_norm` (como mínimo, ignorando
  mayúsculas y espacios extremos).
  - 0 coincidencias o >1 → `unmatched_receipt` pendiente + `stock.unmatched_receipt`.
  - Exactamente 1 → entrada en `U-100` (`location_id = 100`) + `stock.received`, y surte
    faltantes (primero la orden de `work_order_code`, luego del más antiguo al más nuevo).
- Con la entrada se surten faltantes: `stock.reserved` + `stock.shortage_resolved` por cada uno.

## Cancelaciones
- `inspection.voided`: libera reservas activas y cierra faltantes de las líneas cuya necesidad
  vigente venía de esa inspección.
- `work_order.deleted`: libera todas las reservas activas y cierra los faltantes de la orden.
- Liberar una reserva **no** emite evento propio en esta versión (se ve en la API).

## Salida, transferencia y conteo
- `POST /issues`: baja el saldo y consume la reserva de esa orden para esa pieza; completa →
  `fulfilled`. Si no alcanza la ubicación → 409 sin mover nada.
- `POST /transfers`: mueve entre ubicaciones, no cambia el total.
- `POST /counts`: un ajuste por diferencia con motivo obligatorio (422 sin motivo).

## Reabasto
- Una pieza con faltantes abiertos (o bajo su mínimo, si hay `reorder_policy`) tiene una
  sugerencia vigente con `suggested_quantity` ≥ lo que falta y las órdenes en `work_order_ids`.
- Se emite `stock.reorder_suggested` cuando nace o cambia.

## Desorden y errores
- Un evento que referencia algo que aún no se conoce **no se descarta**: se reintenta/encola
  hasta que llegue (por eso el orden de consumo del catálogo primero).
- Lo que no se pueda procesar tras reintentar va a `dead_letter_event` (`inventory.dlq`) sin
  detener el consumo.

## Reconstrucción
- `movement` es la fuente de verdad. Borrar `stock_balance` y **reagregar** los movimientos
  debe dar el mismo `on_hand` por pieza y ubicación.
- Las **reservas no se comparan** en la reconstrucción: dependen de cómo se intercalen los
  tópicos al releer.

## Datos sucios esperados
- Piezas con `sku = null` y piezas distintas con el **mismo** `sku`.
- Familia `SERVICIO` que también aparece en listas de partes con `action = buy`.
- Kits: líneas con el mismo `group_name` (o el mismo `name` si `group_name` es null).
- `part_number` de compras escrito de varias formas; proveedores que no existen en el catálogo.
- Una pieza que recibe su `sku` semanas después, y otra que se da de baja.
