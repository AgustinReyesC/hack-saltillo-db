# hack-saltillo-db

Base de datos **PostgreSQL** del servicio de inventario del *Almacén inteligente para taller*
(hackathon Saltillo). Este repositorio es **solo la base de datos**: el esquema, las
migraciones (Liquibase) y los datos de catálogo. El consumidor de Kafka, la API y el agente
viven en otros repositorios y **usan este esquema**.

El diseño parte del contrato del kit `hackaton-inventarios`:

- **Entrada** (`shop.catalog`, `shop.work_orders`, `shop.inspections`, `shop.purchasing`):
  `part.upserted`, `location.upserted`, `bom.upserted`, `work_order.*`, `inspection.*` y
  `purchase.item_received`.
- **Salida** (`inventory.events`): los 9 eventos `stock.*` y `inventory.dlq`.
- **API**: saldos, kardex, materiales de orden, faltantes, sugerencias, recepciones sin
  relacionar, salidas, transferencias y conteos.

Además de lo que exige el contrato, este esquema agrega lo necesario para el **agente**: cada
**unidad física** (instancia) se registra como una fila independiente, con su estado
(**funcional / defectuoso / en reparación**) y su **recetario de reparación** (instrumentos y
repuestos faltantes). Un mismo producto puede tener varias unidades con daños distintos (ej.
dos motores: a uno le falta una banda y al otro un tornillo). Más un catálogo completo de
**proveedores y órdenes de compra**.

## Requisitos

- Docker Engine + Docker Compose v2 (Docker Desktop o Docker Engine en WSL2). **Único
  requisito** para el camino recomendado.
- Opcional: Python 3.10+ (para regenerar el catálogo con
  `scripts/generate_catalog_seed.py`).
- Opcional: Liquibase CLI + un PostgreSQL ya existente, si no quieres usar Docker.

## Inicialización paso a paso

**1. Clonar el repositorio**

```bash
git clone <url-del-repo> hack-saltillo-db
cd hack-saltillo-db
```

**2. Crear el archivo de entorno**

```bash
cp .env.example .env          # en Windows PowerShell: copy .env.example .env
```

Valores por defecto (puedes cambiarlos en `.env`):

| Variable | Valor | Qué es |
|---|---|---|
| `POSTGRES_DB` | `inventario` | Nombre de la base. |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | `inventario` | Credenciales locales. |
| `POSTGRES_PORT` | `5432` | Puerto expuesto en tu máquina. |
| `LIQUIBASE_CONTEXTS` | `seed` | `seed` = esquema + datos de ejemplo; vacío = solo esquema. |

**3. Levantar la base de datos**

```bash
docker compose up -d
```

Esto arranca **Postgres 16** y un contenedor **Liquibase** que aplica, en orden, el esquema
(`liquibase/changelog/changes/`) y los datos semilla (`liquibase/changelog/seed/`).

**4. Verificar que quedó lista**

```bash
docker compose logs -f liquibase          # busca "liquibase: Update has been successful"
```

Conectar con `psql` y comprobar que hay tablas y catálogo:

```bash
docker compose exec postgres psql -U inventario -d inventario -c "\dt"
docker compose exec postgres psql -U inventario -d inventario -c "SELECT count(*) FROM part;"
```

La conexión queda disponible en `localhost:5432` con
usuario/clave/base `inventario`/`inventario`/`inventario`.

### Ejecutarlo desde WSL2 con Docker Engine

Ejecuta estos comandos dentro de la distribución WSL donde está disponible tu Docker Engine.
Para evitar problemas de rendimiento y de montaje de archivos, guarda ambos repositorios en el
sistema de archivos Linux de WSL, por ejemplo:

```text
~/src/hack-saltillo-db/
~/src/hackaton-inventarios/data/events.jsonl
```

Desde la raíz de `hack-saltillo-db`, genera primero el SQL del catálogo y luego inicia los
contenedores:

```bash
docker info
docker compose version
cp .env.example .env
python3 scripts/generate_catalog_seed.py --events ../hackaton-inventarios/data/events.jsonl
docker compose up --build -d
docker compose logs --follow liquibase
```

