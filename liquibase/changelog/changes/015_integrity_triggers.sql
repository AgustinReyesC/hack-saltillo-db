--liquibase formatted sql

--changeset hack-saltillo-db:015-fn-movement-immutable splitStatements:false
-- G5: el libro mayor es inmutable. Un error se corrige con otro movimiento.
CREATE OR REPLACE FUNCTION fn_movement_immutable() RETURNS trigger AS $fn$
BEGIN
    RAISE EXCEPTION 'movement es inmutable: corrige con otro movimiento (intento de %)', TG_OP;
END;
$fn$ LANGUAGE plpgsql;
--rollback DROP FUNCTION IF EXISTS fn_movement_immutable();

--changeset hack-saltillo-db:015-trg-movement-immutable
CREATE TRIGGER trg_movement_immutable
    BEFORE UPDATE OR DELETE ON movement
    FOR EACH ROW EXECUTE FUNCTION fn_movement_immutable();
--rollback DROP TRIGGER IF EXISTS trg_movement_immutable ON movement;

--changeset hack-saltillo-db:015-fn-apply-balance splitStatements:false
-- G5: `stock_balance.on_hand` SIEMPRE es la suma de los movimientos. La app NO debe escribir
-- on_hand; solo administra `reserved`.
CREATE OR REPLACE FUNCTION fn_apply_movement_balance() RETURNS trigger AS $fn$
BEGIN
    INSERT INTO stock_balance (part_id, location_id, on_hand, updated_at)
    VALUES (
        NEW.part_id, NEW.location_id,
        (SELECT COALESCE(SUM(quantity), 0) FROM movement WHERE part_id = NEW.part_id AND location_id = NEW.location_id),
        now())
    ON CONFLICT (part_id, location_id)
    DO UPDATE SET on_hand = (
        SELECT COALESCE(SUM(quantity), 0) FROM movement WHERE part_id = NEW.part_id AND location_id = NEW.location_id
    ), updated_at = now();
    RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;
--rollback DROP FUNCTION IF EXISTS fn_apply_movement_balance();

--changeset hack-saltillo-db:015-trg-apply-balance
CREATE TRIGGER trg_movement_apply_balance
    AFTER INSERT ON movement
    FOR EACH ROW EXECUTE FUNCTION fn_apply_movement_balance();
--rollback DROP TRIGGER IF EXISTS trg_movement_apply_balance ON movement;

--changeset hack-saltillo-db:015-fn-reserved-guard splitStatements:false
-- G6: una reserva no puede superar el on_hand (evita sobre-reservar la última pieza). Un conteo
-- sí puede dejar on_hand < reserved (available negativo), por eso la guarda no aplica cuando
-- reserved no aumenta.
CREATE OR REPLACE FUNCTION fn_stock_balance_reserved_guard() RETURNS trigger AS $fn$
BEGIN
    IF NEW.reserved > NEW.on_hand
       AND ((TG_OP = 'INSERT' AND NEW.reserved > 0) OR (TG_OP = 'UPDATE' AND NEW.reserved > OLD.reserved))
    THEN
        RAISE EXCEPTION 'reserved (%) no puede superar on_hand (%)', NEW.reserved, NEW.on_hand;
    END IF;
    RETURN NEW;
END;
$fn$ LANGUAGE plpgsql;
--rollback DROP FUNCTION IF EXISTS fn_stock_balance_reserved_guard();

--changeset hack-saltillo-db:015-trg-reserved-guard
CREATE TRIGGER trg_stock_balance_reserved_guard
    BEFORE INSERT OR UPDATE ON stock_balance
    FOR EACH ROW EXECUTE FUNCTION fn_stock_balance_reserved_guard();
--rollback DROP TRIGGER IF EXISTS trg_stock_balance_reserved_guard ON stock_balance;
