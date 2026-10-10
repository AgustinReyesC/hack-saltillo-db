# 08 — Decisiones y preguntas abiertas

## Decisiones tomadas

| Tema | Decisión |
|---|---|
| Alcance del repo | **Solo DB**: esquema, migraciones y seeds. Consumidor, API y agente van en otros repos. |
| Herramienta de migraciones | **Liquibase con SQL puro** + Docker Compose (Postgres 16). |
| Proveedores / órdenes de compra | **Catálogo completo inventado** (`supplier`, `purchase_request`, `purchase_order`, `purchase_line`), aunque el evento solo traiga `purchase_request_id`/`line_id`. |
| Estado de pieza | Por **instancia** (unidad física): `part_instance` con su `condition_code` + `part_status_history`. Reemplaza el modelo por tipo (`part_status`). |
| Reparación | Recetario **por unidad**: `repair_tool` + `part_instance_repair_tool` + `part_instance_repair_component`. |
| Unidades independientes | Cada unidad física es una fila (buenas y defectuosas). Ej.: 2 motores = 2 filas, aunque a uno le falte una banda y al otro un tornillo. |
| Relación con stock | Las instancias son una **capa aparte**: no modifican `movement` ni `stock_balance`. |
| Integridad del libro mayor | `movement` **inmutable** y `stock_balance.on_hand` = **suma** de movimientos, vía triggers (`015`). |
| Relación compras↔catálogo | `part.sku_norm` + función `match_part_by_sku(text)` + vista `v_sku_matches`; **>1 coincidencia = ambiguo** → revisión manual. |
| Kits | Se inventaría cada **componente**; el kit es agrupación de presentación (ver [`DECISIONES.md`](../DECISIONES.md)). |
| Necesidad | Persistida en `work_order_need` por **(work_order, bom_line_id)**; se **reemplaza**. |
| Despliegue | **Solo local** por ahora; AWS/RDS queda para después. |
| Idioma | Tablas/columnas en inglés (como el contrato); documentación en español. |

## Cómo se modeló "defectuoso"

El contrato describe la condición de la **pieza del equipo del cliente**
(`inspection_item.condition` = `ok|damaged|missing`, `action` = `buy|repair`), no del stock
propio. Para el agente se agregó `part_condition` y `part_instance` (una fila por **unidad
física**) con estados `new|functional|defective|under_repair|scrapped`. **Falta definir la
política de sincronización** entre la inspección y las instancias (ver abajo).

## Temas por definir

1. **Catálogo en tiempo de ejecución vs semilla.** El seed carga el catálogo real una vez.
   ¿El consumidor debe además aplicar `part.upserted` en vivo? (Sí, según el contrato; el seed
   es solo para desarrollo/demo.) Confirmar que la semilla no pisa cambios de runtime.

2. **Kits.** **Resuelto** en [`DECISIONES.md`](../DECISIONES.md): se inventaría cada componente;
   el kit es agrupación de presentación por `model_line.group_name` (o `name`).

3. **Familia `SERVICIO`.** Aparece en listas de partes con `action = buy`. Se marcó
   `part.is_service`. ¿Se inventaría o se trata como no inventariable?

4. **Sincronización de `part_instance`.** ¿Se crean/actualizan instancias automáticamente desde
   `inspection.approved` (dañada + repair → `defective`/`under_repair`) o las mantiene el
   taller/agente a mano? Propuesta: derivar a `part_status_history` (con `instance_id`) y dejar
   `part_instance.condition_code` editable.

5. **Alta de instancias.** ¿Cómo se identifican las unidades al entrar (serial, etiqueta,
   escaneo) y cuándo se crean (recepción, inspección, alta manual)? Hoy `serial_number` es libre.
   Definir si se autogenera un código de instancia y su etiqueta.

6. **Proveedor en el evento.** `purchase.item_received` no trae proveedor. ¿De dónde se llena
   `supplier_id`? Opciones: mapeo manual `part_number` → proveedor, catálogo externo, o dejarlo
   nulo salvo que otro proceso lo complete.

7. **Mantenimiento de `stock_balance`.** **Resuelto**: el trigger `trg_movement_apply_balance`
   mantiene `on_hand` = suma de `movement`; la app solo administra `reserved` (`015`).

8. **`v_work_order_materials`.** No se creó una vista para materiales por orden porque depende
   de la lógica de necesidad vigente/reemplazo. ¿Conviene una vista o se resuelve en la API?

9. **Importes.** Se guardan `NUMERIC(14,2)`; la API los expone como texto decimal. Confirmar
   redondeo y moneda por defecto (`MXN`).

10. **Despliegue AWS.** Resuelto con Terraform: `terraform/` crea una **VPC compartida** y una
   **RDS PostgreSQL privada**; la app (ECS) entra por **Security Group (SG→SG)** con
   `app_security_group_id`, sin whitelisting de IPs. La contraseña maestra la administra RDS en
   **Secrets Manager**. Las migraciones se aplican aparte con Liquibase, desde **dentro de la
   VPC** o por **túnel** (la BD es privada, sin IP pública). Pendiente: mover el state a
   S3+DynamoDB si lo administra más de una persona y endurecer para producción (`multi_az`,
   `deletion_protection`, backups ≥ 7 días).
