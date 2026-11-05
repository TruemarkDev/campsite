#!/usr/bin/env python3
"""Read Campsite-only PostgreSQL counters without exporting SQL or bind values."""

import argparse
from datetime import date, datetime, timedelta, timezone
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile


MEMBERS = {
    "pg-a": ("192.168.10.33", "campsite-pg-a"),
    "pg-b": ("192.168.10.35", "campsite-pg-b"),
}
SQL = Path(__file__).with_name("sql") / "postgresql-metrics.sql"


def statement_key(row):
    return row["queryid"], row["toplevel"], row["role_oid"]


def compare(before, after):
    for field in ("format_version", "database", "member", "server_start", "in_recovery", "application_role_oid"):
        if before[field] != after[field]:
            raise ValueError(f"Incomparable snapshots: {field} changed")
    for field in ("stats_reset", "dealloc"):
        if before["statement_stats"][field] != after["statement_stats"][field]:
            raise ValueError(f"Incomparable snapshots: statement {field} changed")
    elapsed = (
        datetime.fromisoformat(after["captured_at"])
        - datetime.fromisoformat(before["captured_at"])
    ).total_seconds()
    if elapsed <= 0:
        raise ValueError("Snapshots must have increasing capture times")
    previous = {statement_key(row): row for row in before["statements"]}
    result = []
    for row in after["statements"]:
        old = previous.get(statement_key(row), {})
        calls = row["calls"] - old.get("calls", 0)
        total_ms = row["total_exec_time"] - old.get("total_exec_time", 0)
        if calls < 0 or total_ms < 0:
            raise ValueError("Incomparable snapshots: statement counters decreased")
        if calls:
            result.append({
                "queryid": row["queryid"], "toplevel": row["toplevel"], "role_oid": row["role_oid"],
                "operation": row["operation"], "calls": calls,
                "relation_tags": row.get("relation_tags", []),
                "calls_per_second": calls / elapsed,
                "total_exec_ms": total_ms, "mean_exec_ms": total_ms / calls,
            })
    return {
        "elapsed_seconds": elapsed,
        "statements": sorted(result, key=lambda row: row["total_exec_ms"], reverse=True),
    }


def snapshot(member, identity, local=False, allow_standby=False):
    host, container = MEMBERS[member]
    command = [
        "docker", "exec", "-i", "-u", "postgres", container,
        "psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-d", "campsite_production",
    ]
    if local:
        command[0] = "/usr/bin/docker"
    else:
        command = [
            "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
            "-i", str(identity), f"prakash@{host}", shlex.join(command),
        ]
    completed = subprocess.run(command, input=SQL.read_text(), capture_output=True,
                               text=True, timeout=30, check=True)
    result = json.loads(completed.stdout)
    if result["database"] != "campsite_production":
        raise ValueError("Unexpected metrics database")
    if result["in_recovery"] and not allow_standby:
        raise ValueError("Metrics must target the current Campsite primary; select its --member")
    if not result["application_role_oid"]:
        raise ValueError("Expected Campsite application role campsite_app is absent")
    result["member"] = member
    return result


def write_private(path, value, exclusive=False):
    """Publish complete JSON atomically; never replace a snapshot."""
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=".metrics-",
                                         delete=False) as output:
            temporary = Path(output.name)
            json.dump(value, output, indent=2, allow_nan=False)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        if exclusive:
            os.link(temporary, path)
        else:
            os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def daily_paths(directory, member):
    prefix = f"snapshot-{member}-"
    result = []
    for path in directory.glob(f"{prefix}*.json"):
        try:
            captured_date = date.fromisoformat(path.name[len(prefix):-5])
        except ValueError:
            continue
        if captured_date.isoformat() != path.name[len(prefix):-5]:
            continue
        result.append((captured_date, path))
    return sorted(result)


