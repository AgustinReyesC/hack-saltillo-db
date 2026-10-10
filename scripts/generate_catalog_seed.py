"""Genera un changelog Liquibase con el catálogo real del taller.

Lee `data/events.jsonl` del kit `hackaton-inventarios` (o la ruta que se indique) y
escribe `liquibase/changelog/seed/099_catalog_generated.sql` con:

  * unit          (unidades de medida referenciadas)
  * part          (lista de productos registrados; `active` e `is_service` incluidos)
  * location      (ubicaciones; marca U-100 como recepción)
  * model         (modelos)
  * model_line    (lista de partes vigente de cada modelo)

Los datos son idempotentes: cada INSERT usa ON CONFLICT para poder reaplicar.

Uso:
    python scripts/generate_catalog_seed.py
    python scripts/generate_catalog_seed.py --events "..\\..\\hackaton-inventarios\\data\\events.jsonl"
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_EVENTS = REPO.parent / "hackaton-inventarios" / "data" / "events.jsonl"
DEFAULT_OUT = REPO / "liquibase" / "changelog" / "seed" / "099_catalog_generated.sql"


def q(value) -> str:
    """Literal SQL: None -> NULL, bool -> TRUE/FALSE, resto citado y escapado."""
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, (int, float)):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def read_events(path: Path) -> dict:
    parts: dict[int, dict] = {}
    locations: dict[int, dict] = {}
    models: dict[int, dict] = {}
    lines_by_model: dict[int, list[dict]] = {}
    line_model: dict[int, int] = {}
    units: dict[int, str] = {}

    with path.open(encoding="utf-8") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            event = json.loads(raw).get("event", {})
            etype = event.get("event_type")
            data = event.get("data", {})

            if etype == "part.upserted":
                parts[data["part_id"]] = data
                unit = data.get("unit")
                if unit:
                    units[unit["id"]] = unit["name"]
            elif etype == "location.upserted":
                locations[data["location_id"]] = data
            elif etype == "bom.upserted":
                models[data["model_id"]] = data
                snapshot = []
                for line in data.get("lines", []):
                    line_model[line["bom_line_id"]] = data["model_id"]
                    snapshot.append(line)
                    unit = line.get("unit")
                    if unit:
                        units[unit["id"]] = unit["name"]
                lines_by_model[data["model_id"]] = snapshot

    return {
        "parts": parts,
        "locations": locations,
        "models": models,
        "lines_by_model": lines_by_model,
        "line_model": line_model,
        "units": units,
    }


def changeset(name: str, body: str) -> str:
    return f"--changeset hack-saltillo-db:{name} context:seed\n{body}\n"


def build_sql(data: dict) -> str:
    parts: dict[int, dict] = data["parts"]
    locations: dict[int, dict] = data["locations"]
    models: dict[int, dict] = data["models"]
    lines_by_model: dict[int, list[dict]] = data["lines_by_model"]
    units: dict[int, str] = data["units"]

    known_parts = set(parts)

    out = [
        "--liquibase formatted sql",
        "-- GENERADO AUTOMÁTICAMENTE por scripts/generate_catalog_seed.py",
        "-- Fuente: hackaton-inventarios/data/events.jsonl  ·  NO EDITAR A MANO",
        "",
    ]

    # Unidades
    if units:
        values = ",\n    ".join(f"({uid}, {q(name)})" for uid, name in sorted(units.items()))
        out.append(changeset(
            "seed-catalog-units",
            "INSERT INTO unit (unit_id, name) VALUES\n    " + values +
            "\nON CONFLICT (unit_id) DO NOTHING;",
        ))

    # Piezas / productos
    if parts:
        rows = []
        for pid, p in sorted(parts.items()):
            unit = p.get("unit") or {}
            is_service = (p.get("family") or "").strip().upper() == "SERVICIO"
            rows.append(
                "    ("
                + ", ".join(q(x) for x in (
                    pid, p.get("sku"), p.get("name"), p.get("family"), p.get("group"),
                    p.get("subgroup"), unit.get("id"), p.get("image_url"), p.get("active", True),
                    is_service,
                ))
                + ")"
            )
        out.append(changeset(
            "seed-catalog-parts",
            "INSERT INTO part (part_id, sku, name, family, group_name, subgroup, unit_id, "
            "image_url, active, is_service) VALUES\n" + ",\n".join(rows) + "\n"
            "ON CONFLICT (part_id) DO UPDATE SET\n"
            "    sku = EXCLUDED.sku, name = EXCLUDED.name, family = EXCLUDED.family,\n"
            "    group_name = EXCLUDED.group_name, subgroup = EXCLUDED.subgroup,\n"
            "    unit_id = EXCLUDED.unit_id, image_url = EXCLUDED.image_url,\n"
            "    active = EXCLUDED.active, is_service = EXCLUDED.is_service, updated_at = now();",
        ))

    # Ubicaciones
    if locations:
        rows = []
        for lid, loc in sorted(locations.items()):
            rows.append("    (" + ", ".join(q(x) for x in (
                lid, loc.get("code"), loc.get("name"), loc.get("is_workbench", False),
                loc.get("code") == "U-100", loc.get("active", True),
            )) + ")")
        out.append(changeset(
            "seed-catalog-locations",
            "INSERT INTO location (location_id, code, name, is_workbench, is_receiving, active) "
            "VALUES\n" + ",\n".join(rows) + "\n"
            "ON CONFLICT (location_id) DO UPDATE SET\n"
            "    code = EXCLUDED.code, name = EXCLUDED.name,\n"
            "    is_workbench = EXCLUDED.is_workbench, is_receiving = EXCLUDED.is_receiving,\n"
            "    active = EXCLUDED.active, updated_at = now();",
        ))

    # Modelos
    if models:
        rows = ["    (" + ", ".join(q(x) for x in (
            mid, m.get("model_name"), m.get("brand"))) + ")"
            for mid, m in sorted(models.items())]
        out.append(changeset(
            "seed-catalog-models",
            "INSERT INTO model (model_id, model_name, brand) VALUES\n" + ",\n".join(rows) + "\n"
            "ON CONFLICT (model_id) DO UPDATE SET\n"
            "    model_name = EXCLUDED.model_name, brand = EXCLUDED.brand, updated_at = now();",
        ))

    # Líneas de BOM (solo la lista vigente de cada modelo; el resto queda inactivo)
    latest_ids = {ln["bom_line_id"] for lines in lines_by_model.values() for ln in lines}
    all_lines = {}
    for model_id, lines in lines_by_model.items():
        for ln in lines:
            all_lines[ln["bom_line_id"]] = (model_id, ln)
    if all_lines:
        rows = []
        for line_id, (model_id, ln) in sorted(all_lines.items()):
            part_id = ln.get("part_id")
            if part_id not in known_parts:
                part_id = None
            unit = ln.get("unit") or {}
            rows.append("    (" + ", ".join(q(x) for x in (
                line_id, model_id, part_id, ln.get("name"), ln.get("group_name"),
                unit.get("id"), ln.get("qty_per_unit"), ln.get("sort_order", 0),
                line_id in latest_ids,
            )) + ")")
        out.append(changeset(
            "seed-catalog-model-lines",
            "INSERT INTO model_line (bom_line_id, model_id, part_id, name, group_name, unit_id, "
            "qty_per_unit, sort_order, active) VALUES\n" + ",\n".join(rows) + "\n"
            "ON CONFLICT (bom_line_id) DO UPDATE SET\n"
            "    model_id = EXCLUDED.model_id, part_id = EXCLUDED.part_id, name = EXCLUDED.name,\n"
            "    group_name = EXCLUDED.group_name, unit_id = EXCLUDED.unit_id,\n"
            "    qty_per_unit = EXCLUDED.qty_per_unit, sort_order = EXCLUDED.sort_order,\n"
            "    active = EXCLUDED.active, updated_at = now();",
        ))

    out.append("")
    return "\n".join(out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--events", type=Path, default=DEFAULT_EVENTS, help="ruta a events.jsonl")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="ruta del .sql a generar")
    args = parser.parse_args()

    if not args.events.exists():
        raise SystemExit(f"no se encontró {args.events}")

    data = read_events(args.events)
    sql = build_sql(data)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(sql, encoding="utf-8")
    print(
        f"generado {args.out} · "
        f"{len(data['parts'])} piezas, {len(data['locations'])} ubicaciones, "
        f"{len(data['models'])} modelos, "
        f"{sum(len(v) for v in data['lines_by_model'].values())} líneas de BOM"
    )


if __name__ == "__main__":
    main()
