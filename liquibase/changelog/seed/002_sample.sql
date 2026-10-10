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
-- Las instancias físicas (unidades) y su recetario se cargan en 003_part_instances.sql.
INSERT INTO part (part_id, sku, name, family, group_name, subgroup, unit_id, active) VALUES
    (900001, '7014 CTA/P4',    'RODAMIENTO DE CONTACTO ANGULAR', 'REFACCIÓN', 'RODAMIENTOS', NULL,     1, TRUE),
    (900002, 'FLECHA-DEMO',    'FLECHA KESSLER DMS080',          'REFACCIÓN', 'FLECHA',      'HSK',    1, TRUE),
    (900003, 'KIT-ORINGS-DEMO','KIT DE ORINGS',                 'REFACCIÓN', 'SELLOS',      'ORINGS', 3, TRUE),
    (900004, 'HUSILLO-DEMO',   'HUSILLO GROB MSP-04',            'REFACCIÓN', 'HUSILLOS',    NULL,     1, TRUE)
ON CONFLICT (part_id) DO NOTHING;
--rollback DELETE FROM part WHERE part_id IN (900001,900002,900003,900004);

--changeset hack-saltillo-db:seed-demo-policies context:seed
INSERT INTO reorder_policy (part_id, min_quantity, max_quantity, reorder_quantity, lead_time_days) VALUES
    (900001, 2, 10, 5,  7),
    (900003, 5, 50, 20, 3)
ON CONFLICT (part_id) DO UPDATE
    SET min_quantity = EXCLUDED.min_quantity, max_quantity = EXCLUDED.max_quantity,
        reorder_quantity = EXCLUDED.reorder_quantity, lead_time_days = EXCLUDED.lead_time_days,
        updated_at = now();
--rollback DELETE FROM reorder_policy WHERE part_id IN (900001,900003);
