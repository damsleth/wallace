# Independent review: ticket 5001 `t6040-init-nvme-p3-identity`

Reviewer: sonnet, offline, 2026-10-24. No rig, lease, boot or build. Nothing
reviewed was edited. The BusyBox applet list came from running the initramfs's
own `busybox --list` in an aarch64 container, not from the rig.

**Verdict: FAIL (two must-fix items).** The probe is read-only and cannot write,
but as built it will not record the data it exists to record. Do not mark 5001
ready until the two items below are fixed and the initramfs is rebuilt.

## Artifacts (recomputed)

```text
a140f2822fc44bc72d421675add95e2c098b1c580a5cbff86135ecb0daac4faa  scripts/t6040-init-nvme-p3-identity (= /init in the initramfs)
556c1ac2adbd57b4adfe96ba9ab91991e9f032d40817df211cdcd5321a7f0484  nvme-p3id-20261024/initramfs-p3id-{a,b}.cpio.gz (identical)
61781806ad3650b0b9d2b3fc6971e2bffdca967af1a95375abd0578bafff14fb  embedded bin/busybox (v1.35.0)
606ecd98f83b72983f3cd35976df939dc9c7187283703736a81e89b65aee85a8  embedded Norwegian keymap
```

## Must-fix

1. **`blkid` is not an applet in this BusyBox.** `busybox --list` has no `blkid`.
   Lines 56-58 call `$BB blkid "$d" 2>&1`, so the log will contain
   `blkid: applet not found` for p1, p2 and p3, the script will still print
   `IDENTITY-DONE`, and the exFAT label and filesystem type are never recorded.
   The boot sector does not hold the label; it is a type-0x83 entry in the root
   directory. Fix: read the root directory yourself (boot-sector
   FirstClusterOfRootDirectory, ClusterHeapOffset and SectorsPerCluster, then
   hexdump the first cluster), or add a tool that has `-l`/blkid to the
   initramfs. `fsck.exfat` is already there but is not a label reader.
2. **The `p3-bootsector` line is dropped by the kernel.** It is 512 bytes as hex
   (`16/1 "%02x" " "` gives 1,536 characters) plus the prefix, about 1,570 bytes
   in one `write()` to `/dev/kmsg`. At `4f2429104009`, `devkmsg_write` returns
   `-EINVAL` when `len > PRINTKRB_RECORD_MAX` (1024) (`kernel/printk/printk.c:749`,
   `internal.h:51`). The write fails, so the record is lost, not truncated.
   `p3-volumeflags` is a separate short line and does survive. Fix: log a
   `sha256sum` of the sector plus at most about 300 bytes of hex per line, and
   split the rest across lines.

## Should-fix

3. **No explicit stop if p3 is absent.** The loop at line 37 waits up to 30 s for
   `/dev/nvme0n1p3` and then carries on; the topology test does not check it.
   If p3 never appears, every p3 read is empty and the script still reports
   `IDENTITY-DONE`. Add `[ -b /dev/nvme0n1p3 ] || { say 'STOP: p3 absent'; park; }`.
4. **The 6001 identity gate was dropped.** The 6001 init also checked
   `transport=apple-nvme` and `model=APPLE SSD…` before any read; this script
   keeps only the namespace sizes. Restore it so a different controller or disk
   with the same sizes is not probed.
5. **No checker for this PASS.** The ticket says PASS is `IDENTITY-DONE` with
   zero write counters, but nothing parses the transcript. With fix 1 and 2
   made, the 211 write test will pin whatever this prints, so a small checker
   (required lines present, `stats before` and `after` write/discard/flush fields
   equal, no `STOP`) is worth having first.

## Checked and fine

- Read-only discipline: no mount, no write path; `blockdev --setro` is set on
  n1, every partition, n2 and n3 before the first read (lines 46-49); every device
  read is `dd if=…` with no `of=` to a device.
- GPT arithmetic: entries are 128 bytes from LBA 2, so `skip=$((8+e))` at `bs=128`
  is correct; the header line (`cut -c1-300`) covers the first 92 bytes (276
  characters), which is the whole header; entry lines are 384 characters, under
  the 1,024 limit; `gpt-lba0-33` hashes 34 sectors.
- exFAT VolumeFlags: byte offset 106, 2 bytes, read with `dd bs=1 skip=106
  count=2` and `od -An -tu2` on little-endian aarch64; `${flags##* }` takes the
  number. Correct.
- Applets used and present in this BusyBox: `mount`, `mkdir`, `loadkmap`,
  `watchdog`, `setsid`, `dd`, `sha256sum`, `hexdump`, `od`, `cut`, `blockdev`,
  `grep`, `sleep`. (`blkid` is the only missing one.)
- Norwegian keymap loaded before any shell; both rescue shells (`ttydc0`, `tty1`)
  start only from `park`. Bootargs in the ticket add `printk.devkmsg=on`, which
  the script needs because the default ratelimits userspace `/dev/kmsg` writes.
- Kernel, DTB and m1n1 pins match 6001 run 3 (`6eef9eef…`, `a96d04a7…`,
  `7de07c71…`).

## How it could be wrong that I did not rule out

- `/dev/watchdog0` presence is assumed from the 6001 init, which uses the same
  idiom. I did not check that run 3 actually had one; if not, this script parks
  at line 29 before probing anything.
- I did not read the run-3 transcript, which is still in the run directory.
  This probe's value depends on run 3 having completed cleanly.

## Commands run

```text
shasum -a 256 scripts/t6040-init-nvme-p3-identity nvme-p3id-20261024/initramfs-p3id-{a,b}.cpio.gz
gunzip -c initramfs-p3id-a.cpio.gz | cpio -idm; shasum -a 256 init bin/busybox etc/wallace-no.bmap
podman run --rm --platform linux/arm64 -v <extracted bin>:/b:ro alpine:3.22 /b/busybox --list
git show 4f2429104009:kernel/printk/printk.c | grep -n -A12 'static ssize_t devkmsg_write'
git show 4f2429104009:kernel/printk/internal.h | grep PRINTKRB_RECORD_MAX
diff scripts/t6040-init-nvme-ioq-readonly scripts/t6040-init-nvme-p3-identity
jq … tickets/5001-nvme-p3-identity-readonly.json; git show 662e08b
```
