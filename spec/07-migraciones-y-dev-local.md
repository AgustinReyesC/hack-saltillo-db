# 07 — Migraciones y desarrollo local

## Levantar el entorno

```bash
cp .env.example .env
docker compose up -d        # Postgres 16 + Liquibase (esquema + seeds)
docker compose logs -f liquibase
docker compose exec postgres psql -U inventario -d inventario
```

Conexión por defecto: `localhost:5432`, DB/usuario/clave `inventario`.

### WSL2 con Docker Engine

Corre los comandos desde WSL, usando Docker Engine y Docker Compose v2 disponibles en esa
distribución. Se recomienda guardar `hack-saltillo-db` y el kit `hackaton-inventarios` en el
sistema de archivos Linux de WSL, como repositorios hermanos bajo `~/src/`:

```bash
cd ~/src/hack-saltillo-db
docker info
docker compose version
cp .env.example .env
python3 scripts/generate_catalog_seed.py --events ../hackaton-inventarios/data/events.jsonl
docker compose up --build -d
docker compose logs --follow liquibase
```

El generador Python no requiere paquetes externos y **no escribe directamente en PostgreSQL**:
lee `events.jsonl` y produce `liquibase/changelog/seed/099_catalog_generated.sql`. Al iniciar
con Liquibase, ese SQL se aplica junto con el esquema y los otros seeds. Sin el kit
`hackaton-inventarios`, se puede omitir la generación y usar el SQL ya incluido.

Cuando Liquibase termine, verifica el resultado:

```bash
docker compose exec postgres psql -U inventario -d inventario -c "SELECT count(*) FROM part;"
docker compose exec postgres psql -U inventario -d inventario -c "SELECT count(*) FROM location;"
```

Para volver a empezar de cero (borra el volumen):

```bash
docker compose down -v && docker compose up -d
```

## Contextos de Liquibase

- `LIQUIBASE_CONTEXTS=seed` (por defecto): aplica esquema **y** datos de ejemplo.
- `LIQUIBASE_CONTEXTS=` (vacío): solo esquema + datos de referencia (unidades y estados).

Los datos de referencia (`seed/001_reference.sql`) no llevan contexto y siempre se aplican;
la muestra y el catálogo generado llevan `context:seed`.

## Cómo crear una migración

1. Crea `liquibase/changelog/changes/NNN_descripcion.sql` con el header:

   ```sql
   --liquibase formatted sql

   --changeset hack-saltillo-db:NNN-descripcion
   CREATE TABLE ...;
   --rollback DROP TABLE ...;
   ```

2. Añádela al final de `liquibase/changelog/db.changelog-master.yaml` con
   `relativeToChangelogFile: true`.
3. Nunca edites un changeset ya aplicado: Liquibase valida el checksum. Para cambiar algo ya
   aplicado, crea un changeset nuevo.
4. Cada changeset **debe** incluir su `--rollback`.
5. Usa nombres de tablas/columnas en inglés y sigue las convenciones de `AGENTS.md`.

## Datos semilla

- `seed/001_reference.sql`: unidades y catálogo de estados (siempre).
- `seed/002_sample.sql`: proveedores, herramientas, piezas de demostración y su recetario
  (contexto `seed`).
- `seed/099_catalog_generated.sql`: **generado** desde el kit. No editar a mano.

### Regenerar el catálogo real

`099_catalog_generated.sql` se genera desde
`../hackaton-inventarios/data/events.jsonl` (256 productos, 67 ubicaciones, 5 modelos,
163 líneas de BOM):

```bash
python3 scripts/generate_catalog_seed.py
python3 scripts/generate_catalog_seed.py --events ../hackaton-inventarios/data/events.jsonl
```

El script deduplica `part.upserted`, `location.upserted` y `bom.upserted` (se queda con la
última versión de cada entidad) y escribe INSERT con `ON CONFLICT` (idempotente).
Ejecuta el generador **antes** del primer `docker compose up`: el archivo generado forma parte
del changelog y Liquibase valida su checksum. No lo regeneres con contenido distinto después de
que esos changesets hayan sido aplicados a esa base; agrega una migración nueva para cambios
posteriores.

## Validar sin Docker

Puedes validar la sintaxis de los `.sql` con un parser de PostgreSQL:

```bash
python -c "import glob; from pglast import parse_sql; [parse_sql(open(f,encoding='utf-8').read()) for f in glob.glob('liquibase/changelog/**/*.sql', recursive=True)]"
```

(Requiere `pip install pglast`.) No sustituye un arranque real con Liquibase.

## Uso del CLI de Liquibase sin Docker

Desde la raíz del repositorio:

```bash
liquibase --defaults-file=liquibase/liquibase.properties update
```

## Estructura de carpetas

```
docker-compose.yml
liquibase/
  Dockerfile                  Liquibase + driver JDBC PostgreSQL
  liquibase.properties
  changelog/
    db.changelog-master.yaml
    changes/                  Esquema
    seed/                     Datos
scripts/
  generate_catalog_seed.py
spec/                         Esta documentación
```
