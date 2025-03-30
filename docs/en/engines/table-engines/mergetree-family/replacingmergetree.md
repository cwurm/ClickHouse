---
description: 'differs from MergeTree in that it removes duplicate rows with the
  same sorting key value (`ORDER BY` clause, not `PRIMARY KEY`).'
sidebar_label: 'ReplacingMergeTree'
sidebar_position: 40
slug: /engines/table-engines/mergetree-family/replacingmergetree
title: 'ReplacingMergeTree'
---

# ReplacingMergeTree

The engine differs from [MergeTree](/engines/table-engines/mergetree-family/versionedcollapsingmergetree) in that it removes duplicate rows with the same [sorting key](../../../engines/table-engines/mergetree-family/mergetree.md) value (`ORDER BY` clause, not `PRIMARY KEY`).

Rows are deduplicated at query time if the [`FINAL`](../../../sql-reference/statements/select/from.md#final-modifier) modifier is used and during background merges. When exactly merges happen is unpredictable and you should generally not rely on the absence of duplicates at query time when not using the `FINAL` modifier.

:::note
Please read the detailed guide on [Updating Data with ReplacingMergeTree](/guides/replacing-merge-tree) for more information including best practices on schema design, merges and optimizing query performance.
:::

## Creating a Table {#creating-a-table}

```sql
CREATE TABLE [IF NOT EXISTS] [db.]table_name [ON CLUSTER cluster]
(
    name1 [type1] [DEFAULT|MATERIALIZED|ALIAS expr1],
    name2 [type2] [DEFAULT|MATERIALIZED|ALIAS expr2],
    ...
) ENGINE = ReplacingMergeTree([ver [, state]])
[PARTITION BY expr]
[ORDER BY expr]
[PRIMARY KEY expr]
[SAMPLE BY expr]
[SETTINGS name=value, ...]
```

For a description of request parameters, see [statement description](../../../sql-reference/statements/create/table.md).

:::note
Uniqueness of rows is determined by the `ORDER BY` clause, not `PRIMARY KEY`.
:::

## ReplacingMergeTree Parameters {#replacingmergetree-parameters}

### ver {#ver}

`ver` — column with the version number. Type `UInt*`, `Date`, `DateTime` or `DateTime64`. Optional parameter.

When merging, `ReplacingMergeTree` from all the rows with the same sorting key leaves only one:

   - The last in the selection, if `ver` not set. A selection is a set of rows in a set of parts participating in the merge. The most recently created part (the last insert) will be the last one in the selection. Thus, after deduplication, the very last row from the most recent insert will remain for each unique sorting key.
   - With the maximum version, if `ver` specified. If `ver` is the same for several rows, then it will use "if `ver` is not specified" rule for them, i.e. the most recent inserted row will remain.

Example:

```sql
-- without ver - the last inserted 'wins'
CREATE TABLE myFirstReplacingMT
(
    `key` Int64,
    `someCol` String,
    `eventTime` DateTime
)
ENGINE = ReplacingMergeTree
ORDER BY key;

INSERT INTO myFirstReplacingMT Values (1, 'first', '2020-01-01 01:01:01');
INSERT INTO myFirstReplacingMT Values (1, 'second', '2020-01-01 00:00:00');

SELECT * FROM myFirstReplacingMT FINAL;

┌─key─┬─someCol─┬───────────eventTime─┐
│   1 │ second  │ 2020-01-01 00:00:00 │
└─────┴─────────┴─────────────────────┘


-- with ver - the row with the biggest ver 'wins'
CREATE TABLE mySecondReplacingMT
(
    `key` Int64,
    `someCol` String,
    `eventTime` DateTime
)
ENGINE = ReplacingMergeTree(eventTime)
ORDER BY key;

INSERT INTO mySecondReplacingMT Values (1, 'first', '2020-01-01 01:01:01');
INSERT INTO mySecondReplacingMT Values (1, 'second', '2020-01-01 00:00:00');

SELECT * FROM mySecondReplacingMT FINAL;

┌─key─┬─someCol─┬───────────eventTime─┐
│   1 │ first   │ 2020-01-01 01:01:01 │
└─────┴─────────┴─────────────────────┘
```

### state {#state}

`state` — Optional name of a column that determines how this row should be merged. If not specified, all rows are treated as if they had `state = 0`
and will replace any previous rows with the same sorting key value.

Column data type — `UInt8`.

Possible values:

- `0` - Row will replace any previous row with the same sorting key value.
- `1` - Delete row that will mask any previous rows with the same sorting key value. It will not show up in the result of `FINAL` queries.
- `2` - Insert if not exists row which will only show up in results of `FINAL` queries if there is no previous row with the same sorting key value or the immediately previous row is a delete row.

:::note
`state` can only be enabled when `ver` is used.

No matter the operation on the data, the version of a row with the same sorting key value as a previous row should be increased.
If two inserted rows have the same version number, they are processed in the order they were inserted in.

ClickHouse will keep the last row for a key even if that row is a delete row. It will also keep all rows with state `2` (insert if not exists) that are not followed by rows with other states. This is so that any future rows with lower versions can
be safely inserted and the correct logic will still be applied.

To permanently merge away rows with states `1` and `2` that are not needed, enable the table setting `allow_experimental_replacing_merge_with_cleanup` and either:

1. Set the table settings `enable_replacing_merge_with_cleanup_for_min_age_to_force_merge`, `min_age_to_force_merge_on_partition_only` and `min_age_to_force_merge_seconds`. If all parts in a partition are older than `min_age_to_force_merge_seconds`, ClickHouse will merge them
all into a single part and remove any delete rows.

2. Manually run `OPTIMIZE TABLE table [PARTITION partition | PARTITION ID 'partition_id'] FINAL CLEANUP`.
:::

Example:
```sql
-- With version and state
CREATE TABLE replacing
(
    `key` Int64,
    `someCol` String,
    `eventTime` DateTime,
    `state` UInt8
)
ENGINE = ReplacingMergeTree(eventTime, state)
ORDER BY key
SETTINGS allow_experimental_replacing_merge_with_cleanup = 1;

INSERT INTO replacing Values (1, 'first', '2020-01-01 01:01:01', 0);
INSERT INTO replacing Values (1, 'second', '2020-01-01 01:01:02', 1);

SELECT * FROM replacing FINAL;

0 rows in set. Elapsed: 0.003 sec.

INSERT INTO replacing Values (1, 'third', '2020-01-01 01:01:03', 2);

-- Merge but preserve delete and insert if not exists row
OPTIMIZE TABLE replacing FINAL;

SELECT * FROM replacing FINAL;

┌─key─┬─someCol─┬───────────eventTime─┬─state─┐
│   1 │ third   │ 2020-01-01 01:01:03 │     2 │
└─────┴─────────┴─────────────────────┴───────┘

-- Permanently drop delete row
OPTIMIZE TABLE replacing FINAL CLEANUP;

INSERT INTO replacing Values (1, 'first', '2020-01-01 00:00:00', 0);

select * from myThirdReplacingMT final;

┌─key─┬─someCol─┬───────────eventTime─┬─state──────┐
│   1 │ first   │ 2020-01-01 00:00:00 │          0 │
└─────┴─────────┴─────────────────────┴────────────┘
```

## Query clauses {#query-clauses}

When creating a `ReplacingMergeTree` table the same [clauses](../../../engines/table-engines/mergetree-family/mergetree.md) are required, as when creating a `MergeTree` table.

<details markdown="1">

<summary>Deprecated Method for Creating a Table</summary>

:::note
Do not use this method in new projects and, if possible, switch old projects to the method described above.
:::

```sql
CREATE TABLE [IF NOT EXISTS] [db.]table_name [ON CLUSTER cluster]
(
    name1 [type1] [DEFAULT|MATERIALIZED|ALIAS expr1],
    name2 [type2] [DEFAULT|MATERIALIZED|ALIAS expr2],
    ...
) ENGINE [=] ReplacingMergeTree(date-column [, sampling_expression], (primary, key), index_granularity, [ver])
```

All of the parameters excepting `ver` have the same meaning as in `MergeTree`.

- `ver` - column with the version. Optional parameter. For a description, see the text above.

</details>

## Query time de-duplication & FINAL {#query-time-de-duplication--final}

At merge time, the ReplacingMergeTree identifies duplicate rows, using the values of the `ORDER BY` columns (used to create the table) as a unique identifier, and retains only the highest version. This, however, offers eventual correctness only - it does not guarantee rows will be deduplicated, and you should not rely on it. Queries can, therefore, produce incorrect answers due to update and delete rows being considered in queries.

To obtain correct answers, users will need to complement background merges with query time deduplication and deletion removal. This can be achieved using the `FINAL` operator. For example, consider the following example:

```sql
CREATE TABLE rmt_example
(
    `number` UInt16
)
ENGINE = ReplacingMergeTree
ORDER BY number

INSERT INTO rmt_example SELECT floor(randUniform(0, 100)) AS number
FROM numbers(1000000000)

0 rows in set. Elapsed: 19.958 sec. Processed 1.00 billion rows, 8.00 GB (50.11 million rows/s., 400.84 MB/s.)
```
Querying without `FINAL` produces an incorrect count (exact result will vary depending on merges):

```sql
SELECT count()
FROM rmt_example

┌─count()─┐
│     200 │
└─────────┘

1 row in set. Elapsed: 0.002 sec.
```

Adding final produces a correct result:

```sql
SELECT count()
FROM rmt_example
FINAL

┌─count()─┐
│     100 │
└─────────┘

1 row in set. Elapsed: 0.002 sec.
```

For further details on `FINAL`, including how to optimize `FINAL` performance, we recommend reading our [detailed guide on ReplacingMergeTree](/guides/replacing-merge-tree).
