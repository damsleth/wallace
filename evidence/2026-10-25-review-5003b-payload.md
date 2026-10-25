# Exact-artifact re-review: 5003b exFAT write payload (ticket 211 stage 1 retry) — PASS-with-notes

Date: 2026-10-25. Reviewer: claude (Mythos Wallace session), offline, host
only; nothing edited. Requested by Opus Wallace. Supersedes
`evidence/2026-10-25-review-5003-payload-exact.md` for the initramfs only.
Payload: `~/Code/linux-build-out/nvme-exfat-write-20261025b/payload/`.

## Verdict

**PASS-with-notes.** Image, System.map, config, DTB, `m1n1.bin` and
`m1n1-raw.elf` are byte-identical to the files I passed this morning. The
only change is the initramfs (`42a5e48f…`, two builds identical), whose
`/init` is byte-identical to `scripts/t6040-init-nvme-exfat-write` at
HEAD (`f8aec6e`). The three init changes are correct and do not widen the
write surface; the field-wise boot-sector pins match the 5001 dump byte for
byte. One bookkeeping must-do before the run (ticket 5003's pins and the
launcher default still point at the old payload) and four notes.

## 1. Hashes

`shasum -c SHA256SUMS` from `linux-build-out/`: all seven `OK`.

| File | sha256 | Status |
|---|---|---|
| Image | `4fadb8d3…` | unchanged (cmp) vs the reviewed 20261025 payload |
| System.map | `48f2d81d…` | unchanged |
| config | `1b19daba…` | unchanged |
| initramfs.cpio.gz | `42a5e48f0b4c6461…` | **new**; `initramfs-write-a == -b == payload` (cmp) |
| m1n1.bin | `7de07c71…` | unchanged |
| m1n1-raw.elf | `5bee616c…` | unchanged |
| t6040-nvme.dtb | `a96d04a7…` | unchanged |

Initramfs contents: `/init` `254b8f1d…` = repo script at HEAD (`cmp`
identical, `git diff HEAD` clean); `bin/busybox` `61781806…` and
`sbin/fsck.exfat` `d56b877d…` unchanged; keymap present. The build
manifest (`initramfs-write-a.cpio.json`) records the same init hash and the
sdroot-hardened base `4cc65133…`.

## 2. The init changes (`a845615` → `f8aec6e`)

**(a) `nvmewritedir=TAG`.** Parsed from the cmdline, validated to
`[a-z0-9]` (anything else stops before the gates), and used as
`wallace-write-test-TAG`. The `write` refusal when the directory exists is
unchanged; nothing deletes. Correct.

**(b) `nvmewc=through`.** Only the literal `through` is accepted. Before
the rw mount it writes `write through` to
`/sys/block/nvme0n1/queue/write_cache` (a sysfs attribute of the request
queue, not a disk write), reads it back, and stops unless the readback is
`write through`. The resulting mode is logged as
`dir=… write_cache=… fua=…` and carried into the PASS line
(`write_cache=back|through`, the `${WCNOW#write }` form, which the flow test
confirmed after the earlier `% *` bug). Effect: the block layer stops
issuing PREFLUSH/FUA, so the exFAT boot-sector and `fsync` writes that
failed in run 1 no longer carry a Flush. Correct; see note 2 for what it
costs.

**(c) Field-wise boot-sector pins.** Replaces the whole-sector hash (which
the first rw mount invalidates by updating VolumeFlags/PercentInUse). The
script pins bytes 64..105, 108..111 and 510..511. Checked against the 5001
console transcript line
`NVME-P3ID exfat nvme0n1p3 bootsector[64..119]: 00ced20b00000000008ea80200000000 00010000000600000007000038441500 05000000af2cdd6a000100000c050180 0000…`:

| Pin | Bytes | Dump | Decoded |
|---|---|---|---|
| `00ced20b00000000 008ea80200000000 00010000 00060000 00070000 38441500 05000000 af2cdd6a 0001` | 64..105 (42 B) | identical | PartitionOffset 198,364,672 (= GPT first LBA), VolumeLength 44,600,832 (= GPT size), FatOffset 256, FatLength 1536, ClusterHeapOffset 1792, ClusterCount 1,393,720, RootCluster 5, serial `0x6add2caf`, revision 1.00 |
| skipped | 106..107 | `0000` | VolumeFlags — driver-written, correctly excluded |
| `0c050180` | 108..111 | identical | BytesPerSectorShift 12 (4 KiB), SectorsPerClusterShift 5 (128 KiB), 1 FAT, DriveSelect 0x80 |
| skipped | 112 | `00` | PercentInUse — driver-written, correctly excluded |
| `55aa` | 510..511 | outside the dump range; mandatory exFAT signature (a mismatch stops, never writes) | |

