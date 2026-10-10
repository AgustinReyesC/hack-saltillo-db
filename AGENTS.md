# AGENTS.md — Contexto del repositorio

Este archivo es el **punto de entrada de contexto** para cualquier agente o persona que
trabaje en `hack-saltillo-db`. Léelo antes de tocar nada.

## Qué es este repositorio

Solo la **base de datos PostgreSQL** del *Almacén inteligente para taller* (hackathon
Saltillo). Contiene:

- El **esquema** y las **migraciones** (Liquibase, SQL puro).
- El **catálogo semilla** (productos, ubicaciones, modelos/BOM, proveedores, herramientas).
- Vistas de apoyo para la API y el agente.

**No** contiene el consumidor de Kafka, la API HTTP ni el agente conversacional: esos viven
en otros repos y **consumen este esquema**.

## Documentación detallada

La carpeta [`spec/`](spec/README.md) contiene el contexto de implementación completo:

| Documento | Contenido |
|---|---|
| [`spec/01-arquitectura.md`](spec/01-arquitectura.md) | Piezas del sistema, flujo de eventos y alcance de este repo. |
| [`spec/02-modelo-de-datos.md`](spec/02-modelo-de-datos.md) | Todas las tablas, columnas e índices. |
| [`spec/03-flujo-eventos.md`](spec/03-flujo-eventos.md) | Cómo procesar cada evento de entrada y qué escribir. |
| [`spec/04-mapeo-contrato.md`](spec/04-mapeo-contrato.md) | Mapeo evento/endpoint del contrato → tablas/vistas. |
| [`spec/05-agente-extensiones.md`](spec/05-agente-extensiones.md) | Estado de pieza y recetario de reparación; consultas del agente. |
| [`spec/06-reglas-e-invariantes.md`](spec/06-reglas-e-invariantes.md) | Idempotencia, no negativos, reconstrucción, reemplazo de necesidad. |
| [`spec/07-migraciones-y-dev-local.md`](spec/07-migraciones-y-dev-local.md) | Cómo crear migraciones y levantar el entorno local. |
| [`spec/08-preguntas-abiertas.md`](spec/08-preguntas-abiertas.md) | Decisiones tomadas y temas por definir. |

## Reglas duras

1. **El contrato manda.** Si algo contradice al kit `hackaton-inventarios`, gana el contrato.
2. **No se modifica** el simulador ni el formato de los eventos de entrada.
3. **Nombres y formas** de los eventos/rutas de salida son fijos; se pueden **agregar** campos,
   nunca cambiar los existentes.
4. **La base de datos es reconstruible**: `movement` es la fuente de verdad y `stock_balance`
   una proyección. Borrar los saldos y reagregar los movimientos debe dar el mismo resultado.
5. **Idempotencia**: `event_inbox.event_id` es clave primaria; reenviar un evento no debe
   cambiar nada.

## Mapa rápido del esquema

- Eventos: `event_inbox`, `outbox_event`, `dead_letter_event`
- Catálogo: `unit`, `part`, `location`, `model`, `model_line`
- Taller: `work_order`, `work_order_stage`, `inspection`, `inspection_item`
- Compras: `supplier`, `purchase_request`, `purchase_order`, `purchase_line`, `unmatched_receipt`
- Libro mayor: `movement` (inmutable) y `stock_balance` (proyección, `on_hand` = suma de movimientos vía trigger)
- Compromisos: `reservation`, `shortage`, `work_order_need`
- Reabasto: `reorder_policy`, `reorder_suggestion`
- Agente: `part_condition`, `part_instance`, `part_instance_repair_tool`, `part_instance_repair_component`, `part_status_history`, `repair_tool`
- Vistas: `v_part_availability`, `v_part_agent_summary`, `v_part_instance_agent`, `v_open_shortages`, `v_unmatched_receipts`, `v_reorder_suggestions`, `v_part_ledger`, `v_sku_matches`
- Funciones: `match_part_by_sku(text)` (relación de compras)
- Integridad: triggers de inmutabilidad de `movement`, proyección de `stock_balance` y guarda `reserved <= on_hand`

## Cómo levantar el entorno

```bash
copy .env.example .env      # PowerShell;  cp en bash
docker compose up -d        # Postgres + Liquibase (esquema y seeds)
docker compose exec postgres psql -U inventario -d inventario
```

Para volver a empezar de cero: `docker compose down -v && docker compose up -d`.

## Convenciones

- Nombres de tablas/columnas en **inglés** (como el contrato). Documentación en español.
- Importes en `NUMERIC(14,2)`; en la API se exponen como texto decimal (`"1850.00"`).
- Fechas en `TIMESTAMPTZ` (UTC).
- Cada migración es un archivo `--liquibase formatted sql` en `liquibase/changelog/changes/`
  e incluye su `--rollback`.
