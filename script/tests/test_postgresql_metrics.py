import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "postgresql_metrics", Path(__file__).resolve().parents[1] / "postgresql-metrics.py"
)
metrics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metrics)


def snapshot():
    return {
        "format_version": 1, "database": "campsite_production", "member": "pg-a", "application_role_oid": "123",
        "server_start": "2026-11-04T00:00:00+00:00", "in_recovery": False,
        "captured_at": "2026-11-04T01:00:00+00:00",
        "statement_stats": {"stats_reset": "2026-11-04T00:00:00+00:00", "dealloc": 0},
        "statements": [{
            "queryid": "9223372036854775806", "toplevel": True, "role_oid": "123",
            "calls": 10, "total_exec_time": 20, "operation": "SELECT",
        }],
    }


class MetricsComparisonTest(unittest.TestCase):
    def setUp(self):
        self.before = snapshot()
        self.after = copy.deepcopy(self.before)
        self.after["captured_at"] = "2026-11-04T01:00:10+00:00"

    def test_interval_mean_uses_deltas_rather_than_cumulative_mean(self):
        self.after["statements"][0].update(calls=15, total_exec_time=35)
        row = metrics.compare(self.before, self.after)["statements"][0]
        self.assertEqual(row["calls"], 5)
        self.assertEqual(row["calls_per_second"], 0.5)
        self.assertEqual(row["mean_exec_ms"], 3)
        self.assertEqual(row["queryid"], "9223372036854775806")

    def test_same_query_under_two_roles_is_not_overwritten(self):
        second = {**self.before["statements"][0], "role_oid": "456", "calls": 30}
        self.before["statements"].append(second)
        self.after["statements"].append({**second, "calls": 32, "total_exec_time": 22})
        rows = metrics.compare(self.before, self.after)["statements"]
        self.assertEqual([(row["role_oid"], row["calls"]) for row in rows], [("456", 2)])

    def test_new_statement_is_counted_from_zero(self):
        self.after["statements"].append({
            **self.before["statements"][0], "queryid": "new", "calls": 2, "total_exec_time": 8,
        })
        self.assertEqual(metrics.compare(self.before, self.after)["statements"][0]["mean_exec_ms"], 4)

    def test_rejects_restart_failover_reset_and_eviction(self):
        for field, value in (("member", "pg-b"), ("server_start", "later"), ("in_recovery", True)):
            with self.subTest(field=field):
                changed = copy.deepcopy(self.after)
                changed[field] = value
                with self.assertRaises(ValueError):
                    metrics.compare(self.before, changed)
        for field, value in (("stats_reset", "later"), ("dealloc", 1)):
            with self.subTest(field=field):
                changed = copy.deepcopy(self.after)
                changed["statement_stats"][field] = value
                with self.assertRaises(ValueError):
                    metrics.compare(self.before, changed)

    def test_rejects_non_increasing_time_and_counter_resets(self):
        with self.assertRaises(ValueError):
            metrics.compare(self.before, self.before)
        self.after["statements"][0]["calls"] = 9
        with self.assertRaises(ValueError):
            metrics.compare(self.before, self.after)


if __name__ == "__main__":
    unittest.main()
