# Execution tracking

Beads is authoritative for status, dependencies and completion. This file is
an index, not a duplicate checklist. Requirements live in
`specs/homelab-ci-images/spec.md`; implementation choices live in `design.md`.

| Bead | Scope |
| --- | --- |
| campsite-7e3 | Overall delivery and acceptance |
| campsite-7e3.1 | Proposal, design and requirements |
| campsite-7e3.2 | Homelab image sources and candidate builds |
| campsite-7e3.3 | Latest stable Campsite Ruby/Node migration |
| campsite-7e3.4 | Campsite workflow integration and reviewdog |
| campsite-7e3.5 | Cache design and measured performance |
| campsite-7e3.6 | Authorized publication, canary, promotion and rollback |

Existing `campsite-jc3`, `campsite-7b6` and `campsite-au5` retain their own
scope; consult them rather than creating duplicate repair tasks.
