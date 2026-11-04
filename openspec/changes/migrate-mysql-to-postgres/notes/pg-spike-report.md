# PostgreSQL 18 test-suite spike

## Run and result

- PostgreSQL image: `postgres:18`, disposable container `campsite-pg-spike`, host port `5434` only.
- Rails adapter: `pg 1.6.3`; test database: `campsite_api_test_pg`; schema loaded from the generated PostgreSQL schema.
- The completed full run used `PARALLEL_WORKERS=1` to avoid a prior eight-worker run hanging after a `pg` C-extension segmentation fault in `connect_start`. It completed in 2,490.55 seconds.
- This checkout's RubyGems/Bundler setup required preloading `rubygems/resolver/api_set/gem_parser` and invoking Rails through mise's Ruby. Rails boot also required `S3_REGION=us-east-1`; telemetry export was disabled for the run. `RAILS_MASTER_KEY` was unset as required.
- Completed result: **4,226 runs, 10,091 assertions, 7 failures, 758 errors, 0 skips**. The test runner finished; these are full-run totals. Some errors are secondary to earlier SQL errors, so the categories below describe the first visible failure in each case.
- `db:create` reported the existing `campsite_api_development` database and left it unchanged. The test connection and schema load targeted `campsite_api_test_pg`; the shared MySQL test database was not used. No MySQL data was written.

The initial eight-worker attempt was not counted: one worker segfaulted in `pg` at `PG::Connection#connect_start`, after which the parallelization coordinator hung. The successful run used one test worker.

## Errors grouped by visible root cause

| Count | Root cause and example tests | Offending code | `tasks.md` coverage |
| ---: | --- | --- | --- |
| 405 | Prosopite's N+1 detector raises `LoadError: Could not load the 'pg_query' gem`. Examples: `MessageThreads::MessagesControllerTest#destroy`, `OrganizationMembersControllerTest#reactivate`, `Notes::TimelineEventsControllerTest#index`. | `api/app/controllers/api/v1/base_controller.rb:214-218` | **NOT COVERED** — no test-instrumentation/parser dependency or PostgreSQL guard is planned. |
| 132 | MySQL reaction aggregation fails: 131 `IF(...)` SQL errors and one PostgreSQL array value passed to `JSON.parse`. Examples: `Posts::TasksControllerTest#update`, `Posts::PublicationsControllerTest#create`, `PostTest#grouped_reactions`. | `api/app/models/concerns/reactable.rb:20-30` | 1.3 covers portable `MAX(IF(...))` and `JSON_ARRAYAGG` behavior. |
| 75 | Grouped `UserSubscription` relations select `user_subscriptions.*`; PostgreSQL rejects the ungrouped `id`. Examples: `Notes::AttachmentsControllerTest#destroy`, `ProjectsControllerTest#index`, `ProjectTest#prerenders: viewer has subscribed`. | `api/app/models/project.rb:208-212` | **NOT COVERED** — these are Active Record grouped relations, not raw SQL fragments in 1.10. |
| 74 | MySQL null-safe `<=>` comparisons are unsupported. Examples: `DeliverWebPushCallRoomInvitationJobTest#perform`, `MessageThreads::FavoritesControllerTest#create`, `ProjectTest#unread_for_viewer_async`. | `api/app/models/notification.rb:56`; `api/app/models/message_thread_membership.rb:23`; `api/app/models/project.rb:242` | 1.10 covers review of these SQL fragments. |
| 28 | MCP tool tests receive no JSON-RPC `result`, then raise `NoMethodError` in the test helper. Examples: `McpControllerTest#reply_to_comment`, `#update_post`, `#list_notifications`. The underlying response body is not present in the failure trace. | `api/test/controllers/mcp_controller_test.rb:1719-1733` | **NOT COVERED** — cause needs follow-up from the actual HTTP response. |
| 10 | `CONVERT_TZ` in notification schedule selection is undefined. Examples: `ApplyNotificationSchedulesTest#perform` cases for missing timezone and weekday scheduling. | `api/app/models/notification_schedule.rb:23-39` | 1.1 covers `NotificationSchedule` time-zone SQL. |
| 8 | PostgreSQL rejects `SELECT DISTINCT` queries ordered by an expression omitted from the select list. Examples: `Search::MixedControllerTest#index` for calls, all results, and highlights. | `api/app/controllers/api/v1/search/mixed_controller.rb:41-43` | **NOT COVERED** — generated Active Record ordering is outside the raw SQL review in 1.10. |
| 6 | `IFNULL` and MySQL `INTERVAL ... SECOND` make scheduled-notification queries invalid. Examples: `ScheduledNotificationTest#schedulable_in` (no delivery day and two-date window), `SchedulePostDigestNotificationJobsTest#perform`. | `api/app/models/scheduled_notification.rb:30-39` | 1.2 covers delivery-window SQL. |
| 5 | `TIMESTAMPDIFF(SECOND, ...)` fails in call-health checks. Examples: `CallHealthJobTest#perform` for stuck processing, recent processing, and completed calls. | `api/app/jobs/call_health_job.rb:12` | 1.5 covers `TIMESTAMPDIFF` in `CallHealthJob`. |
| 4 | MCP tests hit `PG::InFailedSqlTransaction` during follow-up work after a statement has already aborted the transaction. Examples: `McpControllerTest#create_project`, `#send_message`, `#add_comment`. The original statement failure is not included in these traces. | `api/test/controllers/mcp_controller_test.rb:486-915` (follow-up queries) | **NOT COVERED** — migration atomicity in 3.4 does not cover request transaction recovery. |
| 3 | `DATEDIFF` is undefined in viewer recent-post scoring. Examples: `ProjectTest#prerenders`, `Sync::ProjectsControllerTest#index` (result and query-count cases). | `api/app/models/project.rb:152` | 1.10 covers raw SQL review. |
| 3 | MySQL `REGEXP` syntax is rejected by PostgreSQL. Examples: `ChatChannelBackfillTest#run` for both backfill modes and dry-run. | `api/lib/backfills/chat_channel_backfill.rb:6` | 1.10 covers raw SQL review. |
| 2 | `JSON_CONTAINS_PATH` is undefined in content timestamp selection. Examples: `SetContentUpdatedAtJobTest#perform` for recent and absent allowlisted events. | `api/app/jobs/set_content_updated_at_job.rb:10-12` | 1.5 covers `JSON_CONTAINS_PATH` / `JSON_OVERLAPS`. |
| 1 | `GROUP_CONCAT` is undefined while building poll-vote option IDs. Example: `PostTest#prerenders` viewer-voted case. | `api/app/models/post.rb:891-897` | 1.4 covers `GROUP_CONCAT`. |
| 1 | `upsert_all` attempts a duplicate insert without the unique conflict target. Example: `PostViewTest#counter_culture` retaining `read_at`. | `api/app/models/post_view.rb:96` | 1.6 covers `PostView.upsert_all` conflict targeting. |
| 1 | PostgreSQL rejects the MySQL-style qualified assignment in `update_all`. Example: `CallPeersUserIdBackfillTest#run`. | `api/lib/backfills/call_peers_user_id_backfill.rb:11` | 1.10 covers raw SQL review. |

