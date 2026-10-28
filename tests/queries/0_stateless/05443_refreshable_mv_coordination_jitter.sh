#!/usr/bin/env bash
# Tags: zookeeper, no-replicated-database, no-ordinary-database
# no-replicated-database: this test explicitly creates a Replicated database.

# A coordinated refreshable materialized view without `RANDOMIZE FOR` must not be refreshed by the
# same replica every time: each replica waits a random `refresh_coordination_jitter_ms` delay before
# racing for the refresh, so every replica eventually performs one.

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

db1="${CLICKHOUSE_DATABASE}_r1"
db2="${CLICKHOUSE_DATABASE}_r2"
zk_path="/test/${CLICKHOUSE_TEST_ZOOKEEPER_PREFIX}/${CLICKHOUSE_DATABASE}/rmv_coordination_jitter"

$CLICKHOUSE_CLIENT --distributed_ddl_output_mode=none -q "CREATE DATABASE ${db1} ENGINE = Replicated('${zk_path}', 's1', 'r1')"
$CLICKHOUSE_CLIENT --distributed_ddl_output_mode=none -q "CREATE DATABASE ${db2} ENGINE = Replicated('${zk_path}', 's1', 'r2')"

# The refresh query runs with the view's database as the current database, so each row tells which replica refreshed.
$CLICKHOUSE_CLIENT --distributed_ddl_output_mode=none -q "
    CREATE TABLE ${db1}.target (db String) ENGINE = ReplicatedMergeTree ORDER BY db;
    CREATE MATERIALIZED VIEW ${db1}.rmv REFRESH EVERY 1 SECOND APPEND TO ${db1}.target AS SELECT currentDatabase() AS db;
    SYSTEM SYNC DATABASE REPLICA ${db2};"

# The chance that one replica wins every one of the ~60 refreshes is negligible.
for _ in {1..60}
do
    replicas=$($CLICKHOUSE_CLIENT -q "SELECT uniqExact(db) FROM ${db1}.target")
    [ "$replicas" -ge 2 ] && break
    sleep 1
done
echo "$replicas"

$CLICKHOUSE_CLIENT --distributed_ddl_output_mode=none -q "DROP DATABASE ${db2} SYNC"
$CLICKHOUSE_CLIENT --distributed_ddl_output_mode=none -q "DROP DATABASE ${db1} SYNC"
