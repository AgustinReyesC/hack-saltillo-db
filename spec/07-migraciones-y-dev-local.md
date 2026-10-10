# 07 — Migraciones y desarrollo local

## Levantar el entorno

```bash
copy .env.example .env      # PowerShell;  cp en bash
docker compose up -d        # Postgres 16 + Liquibase (esquema + seeds)
docker compose logs -f liquibase
docker compose exec postgres psql -U inventario -d inventario
```

Conexión por defecto: `localhost:5432`, DB/usuario/clave `inventario`.

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
python scripts/generate_catalog_seed.py
python scripts/generate_catalog_seed.py --events "..\..\hackaton-inventarios\data\events.jsonl"
```

El script deduplica `part.upserted`, `location.upserted` y `bom.upserted` (se queda con la
última versión de cada entidad) y escribe INSERT con `ON CONFLICT` (idempotente).

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
