# 08 — Decisiones y preguntas abiertas

## Decisiones tomadas

| Tema | Decisión |
|---|---|
| Alcance del repo | **Solo DB**: esquema, migraciones y seeds. Consumidor, API y agente van en otros repos. |
| Herramienta de migraciones | **Liquibase con SQL puro** + Docker Compose (Postgres 16). |
| Proveedores / órdenes de compra | **Catálogo completo inventado** (`supplier`, `purchase_request`, `purchase_order`, `purchase_line`), aunque el evento solo traiga `purchase_request_id`/`line_id`. |
| Estado de pieza | **Ambos**: estado actual (`part_status`) + historial (`part_status_history`), derivable de inspecciones y ajustable manualmente. |
| Reparación | Recetario con `repair_tool` + `part_repair_tool` + `part_repair_component`. |
| Despliegue | **Solo local** por ahora; AWS/RDS queda para después. |
| Idioma | Tablas/columnas en inglés (como el contrato); documentación en español. |

## Cómo se modeló "defectuoso"

El contrato describe la condición de la **pieza del equipo del cliente**
(`inspection_item.condition` = `ok|damaged|missing`, `action` = `buy|repair`), no del stock
propio. Para el agente se agregó `part_condition` / `part_status` con estados
`new|functional|defective|under_repair|scrapped`. **Falta definir la política de sincronización
entre ambos** (ver abajo).

## Temas por definir

1. **Catálogo en tiempo de ejecución vs semilla.** El seed carga el catálogo real una vez.
   ¿El consumidor debe además aplicar `part.upserted` en vivo? (Sí, según el contrato; el seed
   es solo para desarrollo/demo.) Confirmar que la semilla no pisa cambios de runtime.

2. **Kits.** El contrato deja libre si se inventaría el kit, sus componentes o ambos. Hoy
   `model_line.group_name` permite agrupar. ¿Qué política se documenta en el *documento de
   decisiones*?

3. **Familia `SERVICIO`.** Aparece en listas de partes con `action = buy`. Se marcó
   `part.is_service`. ¿Se inventaría o se trata como no inventariable?

4. **Sincronización de `part_status`.** ¿Se deriva automáticamente de `inspection.approved`
   (dañada + repair → `defective`/`under_repair`) o lo mantiene el taller/agente a mano?
   Propuesta: derivar a `part_status_history` y dejar `part_status` editable.

5. **Proveedor en el evento.** `purchase.item_received` no trae proveedor. ¿De dónde se llena
   `supplier_id`? Opciones: mapeo manual `part_number` → proveedor, catálogo externo, o dejarlo
   nulo salvo que otro proceso lo complete.

6. **Mantenimiento de `stock_balance`.** Hoy no hay triggers: el consumidor/API lo actualiza.
   ¿Se prefiere un trigger sobre `movement` para que la proyección sea automática e
   imposible de desincronizar? (Evaluar rendimiento con el volumen del dataset.)

7. **`v_work_order_materials`.** No se creó una vista para materiales por orden porque depende
   de la lógica de necesidad vigente/reemplazo. ¿Conviene una vista o se resuelve en la API?

8. **Importes.** Se guardan `NUMERIC(14,2)`; la API los expone como texto decimal. Confirmar
   redondeo y moneda por defecto (`MXN`).

9. **Despliegue AWS.** Cuando toque: RDS PostgreSQL + correr los changesets con Liquibase.
   Definir si se agrega IaC (Terraform/CDK) o solo scripts.
