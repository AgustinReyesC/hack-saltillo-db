# 05 — Extensiones del agente: instancias, estado y reparación

El contrato original no describe el estado de cada pieza ni cómo repararla. Estas tablas
completan el modelo para que el **agente conversacional** responda preguntas de negocio.

La clave del diseño: cada **unidad física** es una fila independiente (**instancia**), no el
tipo de producto. Así dos motores iguales pueden estar en estados distintos y necesitar
reparaciones distintas (a uno le falta una banda, al otro un tornillo).

> Esto es una **capa aparte** del inventario: las instancias **no** modifican `movement` ni
> `stock_balance`. El stock sigue siendo por cantidad; las instancias sirven para estado y
> reparación.

## Estado de una unidad

Catálogo `part_condition` (sembrado):

| `condition_code` | Nombre | `is_available` | Significado |
|---|---|---|---|
| `new` | Nuevo | TRUE | Sin uso. |
| `functional` | Funcional | TRUE | En condiciones de uso. |
| `defective` | Defectuoso | FALSE | Requiere reparación antes de usarse. |
| `under_repair` | En reparación | FALSE | En banco de trabajo. |
| `scrapped` | Descartado | FALSE | No reparable. |

- `part_instance`: una fila por **unidad física**, con su `condition_code`, ubicación, orden y
  opcionalmente `serial_number`.
- `part_status_history`: cambios de estado a lo largo del tiempo (puede referir una instancia).

### ¿Quién escribe el estado?

Dos fuentes que conviven:

1. **Derivado de inspecciones** (automático): un `inspection_item` con `condition = 'damaged'`
   y `action = 'repair'` implica que la pieza del equipo está defectuosa. Al aprobarse la
   inspección se puede crear/actualizar la `part_instance` correspondiente y registrar el
   cambio en `part_status_history`.
2. **Manual / del taller**: el agente o un operador ajusta `part_instance.condition_code`
   cuando una unidad pasa a `under_repair`, `functional`, etc.

> `condition`/`action` de la inspección describen la **pieza del equipo del cliente**. La
> `part_instance` permite reflejar también el estado del stock propio.

## Recetario de reparación (por unidad)

- `repair_tool`: instrumentos del taller (prensa, extractor, micrómetro, balanceadora, horno…).
- `part_instance_repair_tool`: qué instrumentos hacen falta para reparar **esa unidad**.
- `part_instance_repair_component`: qué repuestos le faltan a **esa unidad** (banda, tornillo).

La vista `v_part_instance_agent` expone `tools` (arreglo de nombres) y `missing_components`,
que es el "campo de herramientas necesarias" pedido.

## Preguntas típicas del agente

### ¿Qué unidades defectuosas hay y con qué se reparan?
```sql
SELECT instance_id, sku, name, condition_name, tools, missing_components, serial_number
FROM v_part_instance_agent
WHERE condition_code IN ('defective', 'under_repair')
ORDER BY name, instance_id;
```

### ¿Tengo la pieza X? (sí / no)
```sql
SELECT part_id, sku, name, on_hand, reserved, available, defective_units, functional_units
FROM v_part_agent_summary
WHERE sku ILIKE :q OR name ILIKE :q;
```

### ¿Qué herramientas necesita la unidad 900001?
```sql
SELECT t.name AS instrumento, rt.quantity, rt.notes
FROM part_instance_repair_tool rt
JOIN repair_tool t ON t.tool_id = rt.tool_id
WHERE rt.instance_id = :instance_id
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
- Hablar de **unidades** (instancias), no de tipos: "tienes 2 motores: 1 funcional y 1
  defectuoso al que le falta la banda".
- Si el resultado es ambiguo (varias piezas con el mismo `sku`), pedir al usuario que elija.
- Una unidad `defective`/`under_repair` **no** cuenta como disponible.
- Si la pieza es `SERVICIO`, aclarar que no se inventaría.
