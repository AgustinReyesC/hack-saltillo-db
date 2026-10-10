# 05 — Extensiones del agente: estado y reparación

El contrato original no describe el estado de cada pieza ni cómo repararla. Estas tablas
completan el modelo para que el **agente conversacional** pueda responder preguntas de negocio.

## Estado de una pieza

Catálogo `part_condition` (sembrado):

| `condition_code` | Nombre | `is_available` | Significado |
|---|---|---|---|
| `new` | Nuevo | TRUE | Sin uso. |
| `functional` | Funcional | TRUE | En condiciones de uso. |
| `defective` | Defectuoso | FALSE | Requiere reparación antes de usarse. |
| `under_repair` | En reparación | FALSE | En banco de trabajo. |
| `scrapped` | Descartado | FALSE | No reparable. |

- `part_status`: **estado actual** de cada pieza (una fila por `part_id`).
- `part_status_history`: cambios de estado a lo largo del tiempo.

### ¿Quién escribe el estado?

Dos fuentes que conviven:

1. **Derivado de inspecciones** (automático): un `inspection_item` con `condition = 'damaged'`
   y `action = 'repair'` implica que la pieza del equipo está defectuosa. Al aprobarse la
   inspección se puede registrar en `part_status_history` (y opcionalmente actualizar
   `part_status`).
2. **Manual / del taller**: el agente o un operador ajusta `part_status` cuando una pieza pasa
   a `under_repair`, `functional`, etc.

> Importante: **`condition`/`action` describen la pieza del equipo del cliente** (no stock del
> taller). Si se quiere reflejar el estado del stock propio, se usa `part_status`.

## Recetario de reparación

- `repair_tool`: instrumentos del taller (prensa, extractor, micrómetro, balanceadora, horno…).
- `part_repair_tool`: qué instrumentos y cuántos hacen falta para reparar una pieza.
- `part_repair_component`: qué repuestos/piezas consume la reparación.

Así, a una pieza defectuosa se le puede contestar *"para repararla necesitas X, Y y Z"*.

## Preguntas típicas del agente

### ¿Tengo la pieza X? (sí / no)
```sql
SELECT part_id, sku, name, on_hand, reserved, available
FROM v_part_availability
WHERE sku ILIKE :q OR name ILIKE :q;
```
Respuesta: `available > 0` → **sí, la tengo**; si `on_hand = 0` → **no la tengo**.

### ¿Tengo piezas defectuosas que se puedan arreglar?
```sql
SELECT part_id, name, condition_name, repair_tools_count, repair_components_count
FROM v_part_agent_summary
WHERE condition_code IN ('defective', 'under_repair')
ORDER BY repair_tools_count DESC;
```

### ¿Con qué se repara la pieza X?
```sql
SELECT p.name AS pieza, t.name AS instrumento, prt.quantity, prt.notes
FROM part p
JOIN part_repair_tool prt ON prt.part_id = p.part_id
JOIN repair_tool t        ON t.tool_id = prt.tool_id
WHERE p.part_id = :part_id
ORDER BY t.name;
```

### ¿Qué me falta para la orden R…?
```sql
SELECT * FROM v_open_shortages WHERE work_order_code = :code;
```

### ¿Qué debo recomprar?
```sql
SELECT * FROM v_reorder_suggestions;
```

## Reglas de respuesta sugeridas

- Distinguir **existencia** (`on_hand`) de **disponible** (`available = on_hand - reserved`).
- Si el resultado es ambiguo (varias piezas con el mismo `sku`, muy común en este dataset),
  **pedir al usuario que elija** en lugar de adivinar.
- Si la pieza es `SERVICIO`, aclarar que no se inventaría.
- Una pieza `defective`/`under_repair` no cuenta como disponible.
