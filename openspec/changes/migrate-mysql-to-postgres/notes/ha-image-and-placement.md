# Patroni image and recorded homelab placement

## Image (task 6.3)

The local `campsite-postgres-ha:spike` image uses `postgres:18` at OCI index digest `sha256:86c951e05bf56c93d95d397747fb8820ac76cc3bedb78f43abd83eedbe3666ae` (resolved with `docker buildx imagetools inspect postgres:18` on 2026-09-24). Its Dockerfile installs Patroni, the `python3-etcd3` extra, and pgBackRest from the signed PGDG `trixie-pgdg` apt repository. The template implements the synchronous non-strict policy, lag threshold, and timing values from `openspec/changes/migrate-mysql-to-postgres/design.md:197-210`, and uses the leader-side pgBackRest archive command described at `design.md:245-248`. Deployment wiring, an etcd cluster, a backup repository configuration, and failover drills remain unbuilt.

Local build: `docker build -t campsite-postgres-ha:spike config/postgres` succeeded on 2026-09-24 (ARM64). Inside that image, `patroni --version` reported `patroni 4.1.5`; `pgbackrest version` reported `pgBackRest 2.59.1`; `postgres --version` reported `postgres (PostgreSQL) 18.6 (Debian 18.6-1.pgdg13+2)`. The installed package versions were PGDG `patroni 4.1.5-1.pgdg13+1`, PGDG `pgbackrest 2.59.1-1.pgdg13+1`, and Debian `python3-etcd3 0.12.0-3`. These are the newest candidate versions resolved by apt from the configured repositories at build time; a future rebuild can select newer packages.

Runtime template variables must be supplied by the operator. Passwords are required environment inputs and the rendered Patroni config is written with mode 0600. No credentials are present in the image source. A smoke run with dummy inputs rendered the template and returned `patroni 4.1.5`. That verifies rendering, not database startup, replication, or backup behavior. The local build and smoke run used ARM64. An AMD64 build (`docker buildx build --platform linux/amd64`, emulated, 2026-09-24) also succeeded; under `x86_64` it reported `patroni 4.1.5`, `pgBackRest 2.59.1` and `postgres (PostgreSQL) 18.6 (Debian 18.6-1.pgdg13+2)`. Startup, replication and backups on the homelab hosts remain unverified.

## Placement and memory (task 6.1, file-only review)

The 2026-09-22 evidence is a captured XAPI readback, not a current host observation (`docs/k3s-capacity-record.md:3-7`; raw evidence `evidence/k3s-capacity-2026-09-22.json:2-8`). Paths in this section are relative to `/Users/prakash/workspaces/2026/homelab/`.

| Guest or host | Recorded placement | Evidence |
| --- | --- | --- |
| Quill | `knowhere` host, Asgard two-host pool | `evidence/k3s-capacity-2026-09-22.json:6-8,33-48`; `ansible/inventory/homelab.yml:144-149` identifies the guest but does not pin its host |
| Groot | `talokan` host, single-host vibranium pool | `evidence/k3s-capacity-2026-09-22.json:6-8,61-66,83-85`; `ansible/inventory/homelab.yml:175-184,480-495` |
| Mantis | `talokan` host, single-host vibranium pool | `evidence/k3s-capacity-2026-09-22.json:6-8,61-76`; `ansible/inventory/homelab.yml:175-184,480-495` |
| Vyas | Synology NAS outside the listed XCP-ng guest inventory; no pool/host placement is evidenced for its hardware | `ansible/inventory/homelab.yml:504-510,512-529`; raw evidence `:6-8` lists XCP-ng pools only; `:53-54` names a storage repository `vyas-xcpng`, not a Vyas VM |

Recorded host free memory: `talokan` 3.46 GiB, `asgard` 7.57 GiB, `knowhere` about 0.01 GiB (`docs/k3s-capacity-record.md:9-15`; raw evidence `evidence/k3s-capacity-2026-09-22.json:12-17,34-39,61-66`). After the record's 2 GiB host reserve, the figures are 1.46 GiB, 5.57 GiB, and 0 GiB respectively (`docs/k3s-capacity-record.md:11-15`). Talokan's accepted overcommit policy admits against its 7.46 GiB free-plus-balloonable pool, while Asgard is evaluated against free memory (`docs/k3s-capacity-record.md:17-28,47-50`).

**Admission from this snapshot:** A hypothetical extra 1 GiB `pg-a` plus ~1.3 GiB shadow API/web placed on Talokan totals ~2.3 GiB. That exceeds Talokan's 1.46 GiB reserve-adjusted free memory by ~0.84 GiB, but is below its 7.46 GiB squeezable pool under the recorded overcommit policy (capacity record lines 11–15,17–28,47–50; plan `design.md:292-296`). This does **not** establish the proposed placement: Quill, the planned application host, is recorded on Knowhere, which has effectively no free host memory, although Quill itself has a 1–4 GiB dynamic allocation range (raw evidence `:34-48`). Whether ~1.3 GiB fits inside Quill depends on current guest/container use and ballooning targets, which were not captured (capacity record lines 127–133). `pg-a` also needs a current Groot guest-level check (raw evidence `:83-85`).

A 2 GiB `pg-b` fits the recorded **asgard host** free-after-reserve figure of 5.57 GiB, leaving 3.57 GiB on that host. It does not fit Knowhere's 0 GiB after reserve; the Asgard pool has two hosts, so placement must pin or admit against the actual host (capacity record lines 11–15,78–81; raw evidence `:6-8,12-17,34-39`; plan `design.md:201-203`).

**Drift and limits:** The inventory's Talokan resident list omits Groot and Mantis and includes a guest absent from the observed list (capacity record lines 83–87; inventory lines 491–495). The proposal assumes Quill is on Talokan (`design.md:212-214`), contradicted by the captured evidence (`evidence/...json:33-48`). The capacity record says live admission is blocked pending fresh host readback and notes missing Talokan per-guest actual/target memory (capacity record lines 115–118,127–133). This file review does not satisfy a live capacity admission or alter the homelab inventory.

## Open questions

- Where is Quill now, and how much memory is available inside Quill and Groot for the shadow run? Recheck before any placement decision (raw evidence `:33-48,83-85`; capacity record lines 115–118,127–133).
- What explicit `maximum_lag_on_failover` byte threshold and pgBackRest stanza/repository settings will the operator choose? D10 requires a bound but gives no value (`design.md:205-210`); D11 names the repository and retention but its configuration is later work (`design.md:245-268`; `tasks.md:49`).
- Is Vyas an acceptable always-on third failure domain and etcd witness host? D10 proposes it but leaves witness placement open (`design.md:201-203,344-345`).
