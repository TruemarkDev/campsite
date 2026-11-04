# Task 5.1: case-only identity duplicate audit (camp.home MySQL)

Run 2026-09-24, read-only, through `bin/rails runner` in the running
`campsite-api-staging-web` container on Quill against `campsite_production`
(schema `20260828134500`). Counts only; no values were read out.

| Check | Groups/rows |
|---|---:|
| `users.email` case-only duplicate groups | 0 |
| `users.username` case-only duplicate groups | 0 |
| `organizations.slug` case-only duplicate groups | 0 |
| `organization_invitations (organization_id, email)` case-only duplicate groups | 0 |
| `email_bounces.email` case-only duplicate groups | 0 |
| `users.email` values not already lower-case | 0 |
| `organization_invitations.email` values not already lower-case | 0 |

Result: the D2 `citext` conversion cannot introduce a uniqueness collision on
current data. Re-run immediately before cutover (task 8.1).
