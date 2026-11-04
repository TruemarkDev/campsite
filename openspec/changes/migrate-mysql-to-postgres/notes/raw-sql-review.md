# Raw SQL portability review (Phase 1)

Reviewed 2026-09-24 against the Rails application and `api/lib`. Verdicts describe
the SQL shape on MySQL and whether PostgreSQL portability has been implemented
in Phase 1. `needs-test` rows name a focused test that pins the behavior before
any PostgreSQL cutover; a test name can be shared across repeated call sites.

| File:line | Construct | Verdict | Test name |
|---|---|---|---|
| `api/app/models/notification_schedule.rb:17-44` | `COALESCE`, `CONVERT_TZ`, `CONCAT`, `DATE`, `DAYOFWEEK`, CASE boolean schedule predicate | fixed (MySQL zone conversion retained; PostgreSQL branch still required) | `ApplyNotificationSchedulesTest#test_0001_applies_on_the_user's_local_day_when_that_day_differs_from_UTC` |
| `api/app/jobs/set_content_updated_at_job.rb:14-15` | PostgreSQL jsonb key existence functions with named array bind | fixed (function calls avoid `?`/`?|` bind ambiguity; MySQL JSON functions retained) | `SetContentUpdatedAtJobTest#PostgreSQL_predicates_use_named_binds_instead_of_jsonb_operator_placeholders` |
| `api/app/models/concerns/reactable.rb:30` | PostgreSQL `json_agg` adapter result | fixed (parse only adapter strings; decoded arrays pass through) | `PostTest#handles_an_already_decoded_JSON_array` |
| `api/app/models/message_thread_membership.rb:24` | MySQL null-safe `<=>` sender inequality | fixed (PostgreSQL `IS DISTINCT FROM`; MySQL `<=>` retained) | `MessageThreadTest#unread_membership_comparison_preserves_null_safe_sender_inequality` |
| `api/app/models/notification.rb:56` | MySQL null-safe `<=>` target-scope equality | fixed (PostgreSQL `IS NOT DISTINCT FROM`; MySQL `<=>` retained) | `NotificationTest#most_recent_scope_treats_two_NULL_target_scopes_as_equal` |
| `api/app/models/project.rb:242` | MySQL null-safe `<=>` post-sender inequality | fixed (PostgreSQL `IS DISTINCT FROM`; MySQL `<=>` retained) | `ProjectTest#includes_unread_post_with_no_sender_membership` |
| `api/app/models/scheduled_notification.rb:33-71` | `COALESCE`, time-zone conversion, date/time extraction, day difference, offset arithmetic | fixed (adapter branches; MySQL implementation preserved) | `ScheduledNotificationTest#test_0001_returns_schedulable_notifications_within_the_time_frame` in UTC/non-UTC/offset contexts |
| `api/app/models/concerns/reactable.rb:15-22,53` | `MIN`, `MAX(CASE)`, `COUNT`, JSON aggregate | fixed (`MAX(IF)` removed; JSON aggregation adapter-branched) | `PostTest#test_0001_returns_reactions_grouped_by_post_id`; `PostTest#test_0001_falls_back_to_username_for_tooltip_if_user_has_no_name` |
| `api/app/models/post.rb:891-904` | `GROUP_CONCAT` / `string_agg` poll option IDs | fixed (adapter branch) | `PostTest#test_0007_viewer_voted` |
| `api/app/jobs/set_content_updated_at_job.rb:11-18` | JSON object key existence/overlap | fixed (PostgreSQL `?`/`?|` branch; MySQL JSON functions retained) | `SetContentUpdatedAtJobTest#test_0001_sets_content_updated_at_to_the_most_recent_allowed_event`; `#test_0002_sets_content_updated_at_to_created_at_if_no_allowed_events_exist` |
| `api/app/jobs/call_health_job.rb:12,39-41` | `TIMESTAMPDIFF` / epoch extraction | fixed (adapter branch) | `CallHealthJobTest#test_0001_reports_to_Sentry_when_recording_is_stuck_processing`; `#test_0002_reports_to_Sentry_when_transcript_is_stuck_processing` |
| `api/app/models/post_view.rb:96-100` | `upsert_all` conflict target | fixed (PostgreSQL `unique_by:`; Trilogy uses MySQL any-unique-key behavior) | `PostViewTest#test_0006_updating_the_same_member_and_post_in_separate_batches_keeps_one_view` |
| `api/lib/cursor_pagination.rb:32-38` | ordered nullable columns and lexicographic cursor comparisons | fixed (PostgreSQL explicit NULLS FIRST/LAST; MySQL native ordering retained) | `CursorPaginationTest#test_0001_walks_nullable_sort_values_in_both_directions_without_skipping_boundary_records` |
| `api/app/models/user.rb:154` | email equality lookup outside Devise | fixed (input downcased) | `UserTest#test_0001_matches_an_existing_user_when_the_provider_email_has_different_casing` |
| `api/app/models/organization_invitation.rb:31` | `LIKE` search | needs-test (collation and wildcard behavior can differ by adapter) | `OrganizationInvitationTest#test_0001_search_by_matches_invitation_email_text` |
| `api/app/models/organization_invitation.rb:62-63` | application-side email equality | fixed (case-insensitive comparison) | `OrganizationInvitationTest#test_0002_accepts_a_matching_invitation_when_email_casing_differs` |
| `api/app/controllers/api/v1/users/organization_invitations_controller.rb:17` | email equality lookup | fixed (lookup input downcased) | `Users::OrganizationInvitationsControllerTest#test_0001_matches_invitations_when_the_signed_in_email_differs_in_casing` |
| `api/app/models/organization.rb:267,280` | invitation email equality | fixed (lookup input downcased) | `OrganizationInvitationTest#test_0002_accepts_a_matching_invitation_when_email_casing_differs` |
| `api/app/models/organization/invite_members.rb:35,41,49,55` | set membership email lookups | fixed (input lists downcased) | `InviteMembersTest` mixed-case invitation/member scenarios (existing invite flow suite) |
| `api/app/models/comment.rb:74-76` | joins, `IS NULL`, boolean literal comparison | needs-test (boolean representation on PostgreSQL) | `CommentTest#test_0001_returns_comments_not_belonging_to_posts_in_private_projects` |
| `api/app/models/project.rb:85-94` | correlated `EXISTS` subquery | portable (standard SQL, bound relation subquery) | — |
| `api/app/models/post.rb:942` | explicit `LEFT JOIN` with membership ID interpolation | portable (integer ID from persisted membership; standard join) | `PostTest` unseen comment count with post views |
| `api/app/models/linear_events/event_callback.rb:24` | explicit `INNER JOIN` and string discriminator | portable (standard join) | — |
| `api/lib/backfills/project_view_backfill.rb:11,19` | correlated `NOT EXISTS` | portable (standard SQL) | — |
| `api/app/models/concerns/commentable.rb:28` | `MAX(id)` aggregate | portable (standard SQL) | — |
| `api/app/controllers/api/v1/organization_memberships/statuses_controller.rb:13` | `MAX(id)` aggregate | portable (standard SQL) | — |
| `api/app/models/attachment.rb:146-152` | `MAX(id)` with grouped association columns and alias ordering | needs-test (PostgreSQL grouping rules are stricter) | `AttachmentTest#test_0001_latest_commenters_returns_distinct_members_ordered_by_their_latest_comment` |
| `api/app/models/message.rb:128` | `MAX(posts.id)` aggregate | portable (standard SQL) | — |
| `api/app/models/concerns/pinnable.rb:14` | `MIN(public_id)` aggregate | portable (standard SQL) | — |
| `api/app/models/user.rb:422,432,441,449` | `GROUP BY organizations.slug` | needs-test (selected columns/grouping compatibility) | `UserTest#verified_domain_organizations` and `UserTest#suggested_organizations` focused cases |
| `api/app/models/post.rb:900` | `GROUP BY polls.id` | portable (standard SQL; primary key functionally determines row) | `PostTest#test_0007_viewer_voted` |
| `api/app/models/post.rb:1007` | `MAX(comments.id)` | portable (standard SQL) | — |
| `api/app/models/user.rb:280` | bound equality/OR predicate | portable (standard SQL) | — |
| `api/app/models/user.rb:438` | `COALESCE` with bound timestamp | portable (standard SQL) | — |
| `api/app/models/post_view.rb:12` | `COALESCE` comparison | portable (standard SQL) | — |
| `api/app/models/organization_membership_status.rb:16-17` | timestamp comparison and NULL predicate | portable (standard SQL) | — |
| `api/app/models/message_thread_membership.rb:31` | boolean timestamp/NULL comparison | portable (standard SQL) | — |
| `api/app/models/bookmark.rb:27` | bound numeric comparison | portable (standard SQL) | — |
| `api/app/jobs/user_post_digest_notification_job.rb:38,47,62,65` | bound timestamp ranges and comparisons | portable (standard SQL) | — |
| `api/lib/backfills/call_recording_summary_section_backfill.rb:44` | bound timestamp comparison | portable (standard SQL) | — |
| `api/lib/backfills/remove_closure_tree_backfill.rb:8,16` | `IS NULL` and `IS NOT NULL` predicates | portable (standard SQL) | — |
| `api/lib/backfills/project_last_activity_at_backfill.rb:23` | `COALESCE` in update expression | portable (standard SQL) | — |
| `api/lib/backfills/post_last_activity_at_backfill.rb:23` | `COALESCE` in update expression | portable (standard SQL) | — |
| `api/lib/backfills/note_last_activity_at_backfill.rb:23-24` | NULL assignment and `GREATEST(COALESCE(...))` | needs-test (NULL semantics/functions should be pinned on both adapters) | `Backfills::NoteLastActivityAtBackfillTest#test_0001_sets_last_activity_at_to_the_most_recent_of_content_updated_at_or_latest_comment_created_at` |
| `api/lib/backfills/call_recording_transcription_succeeded_at_backfill.rb:8` | column-to-column update assignment | portable (standard SQL) | — |
| `api/lib/backfills/oauth_access_token_previous_token_backfill.rb:8` | column-to-column update assignment | portable (standard SQL) | — |
| `api/lib/backfills/call_peers_user_id_backfill.rb:11` | joined column assignment | needs-test (MySQL UPDATE JOIN shape is adapter-specific) | `Backfills::CallPeersUserIdBackfillTest#updates_user_id_for_call_peers_with_organization_memberships` |
| `api/lib/backfills/post_views_read_at_backfill.rb:9` | column-to-column update assignment | portable (standard SQL) | — |
| `api/lib/backfills/mentions_missing_attributes_backfill.rb:13,25,37` | HTML `LIKE` pattern matching | needs-test (LIKE collation/pattern semantics differ) | `Backfills::MentionsMissingAttributesBackfillTest#updates_old_mentions` |
| `api/lib/backfills/mention_class_backfill.rb:14,23,31` | HTML `LIKE` pattern matching | needs-test (LIKE collation/pattern semantics differ) | `Backfills::MentionClassBackfillTest#updates_old_mentions` |
| `api/lib/backfills/mentions_username_to_name_backfill.rb:11,23,35` | HTML `LIKE` pattern matching | needs-test (LIKE collation/pattern semantics differ) | `Backfills::MentionsUsernameToNameBackfillTest#updates_old_mentions` |
| `api/lib/backfills/note_attachment_extension_backfill.rb:9` | HTML `LIKE` pattern matching | needs-test (LIKE collation/pattern semantics differ) | `Backfills::NoteAttachmentExtensionBackfillTest` matching extension cases |
| `api/lib/backfills/missing_prose_link_backfill.rb:8` | HTML `LIKE` pattern matching | needs-test (LIKE collation/pattern semantics differ) | `Backfills::MissingProseLinkBackfillTest` matching/non-matching prose-link cases |
| `api/lib/backfills/update_co_to_com_links_backfill.rb:13,15,22,29` | constructed HTML `LIKE` pattern | needs-test (quoted pattern and collation behavior) | `Backfills::UpdateCoToComLinksBackfillTest` matching/non-matching domain cases |
| `api/lib/backfills/remote_user_avatar_backfill.rb:6` | URL-prefix `LIKE` pattern | portable (ASCII URL prefix; standard LIKE) | — |
| `api/lib/backfills/chat_channel_backfill.rb:6` | MySQL `REGEXP` | needs-test (syntax differs from PostgreSQL regex operators) | `Backfills::ChatChannelBackfillTest#moves_titled_group_chats_to_private_chat_channels_for_specified_organization` |
| `api/lib/backfills/dupe_views_backfill.rb:8` | `COUNT(1)` aggregate filter | portable (standard SQL) | — |
| `api/app/models/organization_membership.rb:78` | multi-column `LIKE` search | needs-test (collation and case behavior differ) | `OrganizationMembershipTest#search_by_matches_username_name_and_email_text` |
| `api/app/models/organization_invitation.rb:31` | `LIKE` search | needs-test (collation and wildcard behavior differ) | `OrganizationInvitationTest#test_0001_search_by_matches_invitation_email_text` |
| `api/app/models/integration_channel.rb:11` | name `LIKE` search | needs-test (collation/case behavior differs) | `IntegrationChannelTest#search_name_matches_channel_name_text` |
| `api/app/models/integration_team.rb:12` | name `LIKE` search | needs-test (collation/case behavior differs) | `IntegrationTeamTest#search_name_matches_team_name_text` |
| `api/app/models/project.rb:108` | project name `LIKE` search | needs-test (collation/case behavior differs) | `ProjectTest#search_by_matches_project_name_text` |
| `api/app/models/tag.rb:34` | tag name `LIKE` search | needs-test (pinned by `TagTest#test_0001_search_matches_tag_names_without_regard_to_casing`) | `TagTest#test_0001_search_matches_tag_names_without_regard_to_casing` |
| `api/app/models/post.rb:115-117` | title/name/username `LIKE` search | needs-test (collation/titleize semantics differ) | `PostTest#search_matches_title_text` |
| `api/app/controllers/admin/features/organization_searches_controller.rb:8` | `LIKE LOWER(?)` | needs-test (column normalization/collation behavior differs) | `Admin::Features::OrganizationSearchesControllerTest#matches_slug_prefixes_without_regard_to_case` |
| `api/app/controllers/admin/features/user_searches_controller.rb:8` | email `LIKE LOWER(?)` | needs-test (column normalization/collation behavior differs) | `Admin::Features::UserSearchesControllerTest#matches_email_prefixes_without_regard_to_case` |
| `api/app/controllers/api/v1/integrations/zapier/projects_controller.rb:18` | `LOWER(name) LIKE LOWER(?)` | portable (explicit case normalization) | Zapier project search test |
| `api/app/models/project.rb:152` | `SUM(EXP(-DATEDIFF(NOW(), created_at)/30))` | needs-test (MySQL date/math functions and score ordering) | `ProjectTest#recent_project_activity_returns_a_numeric_score_per_project` |
| `api/app/models/organization_membership_status.rb:16-17` | timestamp comparisons | portable (standard SQL) | — |
| `api/app/models/organization/invite_members.rb:42,50` | bound timestamp comparisons | portable (standard SQL) | — |
| `api/app/models/organization_invitation.rb:31` | wildcard search | needs-test (listed above) | `OrganizationInvitationTest#test_0001_search_by_matches_invitation_email_text` |