The error counts above sum to 758. The four aborted-transaction cases and 28 missing MCP results are reported separately because the suite output does not establish a shared initiating error.

## Failures

| Count | Observed mismatch and example test | Offending code | `tasks.md` coverage |
| ---: | --- | --- | --- |
| 1 | Nullable cursor pagination repeats rows and omits expected rows. `CursorPaginationTest#run` fails its two-direction completeness assertion. | `api/lib/cursor_pagination.rb:50-69` | 1.7 covers cursor traversal and explicit NULL ordering. |
| 2 | Search `LIKE` is case-sensitive on PostgreSQL: the `"Match Member2"` record is omitted for query `match`, and `MAR` does not match `Marketing`. | `api/app/models/organization_membership.rb:76-80`; `api/app/models/project.rb:107-109` | 1.10 covers raw SQL review; 1.8 is limited to identity lookups. |
| 3 | Boolean setting writes to a PostgreSQL-backed string column do not satisfy the application's `value == "1"` check. Examples: `OrganizationTest#enforce_two_factor_authentication?`, `OrganizationsControllerTest#show`, `#update`. | `api/app/models/organization.rb:401-410` | **NOT COVERED** — `organization_settings.value` is `varchar`, not a `tinyint(1)` column handled by the pgloader cast in 5.2. |
| 1 | The post subscription association has no order, but the test assumes its first row belongs to the author. `Post::CreatePostTest#creates a post with feedback requests` observes the other subscription first. | `api/app/models/post.rb:57`; assumption at `api/test/models/post/create_post_test.rb:303-307` | **NOT COVERED**. |

## Gaps not specifically covered by the plan

Task 3.3 is the general suite-fix gate, but the following need explicit investigation or acceptance criteria beyond the currently targeted fixes:

- Supply or guard the `pg_query` dependency used by Prosopite during PostgreSQL controller tests.
- Fix the Active Record `GROUP BY` / implicit `SELECT *` incompatibility and the `DISTINCT` plus `in_order_of` ordering incompatibility.
- Inspect MCP responses for the 28 missing `result` failures and identify the initiating SQL errors behind the four aborted-transaction cases.
- Normalize the string-backed organization 2FA setting across adapters.
- Add deterministic ordering for the post subscription association or change the test to assert membership without relying on row order.
- Decide whether PostgreSQL search should preserve MySQL's case-insensitive `LIKE` behavior outside the identity columns addressed by D2.