`docker info` y `docker compose version` deben funcionar desde WSL antes de comenzar. El
script de Python solo genera `liquibase/changelog/seed/099_catalog_generated.sql`; no se
conecta a PostgreSQL. Liquibase carga ese SQL automáticamente durante el primer arranque.
Python 3 no necesita paquetes externos para ejecutar el generador.

Comprueba que Liquibase terminó y que hay registros cargados:

```bash
docker compose ps --all
docker compose exec postgres psql -U inventario -d inventario -c "SELECT count(*) AS parts FROM part;"
docker compose exec postgres psql -U inventario -d inventario -c "SELECT count(*) AS locations FROM location;"
```

Si no tienes el repositorio `hackaton-inventarios`, puedes omitir el comando Python y usar el
SQL generado que ya está incluido en este repositorio. Si la base ya fue inicializada y el
generador cambia un changeset que Liquibase aplicó, no vuelvas a ejecutarlo sobre esa misma
base: Liquibase reportará un checksum distinto. Para datos nuevos, crea una migración nueva;
para descartar una base local y reconstruirla, `docker compose down -v` elimina
permanentemente su volumen.

**5. Reiniciar desde cero** (borra el volumen de datos y reaplica todo)

```bash
docker compose down -v && docker compose up -d
```

### Variantes

- **Solo el esquema, sin datos de ejemplo**: en `.env` deja `LIQUIBASE_CONTEXTS=` y corre
  `docker compose run --rm liquibase`.
- **Sin Docker** (Postgres propio + Liquibase CLI, desde la raíz del repo):

  ```bash
  liquibase --defaults-file=liquibase/liquibase.properties \
    --url=jdbc:postgresql://localhost:5432/inventario \
    --username=inventario --password=inventario update
  ```

- **Aplicar cambios nuevos al esquema**: agrega un changeset (ver
  [`spec/07-migraciones-y-dev-local.md`](spec/07-migraciones-y-dev-local.md)) y vuelve a correr
  `docker compose run --rm liquibase`.

## Estructura

```
docker-compose.yml            Postgres + Liquibase
liquibase/
  Dockerfile                  Liquibase + driver JDBC de PostgreSQL
  liquibase.properties        Config para usar el CLI de Liquibase sin Docker
  changelog/
    db.changelog-master.yaml  Orden de aplicación
    changes/                  Esquema (un archivo por dominio)
    seed/                     Datos: referencia (siempre), muestra y catálogo generado (contexto `seed`)
scripts/
  generate_catalog_seed.py    Regenera el catálogo desde events.jsonl del kit
```

## Modelo de datos

### Eventos y trazabilidad
| Tabla | Para qué |
|---|---|
| `event_inbox` | Evento crudo con `event_id` único → **idempotencia** y **replay** para reconstruir. |
| `outbox_event` | Eventos `stock.*` a publicar en `inventory.events` (patrón outbox). |
| `dead_letter_event` | Eventos que no se pudieron procesar (`inventory.dlq`). |

### Catálogo
`unit`, `part` (con `sku_norm` para relacionar compras y `is_service` para la familia
SERVICIO), `location` (marca `U-100` como recepción), `model`, `model_line` (BOM; la lista
vigente queda `active = true`).

### Taller
`work_order`, `work_order_stage`, `inspection`, `inspection_item` (`condition`:
`ok|damaged|missing`, `action`: `buy|repair`).

### Compras (catálogo propio)
`supplier`, `purchase_request` (llave `PR-<request_number>`), `purchase_order`,
`purchase_line` (`part_number` → `part_id`, `match_status`) y `unmatched_receipt` (con
estado `pending|resolved`).

### Libro mayor
`movement` es **inmutable** (`receipt|issue|transfer_out|transfer_in|adjustment`, cantidad
con signo). `stock_balance` es la **proyección** por `(part_id, location_id)` con
`on_hand`, `reserved` y `available` (columna generada `on_hand - reserved`).
El stock **nunca** se edita directo: se recalcula sumando movimientos.

> El conteo cíclico (`POST /counts`) es la única operación que puede dejar `available`
> negativo, por eso **no** hay `CHECK (available >= 0)`; esa regla la aplica la app en
> reservas y salidas.

