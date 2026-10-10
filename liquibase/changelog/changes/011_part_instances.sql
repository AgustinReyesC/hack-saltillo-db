--liquibase formatted sql

--changeset hack-saltillo-db:011-part-instances
-- Modelo de INSTANCIAS: cada unidad física es una fila independiente (buena o defectuosa),
-- con su propio estado y su recetario de reparación (herramientas y repuestos). Reemplaza el
-- modelo por tipo de pieza (part_status / part_repair_tool / part_repair_component).
--
-- Ejemplo: dos motores iguales, a uno le falta una banda y al otro un tornillo → dos filas.

-- La vista anterior depende de las tablas que se eliminan; se recrea más abajo.
DROP VIEW IF EXISTS v_part_agent_summary;

-- 1) Una fila por unidad física.
CREATE TABLE part_instance (
    instance_id        BIGSERIAL   PRIMARY KEY,
    part_id            INTEGER     NOT NULL REFERENCES part(part_id),          -- tipo de producto
    condition_code     TEXT        NOT NULL REFERENCES part_condition(condition_code),
    location_id        INTEGER     REFERENCES location(location_id),
    work_order_id      INTEGER     REFERENCES work_order(work_order_id),
    inspection_item_id INTEGER     REFERENCES inspection_item(inspection_item_id),
    serial_number      TEXT,
    note               TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_part_instance_part      ON part_instance (part_id);
CREATE INDEX idx_part_instance_condition ON part_instance (condition_code);
CREATE INDEX idx_part_instance_location  ON part_instance (location_id);
CREATE INDEX idx_part_instance_wo        ON part_instance (work_order_id);

-- 2) Herramientas necesarias para reparar esa unidad.
CREATE TABLE part_instance_repair_tool (
    instance_id BIGINT  NOT NULL REFERENCES part_instance(instance_id) ON DELETE CASCADE,
    tool_id     INTEGER NOT NULL REFERENCES repair_tool(tool_id) ON DELETE CASCADE,
    quantity    INTEGER NOT NULL DEFAULT 1,
    notes       TEXT,
    PRIMARY KEY (instance_id, tool_id)
);

-- 3) Repuestos/componentes que le faltan a esa unidad (banda, tornillo, …).
CREATE TABLE part_instance_repair_component (
    instance_id       BIGINT  NOT NULL REFERENCES part_instance(instance_id) ON DELETE CASCADE,
    component_part_id INTEGER NOT NULL REFERENCES part(part_id) ON DELETE CASCADE,
    quantity          INTEGER NOT NULL DEFAULT 1,
    notes             TEXT,
    PRIMARY KEY (instance_id, component_part_id)
);

-- El historial puede referir una instancia concreta (opcional).
ALTER TABLE part_status_history
    ADD COLUMN instance_id BIGINT REFERENCES part_instance(instance_id) ON DELETE SET NULL;
COMMENT ON COLUMN part_status_history.instance_id IS 'Unidad física cuyo estado cambió; NULL si es a nivel tipo.';

-- 4) Migrar el estado por pieza a instancias (una unidad por cada fila previa).
INSERT INTO part_instance (part_id, condition_code, work_order_id, note)
SELECT part_id, condition_code, work_order_id, note FROM part_status;

-- Copiar el recetario por pieza a cada una de sus instancias.
INSERT INTO part_instance_repair_tool (instance_id, tool_id, quantity, notes)
SELECT i.instance_id, prt.tool_id, prt.quantity, prt.notes
FROM part_instance i
JOIN part_repair_tool prt ON prt.part_id = i.part_id
ON CONFLICT (instance_id, tool_id) DO NOTHING;

INSERT INTO part_instance_repair_component (instance_id, component_part_id, quantity, notes)
SELECT i.instance_id, prc.component_part_id, prc.quantity, prc.notes
FROM part_instance i
JOIN part_repair_component prc ON prc.part_id = i.part_id
ON CONFLICT (instance_id, component_part_id) DO NOTHING;

-- 5) Retirar el modelo por tipo.
DROP TABLE part_repair_component;
DROP TABLE part_repair_tool;
DROP TABLE part_status;