def collect_daily(member, identity, directory, local=False, retention_days=30, now=None):
    if not 1 <= retention_days <= 366:
        raise ValueError("Retention must be between 1 and 366 days")
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = directory.stat()
    if info.st_uid != os.geteuid() or info.st_mode & 0o077:
        raise ValueError("Daily directory must be owned by the collector user and private (0700)")
    now = now or datetime.now().astimezone()
    receipt = {"member": member, "run_at": now.astimezone(timezone.utc).isoformat()}
    latest = directory / "latest.json"
    target = directory / f"snapshot-{member}-{now.date().isoformat()}.json"
    try:
        # Only this collector's dated snapshots are eligible for retention.
        for captured_date, path in daily_paths(directory, member):
            if captured_date < now.date() - timedelta(days=retention_days - 1):
                path.unlink()
        if target.exists():
            existing = json.loads(target.read_text())
            if existing["member"] != member or existing["database"] != "campsite_production" or existing["in_recovery"]:
                raise ValueError("Existing daily snapshot has unexpected identity")
            receipt.update(status="already_collected", snapshot=target.name, captured_at=existing["captured_at"])
        else:
            current = snapshot(member, identity, local=local, allow_standby=True)
            if current["in_recovery"]:
                receipt["status"] = "skipped_standby"
            else:
                previous = [(day, path) for day, path in daily_paths(directory, member) if day < now.date()]
                comparison = {"status": "baseline"}
                if previous:
                    baseline = previous[-1][1]
                    comparison["baseline"] = baseline.name
                    try:
                        before = json.loads(baseline.read_text())
                        current["interval"] = compare(before, current)
                        comparison["status"] = "compared"
                    except (ValueError, KeyError, TypeError):
                        # A reset/failover/eviction or malformed baseline must not
                        # discard the new raw counters or manufacture a delta.
                        comparison["status"] = "baseline_reset"
                        comparison["reason"] = "previous_snapshot_not_comparable"
                current["comparison"] = comparison
                write_private(target, current, exclusive=True)
                receipt.update(status=comparison["status"], snapshot=target.name,
                               captured_at=current["captured_at"])
                if "baseline" in comparison:
                    receipt["baseline"] = comparison["baseline"]
        write_private(latest, receipt)
        return receipt
    except Exception as error:
        # Avoid copying SQL output, connection diagnostics or raw exception
        # messages into the persistent run receipt.
        write_private(latest, {**receipt, "status": "failed", "error_type": type(error).__name__})
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--member", choices=MEMBERS, default="pg-a")
    parser.add_argument("--identity", type=Path,
                        default=Path.home() / ".ssh/id_homelab_ed25519")
    parser.add_argument("--output", type=Path, help="New JSON file; existing files are never overwritten")
    parser.add_argument("--baseline", type=Path, help="Compare against a previous snapshot of this member")
    parser.add_argument("--local", action="store_true", help="Use this member's local Docker socket; no SSH key")
    parser.add_argument("--daily-directory", type=Path,
                        help="Collect once per local calendar day and write a latest-run receipt (use an external lock)")
    parser.add_argument("--retention-days", type=int, default=30)
    args = parser.parse_args()
    if args.daily_directory:
        if args.baseline or args.output:
            parser.error("--daily-directory cannot be combined with --baseline or --output")
        receipt = collect_daily(args.member, args.identity, args.daily_directory,
                                local=args.local, retention_days=args.retention_days)
        print(json.dumps(receipt))
        return
    result = snapshot(args.member, args.identity, local=args.local)
    if args.baseline:
        result["interval"] = compare(json.loads(args.baseline.read_text()), result)
    if args.output:
        # Exclusive creation avoids accidentally replacing an earlier baseline.
        with os.fdopen(os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as output:
            json.dump(result, output, indent=2, allow_nan=False)
            output.write("\n")
    else:
        print(json.dumps(result, indent=2, allow_nan=False))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"PostgreSQL metrics failed: {error}", file=sys.stderr)
        sys.exit(1)
