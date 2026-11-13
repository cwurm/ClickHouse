-- The implicit constraints reject invalid values of the `is_deleted` column of `ReplacingMergeTree` and of the
-- `sign` column of `CollapsingMergeTree`, with or without the insert-time merge (`optimize_on_insert`).

DROP TABLE IF EXISTS t_replacing_is_deleted;
DROP TABLE IF EXISTS t_collapsing;

CREATE TABLE t_replacing_is_deleted (key UInt32, ver UInt32, is_deleted UInt8)
ENGINE = ReplacingMergeTree(ver, is_deleted) ORDER BY key;

INSERT INTO t_replacing_is_deleted SETTINGS optimize_on_insert = 0 VALUES (1, 1, 0), (2, 1, 1);
INSERT INTO t_replacing_is_deleted SETTINGS optimize_on_insert = 0 VALUES (3, 1, 2); -- { serverError VIOLATED_CONSTRAINT }

INSERT INTO t_replacing_is_deleted SETTINGS optimize_on_insert = 1 VALUES (3, 1, 2); -- { serverError VIOLATED_CONSTRAINT }

-- With the constraint disabled the invalid value is accepted. A part with it cannot be merged, so stop merges.
SYSTEM STOP MERGES t_replacing_is_deleted;
ALTER TABLE t_replacing_is_deleted MODIFY SETTING add_implicit_is_deleted_column_constraint_for_replacing_engine = 0;
INSERT INTO t_replacing_is_deleted SETTINGS optimize_on_insert = 0 VALUES (3, 1, 2);

SELECT * FROM t_replacing_is_deleted ORDER BY key;

CREATE TABLE t_collapsing (key UInt32, sign Int8)
ENGINE = CollapsingMergeTree(sign) ORDER BY key;

INSERT INTO t_collapsing SETTINGS optimize_on_insert = 0 VALUES (1, 1), (2, -1);
INSERT INTO t_collapsing SETTINGS optimize_on_insert = 0 VALUES (3, 5); -- { serverError VIOLATED_CONSTRAINT }
INSERT INTO t_collapsing SETTINGS optimize_on_insert = 1 VALUES (3, 5); -- { serverError VIOLATED_CONSTRAINT }

SELECT * FROM t_collapsing ORDER BY key;

DROP TABLE t_replacing_is_deleted;
DROP TABLE t_collapsing;
