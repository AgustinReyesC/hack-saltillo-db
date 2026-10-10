--liquibase formatted sql

--changeset hack-saltillo-db:014-domain-checks
-- G4: valores permitidos según el contrato (refuerzo a nivel de BD). NULL se permite donde el
-- contrato lo permite.

ALTER TABLE work_order ADD CONSTRAINT ck_work_order_department
    CHECK (department IS NULL OR department IN ('spindles','motors','electronics','torque_center'));
ALTER TABLE work_order ADD CONSTRAINT ck_work_order_stage
    CHECK (stage IN ('awaiting_quick_inspection','quick_inspection','awaiting_full_inspection','full_inspection','cleaning','assembly','run_in','final_assembly','final_release'));

ALTER TABLE work_order_stage ADD CONSTRAINT ck_wo_stage_to
    CHECK (to_stage IN ('awaiting_quick_inspection','quick_inspection','awaiting_full_inspection','full_inspection','cleaning','assembly','run_in','final_assembly','final_release'));
ALTER TABLE work_order_stage ADD CONSTRAINT ck_wo_stage_from
    CHECK (from_stage IS NULL OR from_stage IN ('awaiting_quick_inspection','quick_inspection','awaiting_full_inspection','full_inspection','cleaning','assembly','run_in','final_assembly','final_release'));

ALTER TABLE inspection ADD CONSTRAINT ck_inspection_kind CHECK (kind IN ('quick','full'));
ALTER TABLE inspection ADD CONSTRAINT ck_inspection_status
    CHECK (status IN ('submitted','approved','rejected','discarded','voided'));

ALTER TABLE inspection_item ADD CONSTRAINT ck_inspection_item_condition
    CHECK (condition IN ('ok','damaged','missing'));
ALTER TABLE inspection_item ADD CONSTRAINT ck_inspection_item_action
    CHECK (action IS NULL OR action IN ('buy','repair'));

ALTER TABLE purchase_line ADD CONSTRAINT ck_purchase_line_purpose CHECK (purpose IN ('restock','customer_order'));
ALTER TABLE purchase_line ADD CONSTRAINT ck_purchase_line_match
    CHECK (match_status IN ('pending','matched','unmatched','resolved'));

ALTER TABLE unmatched_receipt ADD CONSTRAINT ck_unmatched_receipt_status CHECK (status IN ('pending','resolved'));

ALTER TABLE movement ADD CONSTRAINT ck_movement_type
    CHECK (type IN ('receipt','issue','transfer_out','transfer_in','adjustment'));

ALTER TABLE reservation ADD CONSTRAINT ck_reservation_status CHECK (status IN ('active','fulfilled','cancelled'));
ALTER TABLE shortage ADD CONSTRAINT ck_shortage_status CHECK (status IN ('open','closed'));

ALTER TABLE event_inbox ADD CONSTRAINT ck_event_inbox_status CHECK (status IN ('received','processed','failed'));

--rollback ALTER TABLE event_inbox DROP CONSTRAINT ck_event_inbox_status;
--rollback ALTER TABLE shortage DROP CONSTRAINT ck_shortage_status;
--rollback ALTER TABLE reservation DROP CONSTRAINT ck_reservation_status;
--rollback ALTER TABLE movement DROP CONSTRAINT ck_movement_type;
--rollback ALTER TABLE unmatched_receipt DROP CONSTRAINT ck_unmatched_receipt_status;
--rollback ALTER TABLE purchase_line DROP CONSTRAINT ck_purchase_line_match;
--rollback ALTER TABLE purchase_line DROP CONSTRAINT ck_purchase_line_purpose;
--rollback ALTER TABLE inspection_item DROP CONSTRAINT ck_inspection_item_action;
--rollback ALTER TABLE inspection_item DROP CONSTRAINT ck_inspection_item_condition;
--rollback ALTER TABLE inspection DROP CONSTRAINT ck_inspection_status;
--rollback ALTER TABLE inspection DROP CONSTRAINT ck_inspection_kind;
--rollback ALTER TABLE work_order_stage DROP CONSTRAINT ck_wo_stage_from;
--rollback ALTER TABLE work_order_stage DROP CONSTRAINT ck_wo_stage_to;
--rollback ALTER TABLE work_order DROP CONSTRAINT ck_work_order_stage;
--rollback ALTER TABLE work_order DROP CONSTRAINT ck_work_order_department;
