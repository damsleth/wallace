# Independent review: `t6040-init-nvme-exfat-write` (1d67ddc), tickets 211/5003

Reviewer: sonnet, offline, 2026-10-25. No rig, lease, boot or build. Nothing
reviewed was edited. This is the first script that writes to the internal SSD,
so I checked every pin from raw bytes in the 5001 transcript, not from the
evidence prose.

**Verdict on the script: PASS-with-notes.** Every pin is correct and the flow
works. **The payload is not ready**: the kernel it needs does not exist yet and
the host-side stop/checker is missing (must-fix 1 and 2).

## Artifacts (recomputed)

```text
464bc9c3783606a402bdd3bda2773092e3f8b0179904eb425c537b3305ca9733  scripts/t6040-init-nvme-exfat-write (= /init in the initramfs)
67645b86c457ebbf…  nvme-exfat-write-20261025/initramfs-write-{a,b}.cpio.gz (identical)
d56b877d91e8e42a…  embedded sbin/fsck.exfat (exfatprogs 1.2.0; runs);  61781806…  embedded busybox
```

`nvme-exfat-write-20261025/payload/` is **empty**: no Image, DTB, m1n1 or manifest.

## Pins checked against the 5001 transcript (`d6dd8a14…`, operator-shell GPT dump)

| Pin in script | Source | Result |
|---|---|---|
| p3 sysfs start 1586917376 / size 356806656 | probe line `part nvme0n1p3 start=… size=…` | ✓ |
| LBS 4096 | operator shell `logical_block_size` = 4096 | ✓ |
| GPT entry array at byte `2*LBS` + slot 2 × 128 = 8448 | header `entries LBA = 2`, 128 entries × 128 B; entry2 is p3 | ✓ |
| type `a2a0d0ebe5b9334487c068b6b72699c7` | entry2 bytes 0–15 | ✓ (= EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, mixed-endian) |
| unique `dba60dea3529cb49a996b982dd646f24` | entry2 bytes 16–31 | ✓ (= EA0DA6DB-2935-49CB-A996-B982DD646F24) |
| LBAs `00ced20b00000000 ff5b7b0e00000000` | entry2 bytes 32–47 | ✓ (198,364,672 / 242,965,503; ×8 = sysfs start; (last−first+1)×8 = size) |
| exFAT `EXFAT   ` at 3, serial bytes `af2cdd6a` at 100 | probe boot-sector hex | ✓ (0x6add2caf) |
| root dir offset 7733248 | (heap 1792 + (5−2)<<5) << 12 = 1888 × 4096 | ✓ recomputed |
| label `83056c0069006e0075007800` at that offset | probe `rootdir[0..127]` | ✓ |
| ns sizes 1954210120 / 6144 / 262144, transport/model | 6001 run 3 and probe | ✓ |
| p1, p2, p4 are the others; no p5 | probe lists p1 iBootSystemContainer, p2 APFS (no name), p4 RecoveryOSContainer | ✓ |

Cross-checks the script does not make but I did: boot-sector PartitionOffset
(198,364,672) and VolumeLength (44,600,832 sectors) equal the GPT range; the
partition ends 376 sectors before p4 and the namespace ends 40 sectors after p4
(backup GPT), so p3's range overlaps nothing.

## What I ran

My own harness (`evidence/2026-10-25-review-5003-exfat-write-test/`; the author's
`run.sh` sources a `/t/flow.sh` that is not in the repo and saved no output):
the script's flow section, unchanged, under the 5003 initramfs's own BusyBox and
`fsck.exfat`, on a 3 GiB loop device with 4096-byte logical blocks:

- GPT offset logic with a real 4 KiB GPT: slot-2 type, unique GUID and LBAs read
  at `2*4096+2*128` match `sgdisk -i3`.
- `write`: 1 GiB written, fsync, hash, `fsck.exfat -n` clean, read-only remount,
  hash equal, PASS.