Internal consistency, recomputed: `(VolumeLength − ClusterHeapOffset) / 32
= 1,393,720 = ClusterCount`; FAT needs 5,574,888 bytes and has 6,291,456;
root-directory offset `(1792 + 3·32) · 4096 = 7,733,248` is the existing
label pin. The pins describe one specific volume, not merely "an exFAT".

## 3. Write surface (unchanged from the first review)

Every raw access to `/dev/nvme0n1` and `$DEV` outside the mount is `dd if=`;
p1/p2/p4/n2/n3 are `setro` before the first gate; `fsck.exfat -n` only on
the unmounted device; the only writers are the exfat driver through p3's
bdev and the sysfs attribute in (b). The disk-vs-p3 written-sector equality
and the `others()` stat hash still bound the run. No change to `fsck`,
mount options (no `discard`), or the hash/verify flow.

Checker (`t6040-check-nvme-write-transcript.py`): additionally requires
exactly one `NVME-WRITE dir=… write_cache=(write back|write through) fua=…`
line and reports it. The PASS regex is a prefix match, so the appended
`write_cache=` field is accepted. Launcher (`t6040-run-nvme-write.sh`):
`PAYLOAD=` and `WRITE_ARGS=` are honoured, `SHA256SUMS` is checked before
boot, the 300 s post-handoff deadline and DebugUSB reboot are unchanged.
Flow regression (`evidence/2026-10-25-t6040-5003b-write-init-flow-test/`):
five cases pass on a 4 KiB-sector loop GPT with the 5003b initramfs's own
BusyBox and `fsck.exfat`; the pins themselves are device-only and cannot be
exercised there.

## Must-do before "ready" (bookkeeping, not payload)

Ticket 5003's `hashes` still carry `initramfs.cpio.gz dccf3de9…` and
`payload_dir …/nvme-exfat-write-20261025/payload`, and the launcher's
`PAYLOAD` default is that old directory. Re-pin the ticket to
`nvme-exfat-write-20261025b/payload` with initramfs `42a5e48f…` and this
review, and run with `PAYLOAD=nvme-exfat-write-20261025b/payload` (or flip
the default), so the `SHA256SUMS` check guards the right payload.

## Notes

1. **Same TAG on verify.** `verify` recomputes `D` from `nvmewritedir`, so
   the verify boot must pass the same `nvmewritedir=TAG` as the write boot
   or it stops with `test file missing` (safe, but a wasted cycle). The
   checker does not cross-check the two runs' `dir=` lines; the run evidence
   should quote both.
2. **What `nvmewc=through` trades.** With no Flush the controller's volatile
   cache is never explicitly committed; a hard reset (`macvdmtool reboot`,
   no NVMe shutdown) can drop cached data and leave p3's exFAT dirty or the
   test file short. That is confined to p3 and recoverable (`fsck.exfat` /
   macOS repair), and it is exactly what the verify-after-reset run measures;
   just do not read a verify STOP as a transport bug before checking
   `fsck.exfat -n (before)` in the verify transcript. `write_cache` on the
   NVMe queue affects only `nvme0n1`'s request queue; n2/n3 queues keep
   their own setting and stay read-only anyway.
3. `sbin/nvme-readonly-test` (`aef24ab9…`, the reviewed 6001 copy) is
   still carried and still unused.
4. The flow test cannot exercise the write-back branch (loop devices report
   `write through`); on hardware the default (no `nvmewc`) path is the
   run-1 path, which only makes sense once 5006 shows Flush is accepted.

## Commands run

```text
cd linux-build-out && shasum -a 256 -c nvme-exfat-write-20261025b/payload/SHA256SUMS
cmp each of Image/System.map/config/m1n1.bin/m1n1-raw.elf/t6040-nvme.dtb against nvme-exfat-write-20261025/payload/
cmp initramfs-write-a.cpio.gz initramfs-write-b.cpio.gz payload/initramfs.cpio.gz
gzip -dc initramfs.cpio.gz | cpio -idm; cmp ./init scripts/t6040-init-nvme-exfat-write; shasum -a 256 init bin/busybox sbin/fsck.exfat
git diff a845615 HEAD -- scripts/t6040-init-nvme-exfat-write scripts/t6040-check-nvme-write-transcript.py; cat scripts/t6040-run-nvme-write.sh
grep bootsector nvme-p3id-20261024/runs/run1/t6040-console-20261025-claude-5001-run1.log; python3 struct decode of the 42-byte pin
```
