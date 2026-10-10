# hack-saltillo-db

Base de datos **PostgreSQL** del servicio de inventario **Roceel** (reto *Almacén inteligente para
taller*, HackITS 2026). Este repositorio es **solo la base de datos**: el esquema, las migraciones
(Liquibase), los datos de catálogo y la infraestructura de RDS en AWS. La API
([`hack-saltillo-api`](https://github.com/AgustinReyesC/hack-saltillo-api)) es la que consume los
eventos y escribe aquí; no crea ni altera tablas.

El diseño parte del contrato del kit del reto:

- **Entrada** (`shop.catalog`, `shop.work_orders`, `shop.inspections`, `shop.purchasing`):
  `part.upserted`, `location.upserted`, `bom.upserted`, `work_order.*`, `inspection.*` y
  `purchase.item_received`.
- **Salida** (`inventory.events`): los 9 eventos `stock.*` y `inventory.dlq`.
- **API**: saldos, kardex, materiales de orden, faltantes, sugerencias, recepciones sin
  relacionar, salidas, transferencias y conteos.

Además de lo que exige el contrato, el esquema agrega lo que necesita el **agente**: cada
**unidad física** (instancia) es una fila independiente, con su estado (**funcional / defectuoso /
en reparación**) y su **recetario de reparación** (herramientas y repuestos faltantes). Un mismo
producto puede tener varias unidades con daños distintos (ej. dos motores: a uno le falta una banda
y al otro un tornillo). También hay un catálogo de **proveedores y órdenes de compra**.

## Contenido

1. [El sistema completo](#el-sistema-completo)
2. [Correr en local](#correr-en-local)
3. [Conectar con los demás repos](#conectar-con-los-demás-repos)
4. [Estructura](#estructura)
5. [Modelo de datos](#modelo-de-datos)
6. [Consultas del agente](#consultas-del-agente)
7. [Mapeo contrato → tablas](#mapeo-contrato--tablas)
8. [Reglas del reto cubiertas por el esquema](#reglas-del-reto-cubiertas-por-el-esquema)
9. [Despliegue en AWS (Terraform)](#despliegue-en-aws-terraform)

Documentación relacionada:

- [`DECISIONES.md`](DECISIONES.md): documento de decisiones del reto (compras ↔ catálogo, kits,
  reservas dobles, idempotencia).
- [`AGENTS.md`](AGENTS.md): contexto para agentes; [`spec/`](spec/README.md): contexto de
  implementación detallado.
- [`terraform/README.md`](terraform/README.md): RDS en AWS.

## El sistema completo

| Repo | Qué hace | En local |
|---|---|---|
| **`hack-saltillo-db`** (este) | PostgreSQL 16: esquema, migraciones (Liquibase) y catálogo semilla. | `localhost:5432` |
| [`hack-saltillo-broker`](https://github.com/AgustinReyesC/hack-saltillo-broker) | Colas SQS FIFO: Terraform para AWS y ElasticMQ para local. | `localhost:9324` |
| [`hack-saltillo-api`](https://github.com/AgustinReyesC/hack-saltillo-api) | Servicio de inventario (NestJS): consume las colas, lleva el libro mayor, publica `stock.*` y expone REST y WebSocket. | `localhost:8000` (HTTP), `:8443` (HTTPS) |
| [`hack-saltillo-ui`](https://github.com/AgustinReyesC/hack-saltillo-ui) | Pantallas (React + Vite): dashboard, piso con escaneo, órdenes y resolución. | `localhost:5173` |
| [`hack-saltillo-events`](https://github.com/AgustinReyesC/hack-saltillo-events) | Prototipo del agente de IA (Gemini). Aún no se conecta a la API. | proceso de consola |
| `hackathon-inventario-kit` | Kit del reto (no es repo del equipo): Redpanda, simulador, contrato y pruebas de contrato. | `:19092` Kafka, `:8080` consola, `:8090` simulador |

```mermaid
flowchart LR
    SIM["Simulador del kit<br/>:8090"] -->|"shop.*"| RP[("Redpanda<br/>:19092")]
    RP -->|"kafka_sqs_bridge.py"| MQ[("ElasticMQ / SQS<br/>:9324")]
    MQ -->|"shop-*.fifo"| API["hack-saltillo-api<br/>:8000"]
    API -->|"inventory-events / dlq"| MQ
    API <--> DB[("hack-saltillo-db<br/>:5432")]
    UI["hack-saltillo-ui<br/>:5173"] -->|"REST"| API
```

La base es el primer paso para levantar todo. El orden completo está en el
[README de la API](https://github.com/AgustinReyesC/hack-saltillo-api#levantar-todo-el-sistema-en-local).

## Correr en local

### Requisitos

- Docker Engine + Docker Compose v2 (Docker Desktop o Docker Engine en WSL2). **Único requisito** para
  el camino recomendado.
- Opcional: Python 3.10+ sin paquetes externos, para regenerar el catálogo con
  `scripts/generate_catalog_seed.py`.
- Opcional: Liquibase CLI y un PostgreSQL propio, si no quieres usar Docker.

### Paso a paso

**1. Clonar el repositorio**, como carpeta hermana de los otros repos y del kit:

```bash
git clone https://github.com/AgustinReyesC/hack-saltillo-db.git
cd hack-saltillo-db
```

**2. Crear el archivo de entorno**

```bash
cp .env.example .env          # en Windows PowerShell: copy .env.example .env
```

| Variable | Valor | Qué es |
|---|---|---|
| `POSTGRES_DB` | `inventario` | Nombre de la base. |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | `inventario` | Credenciales locales. |
| `POSTGRES_PORT` | `5432` | Puerto expuesto en tu máquina. |
| `LIQUIBASE_CONTEXT_FILTER` | `seed` | `seed` = esquema + datos de ejemplo; otro valor (p. ej. `base`) = solo esquema y datos de referencia. |

**3. Levantar la base de datos**

```bash
docker compose up -d
```

Arranca dos contenedores:

| Contenedor | Imagen | Qué hace |
|---|---|---|
| `saltillo-db` | `postgres:16-alpine` | PostgreSQL en `localhost:5432`, con los datos en el volumen `pgdata`. |
| `saltillo-liquibase` | Liquibase 4.29 + driver JDBC 42.7.4 | Aplica el esquema (`liquibase/changelog/changes/`) y los datos (`liquibase/changelog/seed/`), y termina. |

**4. Verificar que quedó lista**

```bash
docker compose logs -f liquibase          # busca "Liquibase: Update has been successful"
docker compose exec postgres psql -U inventario -d inventario -c "\dt"
docker compose exec postgres psql -U inventario -d inventario -c "SELECT count(*) FROM part;"
```

Conexión: `localhost:5432`, base/usuario/contraseña `inventario`/`inventario`/`inventario`.

```text
postgresql://inventario:inventario@localhost:5432/inventario
```

**5. Reiniciar desde cero** (borra el volumen y reaplica todo):

```bash
docker compose down -v && docker compose up -d
```

### Regenerar el catálogo real

`liquibase/changelog/seed/099_catalog_generated.sql` ya viene generado desde `data/events.jsonl` del kit
(256 piezas, 67 ubicaciones, 5 modelos, 163 líneas de lista de partes). Para regenerarlo:

```bash
python3 scripts/generate_catalog_seed.py --events ../hackathon-inventario-kit/data/events.jsonl
docker compose up --build -d
```

Sin `--events`, el script busca `../hackaton-inventarios/data/events.jsonl`. Solo escribe el `.sql`; no se
conecta a PostgreSQL. Si la base ya aplicó ese changeset, no lo regeneres sobre la misma base: Liquibase
reporta un checksum distinto. Para datos nuevos crea una migración nueva, o reconstruye con
`docker compose down -v`.

### Desde WSL2 con Docker Engine

Corre los comandos dentro de la distribución WSL que tiene Docker. Guarda los repos y el kit en el sistema de
archivos de WSL (por ejemplo `~/src/`) para evitar problemas de rendimiento y de montaje, y comprueba antes
que `docker info` y `docker compose version` funcionan. En WSL2 la VM se apaga cuando no queda ninguna
sesión abierta y los puertos dejan de verse desde Windows: mantén una terminal de WSL abierta.

### Variantes

- **Solo el esquema, sin datos de ejemplo**: en `.env` pon `LIQUIBASE_CONTEXT_FILTER=base` y corre
  `docker compose run --rm liquibase`.
- **Sin Docker** (Postgres propio + Liquibase CLI, desde la raíz del repo):

  ```bash
  liquibase --defaults-file=liquibase/liquibase.properties \
    --url=jdbc:postgresql://localhost:5432/inventario \
    --username=inventario --password=inventario update
  ```

- **Aplicar cambios nuevos al esquema**: agrega un changeset (ver
  [`spec/07-migraciones-y-dev-local.md`](spec/07-migraciones-y-dev-local.md)) y corre
  `docker compose run --rm liquibase`.

## Conectar con los demás repos

### API (`hack-saltillo-api`)

La API se conecta con estas variables en su `.env.local`:

```dotenv
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_NAME=inventario
DATABASE_USER=inventario
DATABASE_PASSWORD=inventario
DATABASE_SSL=false
```

La API usa TypeORM con `synchronize: false`: si falta una tabla o columna, la solución es una migración
aquí, no en la API.

### Una base aparte para pruebas

Las pruebas de contrato y la reconstrucción escriben mucho. Para no tocar la base `inventario`, crea otra en
el mismo contenedor y aplícale las migraciones:

```bash
docker compose exec postgres psql -U inventario -d inventario -c "CREATE DATABASE inventario_pruebas"
docker compose run --rm -e LIQUIBASE_COMMAND_URL=jdbc:postgresql://postgres:5432/inventario_pruebas liquibase
```

Y en el entorno de la API, `DATABASE_NAME=inventario_pruebas`. Para reconstruirla desde cero, con la API
detenida:

```bash
docker compose exec postgres psql -U inventario -d inventario -c "DROP DATABASE inventario_pruebas" -c "CREATE DATABASE inventario_pruebas"
docker compose run --rm -e LIQUIBASE_COMMAND_URL=jdbc:postgresql://postgres:5432/inventario_pruebas liquibase
```

### API desplegada en AWS

El deploy de la API (`hack-saltillo-api/infra`) usa tres salidas de [`terraform/`](terraform/README.md):

| Output de este repo | Variable de GitHub de la API |
|---|---|
| `db_address` | `DATABASE_HOST` |
| `db_security_group_id` | `DATABASE_SECURITY_GROUP_ID` (la API agrega ahí su regla de entrada al 5432) |
| `db_master_user_secret_arn` | `DATABASE_PASSWORD_SECRET_ARN` |

La API corre en las subredes públicas de esta VPC y entra a la RDS por Security Group, con
`DATABASE_SSL=true`.

## Estructura

```text
docker-compose.yml            Postgres + Liquibase
liquibase/
  Dockerfile                  Liquibase + driver JDBC de PostgreSQL
  liquibase.properties        Config para usar el CLI de Liquibase sin Docker
  changelog/
    db.changelog-master.yaml  Orden de aplicación
    changes/                  Esquema (001_eventing … 016_sku_matching)
    seed/                     Datos: referencia (siempre), muestra, instancias y catálogo generado (contexto `seed`)
scripts/
  generate_catalog_seed.py    Regenera el catálogo desde events.jsonl del kit
spec/                         Contexto de implementación (arquitectura, modelo, flujo, reglas)
terraform/                    VPC, Security Groups y RDS PostgreSQL en AWS
DECISIONES.md                 Documento de decisiones del reto
AGENTS.md                     Contexto para agentes
```

## Modelo de datos

### Eventos y trazabilidad

| Tabla | Para qué |
|---|---|
| `event_inbox` | Evento crudo con `event_id` único: **idempotencia**, reintentos y **replay**. |
| `outbox_event` | Eventos `stock.*` por publicar en `inventory.events` (patrón outbox). |
| `dead_letter_event` | Eventos que no se pudieron procesar (`inventory.dlq`). |

### Catálogo

`unit`, `part` (con `sku_norm` para relacionar compras e `is_service` para la familia SERVICIO),
`location` (marca `U-100` como recepción), `model` y `model_line` (lista de partes; la vigente queda
`active = true`).

### Taller

`work_order`, `work_order_stage`, `inspection`, `inspection_item` (`condition`: `ok|damaged|missing`;
`action`: `buy|repair`).

### Compras

`supplier`, `purchase_request` (llave `PR-<request_number>`), `purchase_order`, `purchase_line`
(`part_number` → `part_id`, `match_status`) y `unmatched_receipt` (`pending|resolved`).

### Libro mayor

`movement` es **inmutable** (`receipt|issue|transfer_out|transfer_in|adjustment`, cantidad con signo) y
lleva la trazabilidad para los eventos de salida: `work_order_id`, `issued_by`, `purchase_line_id` y
`transfer_group_id` (empareja `transfer_out` con `transfer_in`). `stock_balance` es la **proyección** por
`(part_id, location_id)` con `on_hand`, `reserved` y `available` (columna generada `on_hand - reserved`).

Integridad en la base:

- `on_hand` **siempre** es la suma de `movement` (trigger `trg_movement_apply_balance`): la app **no**
  escribe `on_hand`, solo `reserved`.
- `movement` es **inmutable** (trigger `trg_movement_immutable`): un error se corrige con otro movimiento.
- `reserved` no puede superar `on_hand` (trigger `trg_stock_balance_reserved_guard`).

> El conteo cíclico (`POST /counts`) es la única operación que puede dejar `available` negativo; por eso
> **no** hay `CHECK (available >= 0)`. Esa regla la aplica la app en reservas y salidas (y la guarda de
> `reserved`).

### Compromisos y reabasto

`reservation` (`active|fulfilled|cancelled`), `shortage` (`open|closed`), `work_order_need` (necesidad
vigente por **(orden, `bom_line_id`)**, que se reemplaza), `reorder_policy` (mínimo, máximo, reorden y lead
time) y `reorder_suggestion`.

### Extensiones del agente

| Tabla | Para qué |
|---|---|
| `part_condition` | Catálogo de estados: `new`, `functional`, `defective`, `under_repair`, `scrapped`. |
| `part_instance` | **Instancia**: una unidad física (ej. dos motores = dos filas). |
| `part_instance_repair_tool` | Herramientas necesarias para reparar **esa unidad**. |
| `part_instance_repair_component` | Repuestos que le faltan a **esa unidad** (banda, tornillo). |
| `part_status_history` | Historial de cambios de estado (opcionalmente por instancia). |
| `repair_tool` | Herramientas del taller. |

### Vistas y funciones

`v_part_availability`, `v_part_agent_summary`, `v_part_instance_agent`, `v_open_shortages`,
`v_unmatched_receipts`, `v_reorder_suggestions`, `v_part_ledger` y `v_sku_matches`. La función
`match_part_by_sku(text)` devuelve el `part_id` solo si hay exactamente una coincidencia.

## Consultas del agente

¿Tengo una pieza y en qué estado están sus unidades?

```sql
SELECT part_id, sku, name, on_hand, reserved, available,
       defective_units, under_repair_units, functional_units, total_units
FROM v_part_agent_summary
WHERE sku ILIKE '%7014%' OR name ILIKE '%rodamiento%';
```

¿Qué unidades defectuosas hay y con qué se reparan?

```sql
SELECT instance_id, sku, name, condition_name, tools, missing_components, serial_number
FROM v_part_instance_agent
WHERE condition_code = 'defective'
ORDER BY name, instance_id;
```

La API expone lo mismo en `GET /parts` y `GET /part-instances`.

## Mapeo contrato → tablas

| Evento de entrada | Tablas que alimenta |
|---|---|
| `part.upserted` | `part`, `unit` |
| `location.upserted` | `location` |
| `bom.upserted` | `model`, `model_line` |
| `work_order.opened/.stage_changed/.deleted` | `work_order`, `work_order_stage` |
| `inspection.submitted/.approved/.rejected/.discarded/.voided` | `inspection`, `inspection_item` (+ `work_order_need`, `reservation`, `shortage`) |
| `purchase.item_received` | `purchase_request`, `purchase_line`, `unmatched_receipt` (y `movement` si es `restock`) |

| Evento de salida | Origen |
|---|---|
| `stock.received` | `movement` + `outbox_event` |
| `stock.reserved` / `stock.shortage_detected` / `stock.shortage_resolved` | `reservation` / `shortage` |
| `stock.issued` / `stock.transferred` / `stock.adjusted` | `movement` |
| `stock.reorder_suggested` | `reorder_suggestion` |
| `stock.unmatched_receipt` | `unmatched_receipt` |

## Reglas del reto cubiertas por el esquema

- **Idempotencia**: `event_inbox.event_id` es llave primaria; el consumidor ignora duplicados.
- **Reconstrucción**: `movement` es la fuente de verdad; borrar `stock_balance` y reagregar los movimientos
  reconstruye el saldo.
- **Sin stock negativo** en reservas y salidas: la app valida con `available`; solo el conteo autorizado
  puede quedar negativo.
- **Orden entre tópicos**: `event_inbox` permite reintentar los eventos que llegan antes que sus
  dependencias.

## Despliegue en AWS (Terraform)

[`terraform/`](terraform/README.md) crea una **VPC compartida** (`10.20.0.0/16`, subredes públicas y
privadas) y una **RDS PostgreSQL 16 privada** (`db.t4g.micro`, 20 GB gp3, single-AZ, región `us-east-1` por
defecto). La contraseña maestra la genera y administra RDS en **AWS Secrets Manager**.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

| Output | Para qué |
|---|---|
| `vpc_id`, `public_subnet_ids`, `private_subnet_ids` | Red para desplegar la API en la misma VPC. |
| `app_security_group_id` | SG con acceso a la base, para adjuntar a otras tareas. |
| `db_security_group_id` | SG de la base (lo usa el deploy de la API). |
| `db_address`, `db_port`, `db_name`, `db_master_username` | Datos de conexión. |
| `db_connection_string`, `db_jdbc_url` | Cadena para `psql` y URL para Liquibase (sin contraseña). |
| `db_master_user_secret_arn` | Secreto con la contraseña. |

Terraform no aplica migraciones. Como la RDS no tiene IP pública, Liquibase se corre desde dentro de la VPC o
por un túnel; los detalles están en [`terraform/README.md`](terraform/README.md).