- second `write`: refuses (`already exists; use nvmewrite=verify`), no write.
- `verify`: PASS, and p3's write counters did not move.
- one flipped byte then `verify`: `STOP: data mismatch`.

## Must-fix before 5003/211 is marked ready

1. **The kernel cannot mount exFAT.** `Image` 6eef9eef (the 6001 payload) has
   `# CONFIG_EXFAT_FS is not set` (payload `config` line 10919) and no `exfat`
   strings. `mount -t exfat` would fail with `mount rw failed`. The ticket still
   says "same kernel as 6001 run 3". Commit 64dcbaf adds `NVME_EXFAT=1`
   (EXFAT_FS only; `utf8` needs no NLS_UTF8 at `4f2429104009`, `super.c:38-39,696`).
   A new Image must be built twice, hashed, preflighted and reviewed, and the
   ticket's pins updated. EXFAT_FS also adds a driver that was not in the 6001
   read-only evidence.
2. **No host stop and no checker.** A hung or crashed controller during the write
   leaves `dd` blocked while the userspace `watchdog` daemon keeps petting, so
   nothing stops the run but a person. The 6001 flow had a host deadline and a
   transcript checker; this one needs both. Suggested: host deadline (the
   1 GiB write should take seconds; say 120 s from `wrote` start with no
   `PASS`), and a checker that requires `pins OK`, `fsck … rc=0` three times,
   equal hashes, `others_unchanged=yes`, and no `SError`/`RTKit: Exception`/
   `crashed`/`timeout:`/`controller is down`/`Reset failure`/`ANS did not`
   (case-sensitive as in the 6001 fix).

## Should-fix (script)

3. **Out-of-partition writes are not detected.** `others()` covers p1, p2, p4,
   n2 and n3, but not the whole disk, which is deliberately left writable (a
   read-only whole disk would make p3 read-only too). Add: after the test,
   write sectors/IOs in `/sys/block/nvme0n1/stat` must equal p3's delta, so a
   write that bypasses p3 shows up.
4. **Pin the boot-sector hash in `write` mode.** The evidence has
   `bb426fe0…` (512 bytes) and the script never uses it. Pin it only in
   `write` mode, because the driver updates VolumeFlags/PercentInUse, so it
   changes after the first run.
5. **Re-read from the device.** Add `echo 3 > /proc/sys/vm/drop_caches` before the
   read-back; umount drops file pages but metadata buffers can stay cached.

## Notes

- Safe ordering confirmed: p1/p2/p4/n2/n3 are set read-only (lines 65–68)
  before any pin read or mount; `p3` rw is asserted; whole disk stays rw by design.
- Mounting rw sets the exFAT dirty flag and unmount clears it; a hang mid-test
  leaves the volume dirty (recoverable with `fsck.exfat`, and macOS will offer to
  repair). The volume already holds macOS Spotlight metadata (`.Spotlight-V100`
  entries in the root directory dump), so it is not empty.
- No `discard` mount option; `fsck.exfat -n` makes no repairs.
- 1 GiB of `/dev/urandom` and a 1 GiB `sha256sum` on `maxcpus=1` are CPU-bound;
  expect tens of seconds for hashing. Set the host deadline accordingly.

## Commands run

```text
git show 1d67ddc; shasum -a 256 scripts/t6040-init-nvme-exfat-write
gunzip -c nvme-exfat-write-20261025/initramfs-write-a.cpio.gz | cpio -idm; cmp init scripts/…; shasum -a 256 sbin/fsck.exfat bin/busybox
sed -n 369,420p …/runs/run1/t6040-console-20261025-claude-5001-run1.log   # raw GPT, boot sector, root dir
grep -n 'CONFIG_EXFAT_FS\|CONFIG_NLS' nvme-ioq-20261024b/payload/config; strings -a payload/Image | grep -ci exfat
git grep -n utf8 4f2429104009 -- fs/exfat/super.c fs/exfat/Kconfig; git show 64dcbaf
podman machine ssh "sudo podman run --rm --privileged --platform linux/arm64 … sh /t/w_run.sh"   # loop-device flow test
```
