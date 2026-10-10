--liquibase formatted sql

--changeset hack-saltillo-db:seed-instance-parts context:seed
-- Piezas para el ejemplo de instancias: dos motores con daños distintos.
INSERT INTO part (part_id, sku, name, family, group_name, subgroup, unit_id, active) VALUES
    (900005, 'MOTOR-DEMO',   'MOTOR ELÉCTRICO DEMO', 'REFACCIÓN', 'MOTORES',     NULL, 1, TRUE),
    (900006, 'BANDA-DEMO',   'BANDA DEMO',           'REFACCIÓN', 'BANDAS',      NULL, 1, TRUE),
    (900007, 'TORNILLO-DEMO','TORNILLO DEMO',         'REFACCIÓN', 'TORNILLERIA', NULL, 1, TRUE)
ON CONFLICT (part_id) DO NOTHING;
--rollback DELETE FROM part WHERE part_id IN (900005,900006,900007);

--changeset hack-saltillo-db:seed-instances context:seed
-- Cada fila es una unidad física. Los dos motores (part 900005) son instancias independientes:
-- al 900001 le falta una banda, al 900002 un tornillo.
INSERT INTO part_instance (instance_id, part_id, condition_code, serial_number, note) VALUES
    (900001, 900005, 'defective',    'MOTOR-001',  'Le falta la banda.'),
    (900002, 900005, 'defective',    'MOTOR-002',  'Le falta un tornillo.'),
    (900003, 900002, 'functional',   'FLECHA-001', 'Unidad buena de ejemplo.'),
    (900004, 900001, 'defective',    'ROD-001',    'Pista con picaduras; requiere reemplazo.'),
    (900005, 900004, 'under_repair', 'HUS-001',    'En banco de trabajo, balanceo pendiente.')
ON CONFLICT (instance_id) DO NOTHING;
--rollback DELETE FROM part_instance WHERE instance_id BETWEEN 900001 AND 900005;

--changeset hack-saltillo-db:seed-instance-repair-tools context:seed
-- Herramientas necesarias por unidad (el "campo" que pide el feedback vive en la vista).
INSERT INTO part_instance_repair_tool (instance_id, tool_id, quantity, notes)
SELECT v.instance_id, t.tool_id, v.quantity, v.notes
FROM (VALUES
    (900001, 'HT-006', 1, 'Abrir la carcasa para reponer la banda.'),
    (900001, 'HT-001', 1, 'Montar la banda.'),
    (900002, 'HT-006', 1, 'Apretar el tornillo de sujeción.'),
    (900002, 'HT-007', 1, 'Par de apriete controlado.'),
    (900004, 'HT-002', 1, 'Retirar la pista exterior.'),
    (900004, 'HT-003', 1, 'Verificar el juego radial.'),
    (900005, 'HT-001', 1, 'Montaje a presión.'),
    (900005, 'HT-004', 1, 'Balanceo dinámico.'),
    (900005, 'HT-005', 1, 'Calentamiento para montaje.')
) AS v(instance_id, tool_code, quantity, notes)
JOIN repair_tool t ON t.code = v.tool_code
ON CONFLICT (instance_id, tool_id) DO NOTHING;
--rollback DELETE FROM part_instance_repair_tool WHERE instance_id BETWEEN 900001 AND 900005;

--changeset hack-saltillo-db:seed-instance-repair-components context:seed
-- Repuestos que le faltan a cada unidad (banda / tornillo / rodamiento).
INSERT INTO part_instance_repair_component (instance_id, component_part_id, quantity, notes) VALUES
    (900001, 900006, 1, 'Banda faltante.'),
    (900002, 900007, 1, 'Tornillo faltante.'),
    (900004, 900003, 1, 'Kit de orings de reemplazo.'),
    (900005, 900001, 2, 'Rodamientos de reemplazo.')
ON CONFLICT (instance_id, component_part_id) DO NOTHING;
--rollback DELETE FROM part_instance_repair_component WHERE instance_id BETWEEN 900001 AND 900005;
