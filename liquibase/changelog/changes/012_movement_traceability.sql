--liquibase formatted sql

--changeset hack-saltillo-db:012-movement-traceability
-- G1/G2: columnas para derivar los eventos de salida directamente del libro mayor.
ALTER TABLE movement
    ADD COLUMN work_order_id     INTEGER REFERENCES work_order(work_order_id),
    ADD COLUMN issued_by         TEXT,
    ADD COLUMN purchase_line_id  INTEGER REFERENCES purchase_line(line_id),
    ADD COLUMN transfer_group_id UUID;

COMMENT ON COLUMN movement.work_order_id     IS 'Orden asociada (issue) para /work-orders/{code}/materials y stock.issued.';
COMMENT ON COLUMN movement.issued_by         IS 'Quién retiró la pieza (stock.issued); acepta número o texto.';
COMMENT ON COLUMN movement.purchase_line_id  IS 'Línea de compra origen de la entrada (stock.received).';
COMMENT ON COLUMN movement.transfer_group_id IS 'Agrupa transfer_out + transfer_in de una misma transferencia (stock.transferred).';

CREATE INDEX idx_movement_work_order    ON movement (work_order_id);
CREATE INDEX idx_movement_purchase_line ON movement (purchase_line_id);
CREATE INDEX idx_movement_transfer_group ON movement (transfer_group_id);
--rollback DROP INDEX IF EXISTS idx_movement_transfer_group;
--rollback DROP INDEX IF EXISTS idx_movement_purchase_line;
--rollback DROP INDEX IF EXISTS idx_movement_work_order;
--rollback ALTER TABLE movement DROP COLUMN transfer_group_id;
--rollback ALTER TABLE movement DROP COLUMN purchase_line_id;
--rollback ALTER TABLE movement DROP COLUMN issued_by;
--rollback ALTER TABLE movement DROP COLUMN work_order_id;
