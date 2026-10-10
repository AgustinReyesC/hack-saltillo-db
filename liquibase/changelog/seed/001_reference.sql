--liquibase formatted sql

--changeset hack-saltillo-db:seed-units
-- Unidades de medida (vienen en `unit` de part.upserted y bom.upserted).
INSERT INTO unit (unit_id, name) VALUES
    (1, 'PIEZA'),
    (2, 'SERVICIO'),
    (3, 'KIT'),
    (4, 'JUEGO'),
    (5, 'LITRO')
ON CONFLICT (unit_id) DO NOTHING;
--rollback DELETE FROM unit WHERE unit_id IN (1,2,3,4,5);

--changeset hack-saltillo-db:seed-part-conditions
-- Catálogo de estados de una pieza (extensión para el agente).
INSERT INTO part_condition (condition_code, name, description, is_available, sort_order) VALUES
    ('new',          'Nuevo',         'Pieza nueva, sin uso.',                 TRUE,  5),
    ('functional',   'Funcional',     'En condiciones de uso.',                TRUE,  10),
    ('defective',    'Defectuoso',    'Requiere reparación antes de usarse.',  FALSE, 20),
    ('under_repair', 'En reparación', 'En banco de trabajo.',                  FALSE, 30),
    ('scrapped',     'Descartado',    'No reparable, dado de baja.',           FALSE, 40)
ON CONFLICT (condition_code) DO NOTHING;
--rollback DELETE FROM part_condition WHERE condition_code IN ('new','functional','defective','under_repair','scrapped');