-- 6) Vistas nuevas.
-- Resumen por tipo: cuántas unidades hay en cada estado.
CREATE VIEW v_part_agent_summary AS
SELECT p.part_id,
       p.sku,
       p.name,
       p.family,
       p.active,
       COALESCE(a.on_hand, 0)   AS on_hand,
       COALESCE(a.reserved, 0)  AS reserved,
       COALESCE(a.available, 0) AS available,
       COUNT(i.instance_id) FILTER (WHERE i.condition_code = 'defective')            AS defective_units,
       COUNT(i.instance_id) FILTER (WHERE i.condition_code = 'under_repair')         AS under_repair_units,
       COUNT(i.instance_id) FILTER (WHERE i.condition_code IN ('functional','new'))  AS functional_units,
       (SELECT COUNT(*) FROM part_instance i2 WHERE i2.part_id = p.part_id)          AS total_units,
       (SELECT COUNT(*) FROM shortage s WHERE s.part_id = p.part_id AND s.status = 'open') AS open_shortages
FROM part p
LEFT JOIN v_part_availability a ON a.part_id = p.part_id
LEFT JOIN part_instance i       ON i.part_id = p.part_id
GROUP BY p.part_id, p.sku, p.name, p.family, p.active, a.on_hand, a.reserved, a.available;

-- Detalle por unidad: estado + herramientas (`tools`) + repuestos faltantes.
CREATE VIEW v_part_instance_agent AS
SELECT i.instance_id,
       i.part_id,
       p.sku,
       p.name,
       i.condition_code,
       pc.name AS condition_name,
       pc.is_available,
       i.location_id,
       i.work_order_id,
       i.serial_number,
       i.note,
       COALESCE((SELECT ARRAY_AGG(t.name ORDER BY t.name)
                   FROM part_instance_repair_tool rt
                   JOIN repair_tool t ON t.tool_id = rt.tool_id
                  WHERE rt.instance_id = i.instance_id), '{}') AS tools,
       COALESCE((SELECT ARRAY_AGG(cp.name ORDER BY cp.name)
                   FROM part_instance_repair_component c
                   JOIN part cp ON cp.part_id = c.component_part_id
                  WHERE c.instance_id = i.instance_id), '{}') AS missing_components
FROM part_instance i
JOIN part p             ON p.part_id = i.part_id
JOIN part_condition pc  ON pc.condition_code = i.condition_code;

--rollback DROP VIEW IF EXISTS v_part_instance_agent;
--rollback DROP VIEW IF EXISTS v_part_agent_summary;
--rollback DROP TABLE IF EXISTS part_instance_repair_component;
--rollback DROP TABLE IF EXISTS part_instance_repair_tool;
--rollback DROP TABLE IF EXISTS part_instance;
--rollback ALTER TABLE part_status_history DROP COLUMN IF EXISTS instance_id;
--rollback CREATE TABLE part_status (part_id INTEGER PRIMARY KEY REFERENCES part(part_id) ON DELETE CASCADE, condition_code TEXT NOT NULL REFERENCES part_condition(condition_code), work_order_id INTEGER REFERENCES work_order(work_order_id), note TEXT, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
--rollback CREATE TABLE part_repair_tool (part_id INTEGER NOT NULL REFERENCES part(part_id) ON DELETE CASCADE, tool_id INTEGER NOT NULL REFERENCES repair_tool(tool_id) ON DELETE CASCADE, quantity INTEGER NOT NULL DEFAULT 1, notes TEXT, PRIMARY KEY (part_id, tool_id));
--rollback CREATE TABLE part_repair_component (part_id INTEGER NOT NULL REFERENCES part(part_id) ON DELETE CASCADE, component_part_id INTEGER NOT NULL REFERENCES part(part_id) ON DELETE CASCADE, quantity INTEGER NOT NULL DEFAULT 1, notes TEXT, PRIMARY KEY (part_id, component_part_id), CONSTRAINT no_self_component CHECK (part_id <> component_part_id));
--rollback CREATE VIEW v_part_agent_summary AS SELECT p.part_id, p.sku, p.name, p.family, p.active, ps.condition_code, pc.name AS condition_name, COALESCE(pc.is_available, FALSE) AS condition_is_available, COALESCE(a.on_hand,0) AS on_hand, COALESCE(a.reserved,0) AS reserved, COALESCE(a.available,0) AS available, (SELECT COUNT(*) FROM part_repair_tool t WHERE t.part_id=p.part_id) AS repair_tools_count, (SELECT COUNT(*) FROM part_repair_component c WHERE c.part_id=p.part_id) AS repair_components_count, (SELECT COUNT(*) FROM shortage s WHERE s.part_id=p.part_id AND s.status='open') AS open_shortages FROM part p LEFT JOIN part_status ps ON ps.part_id=p.part_id LEFT JOIN part_condition pc ON pc.condition_code=ps.condition_code LEFT JOIN v_part_availability a ON a.part_id=p.part_id;
