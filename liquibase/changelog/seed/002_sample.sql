--liquibase formatted sql

--changeset hack-saltillo-db:seed-suppliers context:seed
INSERT INTO supplier (code, name, contact_name, email, phone) VALUES
    ('SUP-001', 'Rodamientos del Norte S.A. de C.V.', 'Laura Méndez',  'ventas@rodnorte.mx',   '844-100-1000'),
    ('SUP-002', 'Herramientas Industriales Saltillo', 'Carlos Ríos',   'contacto@his.mx',      '844-200-2000'),
    ('SUP-003', 'Suministros Técnicos MTY',           'Ana Treviño',   'compras@stmty.mx',     '81-300-3000')
ON CONFLICT (code) DO NOTHING;
--rollback DELETE FROM supplier WHERE code IN ('SUP-001','SUP-002','SUP-003');

--changeset hack-saltillo-db:seed-repair-tools context:seed
INSERT INTO repair_tool (code, name, description) VALUES
    ('HT-001', 'Prensa hidráulica',          'Para desmontar y montar componentes a presión.'),
    ('HT-002', 'Extractor de rodamientos',   'Para retirar pistas y rodamientos.'),
    ('HT-003', 'Micrómetro exterior',        'Medición de precisión del juego radial.'),
    ('HT-004', 'Balanceadora dinámica',      'Balanceo de husillos y rotores.'),
    ('HT-005', 'Horno de inducción',         'Calentamiento controlado para montaje.'),
    ('HT-006', 'Juego de llaves Allen',      'Desarmado general.'),
    ('HT-007', 'Torquímetro',                'Apriete con par controlado.')
ON CONFLICT (code) DO NOTHING;
--rollback DELETE FROM repair_tool WHERE code IN ('HT-001','HT-002','HT-003','HT-004','HT-005','HT-006','HT-007');

--changeset hack-saltillo-db:seed-demo-parts context:seed
-- Productos de demostración con ids altos para no chocar con el catálogo generado.
INSERT INTO part (part_id, sku, name, family, group_name, subgroup, unit_id, active) VALUES
    (900001, '7014 CTA/P4',   'RODAMIENTO DE CONTACTO ANGULAR', 'REFACCIÓN', 'RODAMIENTOS', NULL,       1, TRUE),
    (900002, 'FLECHA-DEMO',   'FLECHA KESSLER DMS080',          'REFACCIÓN', 'FLECHA',      'HSK',      1, TRUE),
    (900003, 'KIT-ORINGS-DEMO','KIT DE ORINGS',                 'REFACCIÓN', 'SELLOS',      'ORINGS',   3, TRUE),
    (900004, 'HUSILLO-DEMO',  'HUSILLO GROB MSP-04',            'REFACCIÓN', 'HUSILLOS',    NULL,       1, TRUE)
ON CONFLICT (part_id) DO NOTHING;
--rollback DELETE FROM part WHERE part_id IN (900001,900002,900003,900004);

--changeset hack-saltillo-db:seed-demo-status context:seed
INSERT INTO part_status (part_id, condition_code, note) VALUES
    (900001, 'defective',    'Pista con picaduras; requiere reemplazo.'),
    (900002, 'functional',   'Listo para usar.'),
    (900003, 'functional',   'Stock disponible.'),
    (900004, 'under_repair', 'En banco de trabajo, balanceo pendiente.')
ON CONFLICT (part_id) DO UPDATE
    SET condition_code = EXCLUDED.condition_code, note = EXCLUDED.note, updated_at = now();
--rollback DELETE FROM part_status WHERE part_id IN (900001,900002,900003,900004);

--changeset hack-saltillo-db:seed-demo-repair context:seed
-- Instrumentos necesarios para reparar cada pieza.
INSERT INTO part_repair_tool (part_id, tool_id, quantity, notes)
SELECT v.part_id, t.tool_id, v.quantity, v.notes
FROM (VALUES
    (900001, 'HT-002', 1, 'Retirar la pista exterior.'),
    (900001, 'HT-003', 1, 'Verificar el juego radial.'),
    (900004, 'HT-001', 1, 'Montaje a presión.'),
    (900004, 'HT-004', 1, 'Balanceo dinámico.'),
    (900004, 'HT-005', 1, 'Calentamiento para montaje.')
) AS v(part_id, tool_code, quantity, notes)
JOIN repair_tool t ON t.code = v.tool_code
ON CONFLICT (part_id, tool_id) DO NOTHING;
--rollback DELETE FROM part_repair_tool WHERE part_id IN (900001,900004);

--changeset hack-saltillo-db:seed-demo-repair-components context:seed
-- Repuestos que consume la reparación.
INSERT INTO part_repair_component (part_id, component_part_id, quantity, notes) VALUES
    (900004, 900001, 2, 'Rodamientos de reemplazo.'),
    (900004, 900003, 1, 'Kit de orings.')
ON CONFLICT (part_id, component_part_id) DO NOTHING;
--rollback DELETE FROM part_repair_component WHERE part_id = 900004;

--changeset hack-saltillo-db:seed-demo-policies context:seed
INSERT INTO reorder_policy (part_id, min_quantity, max_quantity, reorder_quantity, lead_time_days) VALUES
    (900001, 2, 10, 5,  7),
    (900003, 5, 50, 20, 3)
ON CONFLICT (part_id) DO UPDATE
    SET min_quantity = EXCLUDED.min_quantity, max_quantity = EXCLUDED.max_quantity,
        reorder_quantity = EXCLUDED.reorder_quantity, lead_time_days = EXCLUDED.lead_time_days,
        updated_at = now();
--rollback DELETE FROM reorder_policy WHERE part_id IN (900001,900003);
