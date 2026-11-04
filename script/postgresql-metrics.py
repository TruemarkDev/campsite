#!/usr/bin/env python3
"""Read Campsite-only PostgreSQL counters without exporting SQL or bind values."""

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys


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


def snapshot(member, identity):
    host, container = MEMBERS[member]
    remote = shlex.join([
        "docker", "exec", "-i", "-u", "postgres", container,
        "psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-d", "campsite_production",
    ])
    completed = subprocess.run([
        "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8",
        "-i", str(identity), f"prakash@{host}", remote,
    ], input=SQL.read_text(), capture_output=True, text=True, timeout=30, check=True)
    result = json.loads(completed.stdout)
    if result["database"] != "campsite_production" or result["in_recovery"]:
        raise ValueError("Metrics must target the current Campsite primary; select its --member")
    if not result["application_role_oid"]:
        raise ValueError("Expected Campsite application role campsite_app is absent")
    result["member"] = member
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--member", choices=MEMBERS, default="pg-a")
    parser.add_argument("--identity", type=Path,
                        default=Path.home() / ".ssh/id_homelab_ed25519")
    parser.add_argument("--output", type=Path, help="New JSON file; existing files are never overwritten")
    parser.add_argument("--baseline", type=Path, help="Compare against a previous snapshot of this member")
    args = parser.parse_args()
    result = snapshot(args.member, args.identity)
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
