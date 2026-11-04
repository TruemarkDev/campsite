# frozen_string_literal: true

# Existing migrations predate Strong Migrations and are intentionally
# grandfathered. New migrations are checked against the selected database engine.
StrongMigrations.start_after = 20260825040000
StrongMigrations.target_version = "18"

# Keep a migration waiting on locks from stalling application traffic, while
# allowing bounded data-definition work to complete once it acquires the lock.
StrongMigrations.lock_timeout = 10.seconds
StrongMigrations.statement_timeout = 1.hour

# Refresh planner statistics after adding indexes.
StrongMigrations.auto_analyze = true
