# Patroni and etcd file-only rollout plan

This records the declaration at `config/deploy.campsite-pg.yml`; no cluster has been booted. The operator owns the steps below. The config contains a localhost web placeholder because Kamal requires a primary server. **Never run `kamal deploy` or `kamal setup` with this config.** Boot only the named accessories.

etcd is pinned to `quay.io/coreos/etcd:v3.6.15` at the OCI index digest resolved by `docker buildx imagetools inspect` on 2026-09-26. The [upstream release list](https://github.com/etcd-io/etcd/releases) identified v3.6.15 as the latest stable 3.6 patch at that check.

## Placement and network boundary

| Member | Host | Data directory | Listeners |
| --- | --- | --- | --- |
| etcd-a, pg-a | Groot 192.168.10.33 (Talokan) | `/srv/campsite-data/etcd`, `/srv/campsite-data/postgres` | 2379, 2380, 5432, 8008 |
| etcd-b, pg-b | pg-b 192.168.10.35 (Asgard) | `/srv/campsite-data/etcd`, `/srv/campsite-data/postgres` | 2379, 2380, 5432, 8008 |
| etcd-c | Quill 192.168.10.32 (Knowhere) | `/srv/campsite-runtime/etcd` | 2379, 2380 |

All listeners bind to the stated LAN addresses; PostgreSQL also binds to 127.0.0.1. etcd peer and client TLS are deferred. Plain HTTP is acceptable only while the UFW source allowlist below is enforced, the LAN remains trusted, and no public ingress or port forwarding exposes these ports. The cluster token is an environment secret, not transport authentication. Add TLS before broadening access beyond these three hosts.

Read-only UFW check on 2026-09-26: `sudo -n /usr/sbin/ufw status numbered` reported **active** on Groot and Quill. Groot had SSH rules, trusted-subnet Docker forwarding rules, and a 9100 rule from 192.168.10.12; Quill had SSH and trusted-subnet forwarding rules. Neither showed 2379, 2380, 5432, or 8008 inbound rules. pg-b is being provisioned; its UFW state is unverified. Recheck all three before mutation. Existing Docker forwarding rules do not replace host-input rules for host networking.

Exact inbound UFW allowlist to apply before boot (default deny inbound must be confirmed):

| Destination host | TCP destination ports | Allowed source IPs |
| --- | --- | --- |
| Groot 192.168.10.33 | 2379, 2380 | 192.168.10.33, 192.168.10.35, 192.168.10.32 |
| Groot 192.168.10.33 | 5432, 8008 | 192.168.10.33, 192.168.10.35, 192.168.10.32 |
| pg-b 192.168.10.35 | 2379, 2380 | 192.168.10.33, 192.168.10.35, 192.168.10.32 |
| pg-b 192.168.10.35 | 5432, 8008 | 192.168.10.33, 192.168.10.35, 192.168.10.32 |
| Quill 192.168.10.32 | 2379, 2380 | 192.168.10.33, 192.168.10.35, 192.168.10.32 |

Each row means one `sudo ufw allow in from <source IP> to <destination IP> port <port> proto tcp` rule for every listed source and port (12 rules each on Groot and pg-b, six on Quill). Do not add `Anywhere` rules. Quill has no PostgreSQL or Patroni listener, so no 5432/8008 rule belongs there. Apply on each destination through an approved host change, then read back `sudo ufw status numbered` and check the effective default inbound policy before boot.

## Operator rollout order

1. Build the reviewed commit locally for AMD64: `docker buildx build --platform linux/amd64 --load -t builder.home:5555/truemarkdev/campsite-postgres-ha:<git-sha> config/postgres`. Verify image architecture and render both archive modes. Push that exact tag only after operator approval. Replace `<git-sha>` in the config with the image's source commit SHA and rerender `kamal config -c config/deploy.campsite-pg.yml`.
2. Verify pg-b's data disk is mounted at `/srv/campsite-data/postgres`, verify all data directory ownership for the container UID, and apply/read back the UFW rules above on all three hosts. Ensure 5432 is free on Groot before boot; do not disturb MySQL.
3. Export the required secrets from the operator's approved secret source. Run `mise -E deploy exec -- script/check-campsite-kamal-secrets config/deploy.campsite-pg.yml`. Boot `etcd-a`, then `etcd-b`, then `etcd-c` using `mise -E deploy exec -- kamal accessory boot <name> -c config/deploy.campsite-pg.yml`. Verify `etcdctl --endpoints=http://192.168.10.33:2379,http://192.168.10.35:2379,http://192.168.10.32:2379 endpoint health --cluster` reports all three healthy and `member list` shows three members.
4. Boot `pg-a` with the same accessory command. Verify it is the leader with `patronictl -c /run/patroni/patroni.yml list` inside its container. Boot `pg-b` only after that check. Verify `patronictl list` shows exactly one leader and one **sync standby** and `SELECT pg_is_in_recovery()` is false on the leader and true on the standby. Confirm `SHOW archive_mode` returns `off`; pgBackRest is task 6.6.
5. Check port binding, memory, replication lag, app connection from the shadow environment, and a controlled switchover before accepting the cluster. This declaration alone does not prove any of those outcomes. Never restart the leader accessory without a planned switchover.

For shadow clients, use the multi-host libpq form `postgresql://<user>:<password>@192.168.10.33:5432,192.168.10.35:5432/campsite_production?target_session_attrs=read-write`. The operator supplies credentials through the shadow environment's secret source. Keep production `DATABASE_URL` unchanged until the separate cutover.

## Rollback

Stop and remove the five named accessories with the operator's Kamal accessory stop/remove commands in reverse order: `pg-b`, `pg-a`, `etcd-c`, `etcd-b`, `etcd-a`. Verify containers and listeners are gone. Retain Groot's PostgreSQL and etcd data pending diagnosis; delete data directories **only on pg-b**, and only after confirming their exact mount and rollback need. Never touch Groot's MySQL data or production `DATABASE_URL`. UFW rule removal is a separately reviewed host change after all listeners are stopped.

## As-built rollout, 2026-09-26

- `pg-b` guest (task 6.2): created on `asgard` with `scripts/provision_guest_vm.sh` from the homelab
  `campsite-pg-b-vm` branch (state `/root/pg-b-install.eAsRlj`). 2 vCPU, fixed 2 GiB, 20 GiB root,
  40 GiB data mounted at `/srv/campsite-data` (ext4, UUID, `nofail`), Debian 13, cloud-init done,
  `192.168.10.35` (static fallback; the router reservation is still pending). Homelab guest baseline applied
  (Docker CE, UFW, fail2ban, unattended security upgrades): ok=34, failed=0.
- Registry: `insecure-registries: [builder.home:5555]` on Groot and pg-b, applied with `systemctl reload
  docker` (no container restart; Groot MySQL/Redis stayed up). The builder's UFW allows pg-b on 5555 (in) and 5000 (route).
- UFW cluster allowlist applied: Groot 12, pg-b 12 and Quill 6 rules; default deny inbound on all three.
- Secrets: `PATRONI_SUPERUSER_PASSWORD`, `PATRONI_REPLICATION_PASSWORD` and `ETCD_CLUSTER_TOKEN` were
  generated into `mise.deploy.toml` (never printed); the file is now mode 600.
- Image (task 6.3): `builder.home:5555/truemarkdev/campsite-postgres-ha:9e3184dcc0b566e5d66ece6e13d087fd2017abe5`.
  Two defects were found at boot and fixed: `python3-etcd3` → `python3-etcd` (Patroni found no etcd DCS), and
  `PATRONI_ETCD_HOSTS` → `PATRONI_ETCD3_HOSTS` (the native v2 variable overrode the etcd3 section; etcd 3.6
  has no v2 API). Also added: pg_hba (replication from the members, scram clients from the members and Quill).
- etcd (task 6.4): etcd-a (Groot), etcd-b (pg-b) and etcd-c (Quill) are all `started` and healthy.
- Patroni (task 6.4): cluster `campsite` (system id 7689903181580402721) has `pg-a` Leader and `pg-b` **Sync
  Standby**, streaming, lag 0. `/primary` returns 200 on pg-a; `/sync` returns 200 and `/primary` returns 503 on pg-b.
  WAL archiving is off until task 6.6.
- All `kamal accessory` commands for this config need `--hosts <accessory host>`; without it, Kamal
  tries the `127.0.0.1` placeholder server and fails.
- camp.home api/auth/sync returned 200 throughout; MySQL/Redis on Groot were untouched.

Follow-ups from this rollout, all closed on 2026-09-26 (UTC) in the next section: dedicated postgres
UID, pg-b DHCP reservation, failover/switchover drills (task 6.9), pgBackRest (task 6.6).

## Dedicated UID, pgBackRest and drills, 2026-09-26 (UTC)

### Image and UID

- Image `builder.home:5555/truemarkdev/campsite-postgres-ha:1b6c08c1eb4a99c4cb0387c401a5c0865d6a581a`
  (built by `kamal build push` on the remote builder). `postgres` is uid/gid **5432**; no file in the image
  is owned by 999; `patroni 4.1.5`, `pgBackRest 2.59.1`, PostgreSQL 18.6.
- Rolled one member at a time: stop accessory → `chown -R 5432:5432 /srv/campsite-data/postgres` (only that
  directory; Groot's `mysql` and `redis` directories stay 999) → `kamal accessory reboot`. The replica went
  first, then a switchover, then the former leader. `docker exec … id -u` returns 5432 on both members.
  Groot MySQL and Redis stayed healthy throughout.

### pgBackRest (task 6.6)

- Repository: `vyas:/volume1/shared/backups/campsite/pgbackrest` (mode 0750, owner 5432:5432). This is the
  as-built namespace named in `docs/deployment/homelab-production.md`; D11's `starkdrive:/volume1/backups/…`
  predates the NAS rename. `backups/campsite/` was changed from 0700 to 0711 so uid 5432 can traverse it;
  uid 5432 cannot list or read the sibling `mysql/` dumps.
- Hosts: homelab `ansible/setup_shared_mount.yml` mounts `vyas:/volume1/shared` at `/mnt/starkdrive-shared`
  on Groot and pg-b (NFSv3, soft, systemd automount, no idle timeout). The accessories bind it with `rslave`
  propagation, so a NAS outage stalls archiving rather than preventing PostgreSQL from starting.
- Configuration is `PGBACKREST_*` accessory env (stanza `campsite`, `repo1-retention-full=5`, zstd,
  `process-max=2`, `start-fast`); `/etc/pgbackrest.conf` is empty in the image. `archive_mode=on`,
  `archive_command=pgbackrest --stanza=campsite archive-push %p`, and `restore_command=… archive-get %f "%p"`
  on both members.
- `stanza-create` on the leader, then the first full backup `20260926-182326F` (database 30.3 MB, repo
  3.6 MB) and a differential. `pgbackrest check` passed on **pg-b while leader** and on **pg-a while leader**
  (after the power-off failover). On a standby, `check` fails with `[027] primary database not found`
  because no `pg2-host` path between members exists (by design; there is no SSH/TLS between members).
  Standby readiness was shown instead by `pgbackrest info` (status ok) and `archive-get` of a 16 MiB segment.
- Schedule: homelab `ansible/setup_campsite_pgbackrest.yml` installs `campsite-pgbackrest-full.timer`
  (Sun 01:30 local) and `campsite-pgbackrest-diff.timer` (Mon–Sat 01:30) on **both** hosts. Each run exits 0
  unless Patroni `/primary` answers 200 on that member. Verified: Groot's run logged
  `campsite-pg-a is not the Patroni leader; skipping diff backup`; pg-b's run took a differential.
- ⚠️ Archive failure alerting and backup-age alerting are task 6.8 and do not exist yet. A soft-mount
  failure currently shows only in `pg_stat_archiver.failed_count`. Before the stanza existed, six archive
  attempts of `00000002.history` failed and then succeeded.
- The homelab playbooks above are committed in homelab `ee4b1c1` (see below).

### Drills (task 6.9, empty cluster plus synthetic writes)

Method: a probe container on Quill (the application host) inserted one row every ~250 ms into a throwaway
`drill` database through `postgresql://drill@192.168.10.33:5432,192.168.10.35:5432/drill?target_session_attrs=read-write&connect_timeout=2`,
with a 3 s client timeout, logging epoch-ms, outcome and `inet_server_addr()`. Gaps are the time between
consecutive successful inserts (every gap over 1 s is listed). The probe, its password file, the `drill`
database and the role were removed afterwards. The repeat on rehearsal data is part of the shadow run
(design step 5, SyR-PG-10).

| Drill (UTC) | Requirement | Action | Write gap | Outcome |
| --- | --- | --- | --- | --- |
| 18:20 replica stopped (graceful) | SyR-HA-4 | `kamal accessory stop pg-b` | none over 1 s (max 385 ms) | leader kept serving; 0 failures |
| 18:21:43 planned switchover | SyR-HA-2 (≤30 s) | `patronictl switchover --leader pg-a --candidate pg-b` | **2.1 s**, 6 failed attempts | pg-b leader TL2; pg-a rejoined as sync standby; client followed without a config change |
| 18:22 replica stopped (graceful) | SyR-HA-4 | `kamal accessory stop pg-a` (UID roll) | none over 1 s (max 575 ms) | 0 failures |
| 18:25:52 hard power-off of leader VM | SyR-HA-2 (≤60 s) | `xe vm-shutdown force=true` for pg-b on asgard | **28.1 s**, 13 failed attempts | pg-a promoted TL3; etcd 2/3 kept quorum; after `xe vm-start`, pg-b ran `pg_rewind` and rejoined as sync standby ~78 s after boot; data mount, DHCP `.35`, NFS mount and etcd-b all came back |
| 18:28:35 etcd minority lost | SyR-HA-1 | `docker stop campsite-etcd-c` (Quill) for ~57 s | none over 1 s (max 474 ms) | no leader change; Patroni logged connection errors to `.32:2379` and used the other two members; etcd-c rejoined healthy |
| 18:29:52 sync standby killed | SyR-HA-4 | `docker kill campsite-pg-b` | **6.8 s** stall, 2 timed-out inserts | commits waited for the dead sync standby until Patroni dropped it from `synchronous_standby_names`; then the leader served alone; pg-b rejoined as sync standby after `docker start` |

Totals: 2214 acknowledged inserts and 22 failures; the table held 2219 rows (five commits whose
acknowledgement was lost to the client timeout). That is a count-level check that no acknowledged commit
was lost across three leader changes. It is not a per-row proof. Archiving continued across the failover:
timeline 3 segment `000000030000000000000009` archived from pg-a.

Observations:
- The first full backup and its `check` (18:23:26–41) caused 2.6–3.6 s insert-latency gaps and one timed-out
  insert on the 2 vCPU / 2 GiB pg-b. Scheduled backups run at 01:30. Consider `process-max=1` if this shows
  under shadow load.
- Not exercised: loss of the etcd **majority** (SyR-HA-1: the leader must stop accepting writes), and an
  alert on each leader change (SyR-HA-2; alerts are task 6.8).

### Router and DNS

UDR7 reservation `02:16:3e:10:4b:0b` → `192.168.10.35` (`scripts/unifi_reserve_client.sh --outside-pool`,
read back exactly); pg-b now holds `.35` as its DHCP lease and the stray `.17` lease is gone. AdGuard exact
rewrite `pg-b.home` → `192.168.10.35` (`ansible/deploy_heimdall_home_dns.yml`).

### Homelab repository state

✅ Committed as homelab `ee4b1c1` on branch `campsite-pg-b` (worktree
`~/workspaces/2026/homelab-wt-campsite-pg-b`, based on `complete-homelab-platform-lifecycle` 231fe8a; not
pushed or merged). It carries the pg-b provisioning files, the `--outside-pool` reservation change, the
`pg-b.home` rewrite, the Groot/pg-b NFS mount and the backup-timer playbook.

The earlier commit attempt failed because `tests/test_update_lifecycle.py` runs `git init/add/commit` in
temporary directories. Under the pre-commit hook those commands inherited `GIT_DIR`/`GIT_INDEX_FILE`, so
they set `core.bare=true` on the real repository and committed into the `campsite-pg-b-vm` worktree. The
same commit now strips git's environment from the lefthook python-tests job. The damaged
`homelab-wt-campsite-pg-b-vm` worktree (branch `campsite-pg-b-vm`) is superseded and left for the operator to remove.