### Compromisos y reabasto
`reservation` (`active|fulfilled|cancelled`), `shortage` (`open|closed`),
`reorder_policy` (mínimo/máximo/reorden/lead time) y `reorder_suggestion`.

### Extensiones del agente
Cada **unidad física** es una fila independiente (buena o defectuosa), con su propio estado y
recetario de reparación.

| Tabla | Para qué |
|---|---|
| `part_condition` | Catálogo de estados: `new`, `functional`, `defective`, `under_repair`, `scrapped`. |
| `part_instance` | **Instancia**: una unidad física (ej. dos motores = dos filas). |
| `part_instance_repair_tool` | Herramientas necesarias para reparar **esa unidad**. |
| `part_instance_repair_component` | Repuestos que le faltan a **esa unidad** (banda, tornillo). |
| `part_status_history` | Historial de cambios de estado (opcionalmente por instancia). |
| `repair_tool` | Instrumentos/herramientas del taller. |

### Vistas de apoyo
`v_part_availability`, `v_part_agent_summary`, `v_part_instance_agent`, `v_open_shortages`,
`v_unmatched_receipts`, `v_reorder_suggestions`, `v_part_ledger`.

## Consultas del agente

¿Tengo una pieza y en qué estado están sus unidades?

```sql
SELECT part_id, sku, name, on_hand, reserved, available,
       defective_units, under_repair_units, functional_units, total_units
FROM v_part_agent_summary
WHERE sku ILIKE '%7014%' OR name ILIKE '%rodamiento%';
```

¿Qué unidades defectuosas hay y con qué se reparan? (`tools` es el campo pedido)

```sql
SELECT instance_id, sku, name, condition_name, tools, missing_components, serial_number
FROM v_part_instance_agent
WHERE condition_code = 'defective'
ORDER BY name, instance_id;
```

## Regenerar el catálogo real

`liquibase/changelog/seed/099_catalog_generated.sql` se genera desde
`../hackaton-inventarios/data/events.jsonl` (256 productos, 67 ubicaciones, 5 modelos,
163 líneas de BOM). Para regenerarlo:

```bash
python scripts/generate_catalog_seed.py
# o indicando la ruta:
python scripts/generate_catalog_seed.py --events "..\..\hackaton-inventarios\data\events.jsonl"
```

## Mapeo contrato → tablas

| Evento de entrada | Tablas que alimenta |
|---|---|
| `part.upserted` | `part`, `unit` |
| `location.upserted` | `location` |
| `bom.upserted` | `model`, `model_line` |
| `work_order.opened/.stage_changed/.deleted` | `work_order`, `work_order_stage` |
| `inspection.submitted/.approved/.rejected/.discarded/.voided` | `inspection`, `inspection_item` (+ `reservation`, `shortage`) |
| `purchase.item_received` | `purchase_request`, `purchase_line`, `unmatched_receipt` (y `supplier`/`purchase_order`) |

| Evento de salida | Origen |
|---|---|
| `stock.received` | `movement` + `outbox_event` |
| `stock.reserved` / `stock.shortage_detected` | `reservation` / `shortage` |
| `stock.issued` / `stock.transferred` / `stock.adjusted` | `movement` |
| `stock.reorder_suggested` | `reorder_suggestion` |
| `stock.unmatched_receipt` | `unmatched_receipt` |

## Reglas del reto cubiertas por el esquema

- **Idempotencia**: `event_inbox.event_id` es PK; el consumidor ignora duplicados.
- **Reconstrucción**: `movement` es la fuente de verdad; borrar `stock_balance` y reagregar
  los movimientos reconstruye el saldo.
- **Sin stock negativo** en reservas/salidas: la app valida con `available`; solo el conteo
  autorizado puede quedar negativo.
- **Orden entre tópicos**: `event_inbox` permite reintentar/encolar eventos que llegan antes
  que sus dependencias.

## Estado y pendientes

- Despliegue en AWS (RDS) queda **para después**; por ahora solo local.
- El consumidor de Kafka, la API y el agente son repos aparte y consumen este esquema.
- No se modifica el simulador ni el formato de los eventos de entrada.