## Additional raw SQL call sites from the full source scan

| File:line | Construct | Verdict | Test name |
|---|---|---|---|
| `api/lib/backfills/call_rooms_source_and_creator_backfill.rb:8` | explicit inner join | portable (standard SQL join and equality) | — |
| `api/lib/backfills/call_recording_summary_section_backfill.rb:44` | bound timestamp predicate | portable (standard SQL) | — |
| `api/lib/backfills/dupe_views_backfill.rb:8` | `HAVING COUNT(1)` | portable (standard aggregate/filter) | — |
| `api/lib/backfills/project_view_backfill.rb:11,19` | correlated `NOT EXISTS` predicates | portable (standard SQL) | — |
| `api/lib/backfills/note_last_activity_at_backfill.rb:23` | NULL assignment | portable (standard SQL assignment) | `Backfills::NoteLastActivityAtBackfillTest#dry_run_is_a_no_op` |
| `api/lib/backfills/post_views_read_at_backfill.rb:9` | column-to-column update assignment | portable (standard SQL assignment) | — |
| `api/lib/backfills/call_recording_transcription_succeeded_at_backfill.rb:8` | column-to-column update assignment | portable (standard SQL assignment) | — |
| `api/lib/backfills/oauth_access_token_previous_token_backfill.rb:8` | column-to-column update assignment | portable (standard SQL assignment) | — |
| `api/lib/backfills/remove_closure_tree_backfill.rb:8,16` | NULL checks and boolean logic | portable (standard SQL predicates) | `Backfills::RemoveClosureTreeBackfillTest` parent/root assignment cases |
| `api/app/models/user.rb:280` | bound equality with OR | portable (standard SQL) | — |
| `api/app/models/user.rb:583` | suffix `LIKE` email-domain match | needs-test (collation and wildcard semantics) | `UserTest#likely_primary_work_organization` matching domain case |
| `api/app/models/project.rb:85,94` | `EXISTS` association subqueries | portable (Arel relation subqueries) | — |
| `api/app/models/project.rb:243` | timestamp comparison between joined relations | portable (standard SQL) | — |
| `api/app/models/post.rb:1035,1039,1043,1271,1273` | bound version/root predicates | portable (standard SQL) | — |
| `api/app/models/concerns/commentable.rb:28` | `MAX(comments.id)` aggregate | portable (standard SQL) | — |
| `api/app/models/concerns/pinnable.rb:14` | `MIN(public_id)` aggregate | portable (standard SQL) | — |
| `api/app/controllers/api/v1/organization_memberships/statuses_controller.rb:13` | `MAX(id)` aggregate | portable (standard SQL) | — |
| `api/app/models/message.rb:128` | `MAX(posts.id)` aggregate | portable (standard SQL) | — |
| `api/app/models/attachment.rb:146-152` | derived-table aggregate, group and alias order | needs-test (focused latest-commenters behavior pinned above) | `AttachmentTest#latest_commenters_returns_distinct_members_ordered_by_their_latest_comment` |
| `api/app/models/concerns/reactable.rb:15,20-22` | `MIN`, conditional `MAX`, count and JSON aggregate | fixed; covered above | `PostTest` grouped reaction and tooltip tests |
| `api/app/models/post.rb:901` | adapter-branched poll ID aggregation | fixed; covered above | `PostTest#viewer_voted` |
| `api/app/models/scheduled_notification.rb:33,36-71` | adapter-branch interval/time-zone SQL | fixed; covered above | `ScheduledNotificationTest#schedulable_in` contexts |
| `api/app/jobs/set_content_updated_at_job.rb:13-18` | adapter-branched JSON key predicates | fixed; covered above | `SetContentUpdatedAtJobTest` allowed/disallowed event cases |
| `api/app/jobs/call_health_job.rb:39-41` | adapter-branched elapsed-time calculation | fixed; covered above | `CallHealthJobTest` stuck processing cases |
| `api/lib/cursor_pagination.rb:32-41` | dynamic quoted column comparison/order | fixed; covered above | `CursorPaginationTest` nullable walk and invalid-column cases |
| `api/app/models/post_view.rb:96-100` | adapter-specific upsert conflict targeting | fixed; covered above | `PostViewTest#updating_the_same_member_and_post_in_separate_batches_keeps_one_view` |
| `api/app/models/notification_schedule.rb:18-65` | adapter-branched time-zone date/weekday SQL | fixed; covered above | `ApplyNotificationSchedulesTest` local-zone boundary case |

## Notes

- The source review searched `api/app` and `api/lib` for `Arel.sql`, raw SQL
  string arguments to `where`, `order`, `joins`, `select`, `group`, `having`,
  `pluck`, and update methods, as well as `find_by_sql` and direct `execute`.
  No `find_by_sql` or direct `execute` calls were found. Hash-based ActiveRecord
  predicates are excluded because they are not raw SQL fragments.
- Every `needs-test` row names a focused test. New Phase 1 MySQL pins were added
  for invitation, organization-membership, project, post-title, integration
  channel/team and admin search behavior; existing focused tests cover the
  comment, attachment, user grouping and backfill cases.
- Historical backfill SQL remains unchanged unless a Phase 1 task named the call site. The call-recording-speaker test confirms a known MySQL failure: the backfill references a column removed by migration `20240617181057_drop_call_recording_speakers_organization_membership_id`.
  This stale path needs a separate maintenance decision before PostgreSQL
  portability implementation.
- Lines are from this reviewed revision; adjust references if later edits move
  the call sites.
