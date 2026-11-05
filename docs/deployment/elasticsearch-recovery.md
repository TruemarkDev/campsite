# Elasticsearch durability and recovery

## Current configuration

Elasticsearch runs on `prakash@192.168.10.26`, a Vyas VMM guest. Its 60 GiB
disk is LUN `004a5c5a-0041-41cf-b28f-46c14f564b71`, owned by guest
`f38c0d78-90e8-4384-b72c-873cc144c4dc`. On September 12, 2026, the native
Synology LUN API enabled `emulate_sync_cache=1`, retaining
`emulate_fua_write=1`. Both the saved API configuration and live kernel
attributes were verified, including after a graceful VM stop/start and disk
reattachment. Eight disposable 1 MiB files retained their SHA256 checksums.
Guest tracing observed 17 SCSI cache-flush commands and 18 FUA writes during
the test. Physical drive cache settings were not changed.

The supported API operation used by the installed SAN Manager interface is:

```bash
# Run on Vyas as prakash. This changes only the identified LUN.
sudo -n /usr/syno/bin/synowebapi -s --exec \
  api=SYNO.Core.ISCSI.LUN method=set version=1 \
  'uuid="004a5c5a-0041-41cf-b28f-46c14f564b71"' \
  'dev_attribs=[{"dev_attrib":"emulate_fua_write","enable":1},{"dev_attrib":"emulate_sync_cache","enable":1}]'
```

Rollback uses the same operation with `emulate_sync_cache` set to `0`; this
restores the previous durability risk. Do not change shared drive caches,
LUN size, NOCOW attributes, or other guests as part of this operation.

🟡 Abrupt physical power-loss durability has not been demonstrated. Successful
flush commands and a graceful restart cannot establish that guarantee.

## Search verification

Run `bash script/check-campsite-search`. It selects exactly one running staging
API on Odin, checks authenticated green cluster health, compares the three
indices with `search_import`, and searches for existing posts and notes without
printing their contents. Counts may briefly differ during concurrent writes;
investigate persistent differences before rebuilding.

## Monitoring

The existing Uptime Kuma service on Heimdall (`192.168.10.8`) is the monitoring
source. Two monitors were installed and observed Up on September 12, 2026:

- [Listener availability](http://kuma.home/dashboard/13): TCP port 9201.
- [Authenticated cluster health](http://kuma.home/dashboard/14): HTTP JSON
  query `status == green` against `/_cluster/health`.

Both check every 60 seconds, retry twice, and use the existing Homelab mail
(Stalwart) notification. Delivery of a failure email was not separately tested.
The cluster monitor stores a dedicated `campsite-kuma-cluster-health` API key
in Kuma's monitor configuration. It has only cluster `monitor` privileges and
no index privileges: health returned HTTP 200 and a search attempt returned
HTTP 403. Never copy the key into this repository. A fresh Elasticsearch
cluster rebuild requires re-creating this key and updating the monitor header.
Removing the monitor and invalidating its named API key reverses this setup.

The guest has a scoped persistent UFW forwarding rule allowing only
that source to `172.18.0.2:9200`, the current Elasticsearch container address
after Docker port translation from guest port 9201. Recheck this address if
the Docker network or container allocation changes. The rule can be removed
with `sudo -n ufw route delete allow proto tcp from 192.168.10.8 to 172.18.0.2 port 9200`.

The verification stop/start preserved the Elasticsearch cluster UUID
`v_kmpXJkRea1iOn_i_OVbw`. All six primary shards became active with no unassigned
shards. Post/Note/Call index counts were 767/68/0, matching MySQL, and existing
post/note searches passed. The staging worker was resumed. Cold startup took
several minutes with substantial guest I/O wait; no startup performance target
or abrupt-power-loss guarantee is established by this test.

## Recovery procedure

1. Inspect the exact Elasticsearch container, image, mounts, health, and logs.
   Check VM/NAS shutdown history and storage state before changing anything.
2. If data is unreadable, stop Elasticsearch gracefully and preserve the entire
   cold data directory separately. Never delete individual Lucene state files
   or carry out filesystem repair on a mounted filesystem.
3. Follow the authoritative rebuild procedure in
   [homelab-production.md](../reviews/homelab-platform-history.md#elasticsearch-95-migration--deployed-2026-08-28).
   Pause the staging worker during the bounded rebuild and resume it afterward.
   Preserve the old storage while initializing fresh search storage.
4. Apply `config/elasticsearch/staging-index-template.json` before reindexing.
   Reindex `Post`, `Note`, and `Call` from the live database; allow enough time
   for index creation on the VM. Keep longer recovery timeouts local to the
   recovery process.
5. Run the search check, verify worker connectivity, and check restart growth.

The September 12 incident's original data remains on the guest at
`/var/lib/campsite-recovery/2026-09-12-elasticsearch-data`. This is forensic
evidence, not a supported Elasticsearch snapshot backup. The retained
`_state/segments_1nk` SHA256 is
`8dc6976cdcc594b49c1a7f1aac9acc8c9e0e6dbe84aa6a0db6cce05f83261960`.

Investigation and verification evidence are tracked in Beads
`campsite-d5w.4.2.1` and `campsite-d5w.4.2.2`; those records own outstanding work.

References: [Synology LUN settings](https://kb.synology.com/en-nz/PAS/help/ScsiTarget/lun),
[Elastic corruption troubleshooting](https://www.elastic.co/docs/troubleshoot/elasticsearch/corruption-troubleshooting),
[Btrfs scrub limitations](https://btrfs.readthedocs.io/en/latest/btrfs-scrub.html).
