import pytest

from helpers.cluster import ClickHouseCluster


cluster = ClickHouseCluster(__file__)
node = cluster.add_instance("node", main_configs=["configs/overcommit.xml"])


@pytest.fixture(scope="module", autouse=True)
def start_cluster():
    try:
        cluster.start()
        yield cluster
    finally:
        cluster.shutdown()


def test_system_log_flush_can_overcommit():
    if (
        node.is_built_with_memory_sanitizer()
        or node.is_built_with_address_sanitizer()
        or node.is_built_with_thread_sanitizer()
    ):
        pytest.skip("memory limits are too small for sanitizer builds")

    victim_query_id = "system_log_flush_overcommit_victim"
    query_id = "system_log_flush_overcommit_survivor"
    victim = node.get_query_request(
        "SELECT groupArray(number) FROM numbers(30000000) "
        "SETTINGS max_threads=1, memory_overcommit_ratio_denominator=1",
        ignore_error=True,
        query_id=victim_query_id,
    )
    node.query_with_retry(
        "SELECT count() FROM system.processes "
        f"WHERE query_id = '{victim_query_id}'",
        check_callback=lambda result: result.strip() == "1",
    )
    survivor = node.get_query_request(
        "SELECT 42 WHERE sleep(3) = 0 SETTINGS memory_overcommit_ratio_denominator=80000000",
        query_id=query_id,
    )

    node.query("SYSTEM FLUSH LOGS")

    survivor_result, survivor_error = survivor.get_answer_and_error()
    victim_result, victim_error = victim.get_answer_and_error()

    node.query("SYSTEM FLUSH LOGS")

    assert survivor_error == "", survivor_error
    assert survivor_result.strip() == "42"
    assert "MEMORY_LIMIT_EXCEEDED" in victim_error, victim_error
    assert victim_result == ""

    assert node.query(
        "SELECT count() FROM system.query_log "
        f"WHERE query_id = '{query_id}' AND type = 'QueryFinish'"
    ).strip() == "1"
