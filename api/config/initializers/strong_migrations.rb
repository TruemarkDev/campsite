# frozen_string_literal: true

# Existing migrations predate Strong Migrations and are intentionally
# grandfathered. New migrations are checked against the homelab MySQL version.
StrongMigrations.start_after = 20260825040000
StrongMigrations.target_version = "8.4"

# Keep a migration waiting on locks from stalling application traffic, while
# allowing bounded data-definition work to complete once it acquires the lock.
StrongMigrations.lock_timeout = 10.seconds
StrongMigrations.statement_timeout = 1.hour

# Refresh MySQL planner statistics after adding indexes.
StrongMigrations.auto_analyze = true
