DROP TABLE IF EXISTS replacing;

CREATE TABLE replacing (key int, value int, version int, mode UInt8) ENGINE = ReplacingMergeTree(version, mode) ORDER BY key;

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

DROP TABLE replacing;


