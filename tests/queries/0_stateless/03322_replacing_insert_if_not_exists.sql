SET insert_deduplicate = 0, optimize_on_insert = 0;

DROP TABLE IF EXISTS replacing;

CREATE TABLE replacing (key int, value int, version int, mode UInt8) ENGINE = ReplacingMergeTree(version, mode) ORDER BY key
SETTINGS allow_experimental_replacing_merge_with_cleanup = 1;

-- Insert if not exists
INSERT INTO replacing VALUES (1, 1, 1, 2);

SELECT * FROM replacing FINAL;

-- Insert (overwrites)
INSERT INTO replacing VALUES (1, 2, 2, 0);

SELECT * FROM replacing FINAL;

-- Insert if not exists (should not do anything)
INSERT INTO replacing VALUES (1, 3, 3, 2);

SELECT * FROM replacing FINAL;

-- Delete (now nothing should be returned with FINAL)
INSERT INTO replacing VALUES (1, 4, 4, 1);

SELECT * FROM replacing FINAL;

-- Insert if not exists (should work even if merge hasn't happened since previous row is a delete row)
INSERT INTO replacing VALUES (1, 5, 5, 2);

SELECT * FROM replacing FINAL;

-- Merge away all but the last insert if not exists row
OPTIMIZE TABLE replacing FINAL CLEANUP;

SELECT * FROM replacing;

SELECT * FROM replacing FINAL;

TRUNCATE TABLE replacing;

-- Insert if not exists
INSERT INTO replacing VALUES (1, 3, 3, 2);

-- Out of order previous insert
INSERT INTO replacing VALUES (1, 1, 1, 0);

TRUNCATE TABLE replacing;

INSERT INTO replacing VALUES (1, 3, 3, 2);
-- Delete with lower version before it
INSERT INTO replacing VALUES (1, 2, 2, 1);
-- Out of order previous insert - but masked by delete with higher version
INSERT INTO replacing VALUES (1, 1, 1, 0);

SELECT * FROM replacing FINAL;

DROP TABLE replacing;


