--liquibase formatted sql

--changeset hack-saltillo-db:016-sku-matches-view
-- G7: relación part_number ↔ sku. Agrupa piezas por sku normalizado (sin mayúsculas ni
-- espacios extremos). `match_count > 1` = sku ambiguo (dos piezas distintas con el mismo sku).
CREATE VIEW v_sku_matches AS
SELECT sku_norm,
       array_agg(part_id ORDER BY part_id) AS part_ids,
       count(*)                            AS match_count
FROM part
WHERE sku_norm IS NOT NULL
GROUP BY sku_norm;
--rollback DROP VIEW IF EXISTS v_sku_matches;

--changeset hack-saltillo-db:016-match-part-by-sku splitStatements:false
-- Devuelve el part_id si el número de parte coincide EXACTAMENTE con una pieza.
-- NULL = no coincide o coincide con más de una (revisar `v_sku_matches`).
CREATE FUNCTION match_part_by_sku(p_number TEXT) RETURNS INTEGER AS $fn$
    SELECT CASE WHEN count(*) = 1 THEN min(part_id) ELSE NULL END
    FROM part
    WHERE sku_norm = lower(btrim(p_number));
$fn$ LANGUAGE sql STABLE;
--rollback DROP FUNCTION IF EXISTS match_part_by_sku(text);
