import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

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


class DailyCollectionTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.now = metrics.datetime.fromisoformat("2026-11-05T07:15:00+05:45")
        self.current = snapshot()
        self.current["captured_at"] = "2026-11-05T01:30:00+00:00"

    def collect(self, **options):
        with patch.object(metrics, "snapshot", return_value=self.current):
            return metrics.collect_daily("pg-a", Path("unused"), self.directory,
                                         local=True, now=self.now, **options)

    def seed(self, day, value=None):
        target = self.directory / f"snapshot-pg-a-{day}.json"
        metrics.write_private(target, value or snapshot(), exclusive=True)
        return target

    def test_initial_snapshot_and_receipt_are_private(self):
        receipt = self.collect()
        self.assertEqual(receipt["status"], "baseline")
        target = self.directory / receipt["snapshot"]
        self.assertEqual(json.loads(target.read_text())["comparison"], {"status": "baseline"})
        for path in (target, self.directory / "latest.json"):
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(list(self.directory.glob(".metrics-*")), [])

    def test_next_day_compares_and_retains_both_raw_snapshots(self):
        baseline = self.seed("2026-11-04")
        self.current["statements"][0].update(calls=15, total_exec_time=35)
        receipt = self.collect()
        current = json.loads((self.directory / receipt["snapshot"]).read_text())
        self.assertEqual(receipt["status"], "compared")
        self.assertEqual(receipt["baseline"], baseline.name)
        self.assertEqual(current["interval"]["statements"][0]["calls"], 5)
        self.assertEqual(current["interval"]["statements"][0]["mean_exec_ms"], 3)
        self.assertTrue(baseline.exists())

    def test_rerun_is_idempotent_and_does_not_query_database(self):
        first = self.collect()
        target = self.directory / first["snapshot"]
        original = target.read_bytes()
        with patch.object(metrics, "snapshot") as collect:
            receipt = metrics.collect_daily("pg-a", Path("unused"), self.directory,
                                            local=True, now=self.now)
        collect.assert_not_called()
        self.assertEqual(receipt["status"], "already_collected")
        self.assertEqual(target.read_bytes(), original)

    def test_restart_or_corrupt_baseline_preserves_new_raw_counters(self):
        baseline = self.seed("2026-11-04")
        self.current["server_start"] = "2026-11-05T00:00:00+00:00"
        receipt = self.collect()
        current = json.loads((self.directory / receipt["snapshot"]).read_text())
        self.assertEqual(receipt["status"], "baseline_reset")
        self.assertNotIn("interval", current)
        self.assertTrue(baseline.exists())

    def test_malformed_baseline_starts_a_new_interval(self):
        self.seed("2026-11-04").write_text("{invalid")
        self.assertEqual(self.collect()["status"], "baseline_reset")

    def test_standby_records_skip_without_exporting_raw_snapshot(self):
        self.current["in_recovery"] = True
        self.assertEqual(self.collect()["status"], "skipped_standby")
        self.assertEqual(list(self.directory.glob("snapshot-*.json")), [])
        self.assertEqual(json.loads((self.directory / "latest.json").read_text())["status"], "skipped_standby")

    def test_failure_receipt_does_not_copy_exception_output(self):
        with patch.object(metrics, "snapshot", side_effect=RuntimeError("private diagnostic sentinel")):
            with self.assertRaises(RuntimeError):
                metrics.collect_daily("pg-a", Path("unused"), self.directory, local=True, now=self.now)
        text = (self.directory / "latest.json").read_text()
        self.assertEqual(json.loads(text)["status"], "failed")
        self.assertEqual(json.loads(text)["error_type"], "RuntimeError")
        self.assertNotIn("sentinel", text)

    def test_retention_only_prunes_owned_canonical_dates(self):
        old = self.seed("2026-10-06")
        boundary = self.seed("2026-10-07")
        unrelated = self.directory / "operator-notes.json"
        unrelated.write_text("keep")
        malformed = self.directory / "snapshot-pg-a-20261001.json"
        malformed.write_text("keep")
        other_member = self.directory / "snapshot-pg-b-2026-10-01.json"
        other_member.write_text("keep")
        self.current["in_recovery"] = True
        self.collect()
        self.assertFalse(old.exists())
        for path in (boundary, unrelated, malformed, other_member):
            self.assertTrue(path.exists())

    def test_rejects_public_directory_and_invalid_retention(self):
        self.directory.chmod(0o755)
        with self.assertRaises(ValueError):
            self.collect()
        self.directory.chmod(0o700)
        for days in (0, 367):
            with self.assertRaises(ValueError):
                self.collect(retention_days=days)

    def test_atomic_publication_never_overwrites_snapshot(self):
        path = self.seed("2026-11-04")
        original = path.read_bytes()
        with self.assertRaises(FileExistsError):
            metrics.write_private(path, {"changed": True}, exclusive=True)
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual(list(self.directory.glob(".metrics-*")), [])

    def test_local_transport_uses_fixed_container_without_ssh(self):
        response = metrics.subprocess.CompletedProcess([], 0, stdout=json.dumps(self.current))
        with patch.object(metrics.subprocess, "run", return_value=response) as run:
            metrics.snapshot("pg-a", Path("unused"), local=True)
        command = run.call_args.args[0]
        self.assertEqual(command[:2], ["/usr/bin/docker", "exec"])
        self.assertIn("campsite-pg-a", command)
        self.assertNotIn("ssh", command)
        self.assertEqual(run.call_args.kwargs["timeout"], 30)

    def test_manual_transport_still_refuses_standby(self):
        self.current["in_recovery"] = True
        response = metrics.subprocess.CompletedProcess([], 0, stdout=json.dumps(self.current))
        with patch.object(metrics.subprocess, "run", return_value=response):
            with self.assertRaises(ValueError):
                metrics.snapshot("pg-a", Path("unused"), local=True)


if __name__ == "__main__":
    unittest.main()
