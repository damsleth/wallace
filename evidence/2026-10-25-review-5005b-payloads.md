# Review: 5005 revision b payloads (host-built root image, installer, step launcher) — PASS-with-notes

Date: 2026-10-25. Reviewer: claude (Mythos Wallace session), offline, host
only; the embedded root image was decompressed and inspected under
`podman run --platform linux/arm64` (Alpine 3.22 e2fsprogs), nothing else
executed, nothing edited. Requested by Opus Wallace for ticket 5005/5008
after revision b (`ea9aebc`, launcher `89f355e`). Supersedes
`evidence/2026-10-25-review-5005-payloads.md` for payloads A and B; C is
unchanged and that review's verdict on it stands.

## Verdict

**PASS-with-notes.** The installer no longer needs the SD64 card: it
decompresses a host-built 16 GiB ext4 image carried inside its own
initramfs, hashes it in-stream against a hash that is also carried in the
initramfs, re-hashes from the SSD, checks it read-only, renames, and
reboots cleanly. The write surface is strictly smaller than revision a
(no `e2fsck -fp`, `tune2fs`, `resize2fs`; the loop is attached `-r`); the
tools that could widen it are absent from the initramfs. Step A is the
already-passed 6001 read-only tester byte for byte. The launcher's hash
check, 900 s deadline and DebugUSB reboot are as the earlier must-do asked.
Four notes, none blocking.

## 1. Hashes (`shasum -c SHA256SUMS` from `linux-build-out/`: all OK for A, B, C)

| Payload | File | sha256 | Status |
|---|---|---|---|
| A, B, C | Image / System.map / config | `2234baad…` / `c0739fd7…` / `7045ae19…` | unchanged from the revision-a review |
| A, B, C | t6040-nvmeroot.dtb | `6d2d3da6…` | unchanged |
| A, B, C | m1n1.bin | `7de07c71…` | unchanged (rollback proxy, chainload) |
| A | initramfs.cpio.gz | `524d94c3…` | **`cmp`-identical to `nvme-ioq-20261024b/payload/initramfs.cpio.gz`**, the 6001 run-3 read-only tester (its `/init` is the RAM-only queue-wrap test, `setro` on every namespace) |
| B | initramfs.cpio.gz | `d2c564f0…` | new; `/init` `8516e58c…` is `cmp`-identical to `scripts/t6040-init-nvme-root-install` at HEAD, `git diff HEAD` clean |
| C | initramfs.cpio.gz | `9adabb1b…` | unchanged |

Inside B (529 files): `/wallace-root.img.xz` `ab73d13f…` (27,037,564 B)
and `/wallace-root.img.sha256` containing exactly `e3fa66b5…`, both
matching the ticket pins and the builder output in
`linux-build-out/nvmeroot-image-20261025/`; `bin/busybox` `97d52efa…`
(the `xzcat` applet is present), `sbin/fsck.exfat` `d56b877d…`
(unchanged), `sbin/e2fsck` `9b4fd5bf…` (has the `orphan_file` checksum
code the image's feature set needs). Absent, as the builder's forbidden
list requires: `mke2fs`, `mkfs.ext4`, `blkdiscard`, `fdisk`, `debugfs`,
`tune2fs`, `resize2fs`. Present and unused: `usr/sbin/dumpe2fs`
(read-only; note 4). The BusyBox binary itself still carries the `fdisk`,
`mkfs.vfat`, `mkswap`, `blkdiscard` and `fstrim` applets (the builder's
`rm -f` removes symlinks, not applets); the scripted PID-1 init never
invokes any of them and no shell is reachable before `park`, so they are
unreachable in the automated run, not absent (note 5).

## 2. The embedded root image

Decompressed under arm64: raw sha256 **`e3fa66b5…`** (= the carried hash
= the launcher's `--expect-sha256`), `e2fsck -fn` rc 0 (`3280/1048576
files, 132757/4194304 blocks`), UUID `988d97b4-06ba-40d7-8f70-7899bb6fa297`,
label `wallace-root`, state clean, 4,194,304 × 4 KiB = 17,179,869,184 B =
`ROOT_BYTES`. Features: `has_journal ext_attr resize_inode dir_index
orphan_file filetype extent 64bit flex_bg metadata_csum_seed sparse_super
large_file huge_file dir_nlink extra_isize metadata_csum`.

Contents, against `scripts/t6040-build-nvmeroot-image.sh`:

- Alpine 3.24.0 base (`initramfs-alpine-dwm-i3-v5`, pinned by hash in the
  builder); `/init` and `/etc/machine-id` removed.
- **`/usr/local/sbin/t6040-data-mount` and `t6040-data-sync` absent**
  (the RAM-root helper that mounts every NVMe partition rw is gone; the
  nvmeroot init owns p3). `tree.txt` has no match either.
- Runlevels exactly as the builder specifies: sysinit `devfs dmesg procfs
  sysfs`; boot `bootmisc hostname t6040-keymap`; default `bluetooth dbus`;
  shutdown `killprocs mount-ro`. 62 services in `/etc/init.d`, no
  automount/fsck/swap/udev service enabled.
- **Norwegian keyboard at all three layers:** console
  `/etc/init.d/t6040-keymap` (boot runlevel) `loadkmap`s
  `/etc/wallace-no.bmap` after verifying its sha256 `606ecd98…`
  (`/etc/conf.d/keymaps` also says `keymap="no"`, but Alpine's `keymaps`
  service is in no runlevel, so `t6040-keymap` is the live layer); Xorg
  `/etc/X11/xorg.conf.d/00-keyboard.conf` `XkbLayout "no"`; locale
  `/etc/profile.d/wallace-locale.sh` `nb_NO.UTF-8`. The installer
  initramfs loads the same keymap in `/init` before any shell.
- `/etc/fstab` is a comment only (the nvmeroot init mounts `/`);
  hostname `wallace`; `/etc/wallace-root-profile` = `nvmeroot-5005-v2`.
- The remaining `usr/local/sbin` helpers (`t6040-b0-autologin`,
  `t6040-startx`, `t6040-usb-*`, `t6040-wifi-*`, `t6040-bluetooth-start`)
  are carried but not enabled; inittab and the login/X helpers come from
  the C initramfs each boot, as revision a's design said.

Deterministic build: `E2FSPROGS_FAKE_TIME=1`, fixed `hash_seed`, no lazy
init, `xz --check=crc32`; the builder refuses an existing `DEST` and never
opens a block device.

## 3. Installer delta (`d948ba7` → `ea9aebc`)

| Removed | Added |
|---|---|
| the whole SD64 source gate (GL9755 PCI check, `setro` on mmcblk0, LABEL/UUID/ext4-clean checks, `/mnt/sd`) | `SRC=/wallace-root.img.xz`; `EXP` read from `/wallace-root.img.sha256`, must be 64 hex chars, else STOP before any gate |
| `dd if=$SRC bs=4M | tee | sha256sum` of 6 GiB | `xzcat $SRC | tee $DST.partial | sha256sum` with `pipefail`; size must equal `ROOT_BYTES`; **`H == EXP` or STOP** |
| `truncate -s 16G`, rw loop, `e2fsck -fp`, `tune2fs -U`, `resize2fs`, second `e2fsck -fn` | read-only loop (`losetup -r`), one `e2fsck -fn`, `findfs UUID=988d97b4` must return the loop, `blockdev --getsize64` must equal `ROOT_BYTES` |
| PASS field `source_sha256=` | PASS field `sha256=`; re-read hash compared against `EXP` (the pin), not merely against the stream hash |

Everything else is unchanged from revision a: NVMe identity and p3 pin
gates (GPT entry, type/GUID/LBAs, exFAT serial, label at 7,733,248,
boot-sector fields 64..105/108..111), `setro` on p1/p2/p4/n2/n3, dirty-bit
repair with `fsck.exfat -y` on p3 only, `write through` to the queue with
readback, refusal when `wallace-root.img` exists, `rm -f` of a stale
`.partial`, `drop_caches` before the re-read, `fsck.exfat -n` before and
after, disk-vs-p3 written-sector equality, `others()` hash, `sync` +
`reboot -f` after PASS with `park` fallback.

**Write surface:** the only writers are the exfat driver through p3's bdev
(the `.partial` file, its rename, the dirty-bit repair) and the sysfs
`write_cache` attribute. Nothing opens the loop device rw; no standalone
tool in the initramfs can make, resize or retune a filesystem, and the
init calls none of the BusyBox applets that could partition or discard. The image
bytes written are fixed by two hashes that live in the same signed-off
initramfs as the installer, so a corrupted or substituted image cannot
pass the in-stream check, and a transport error on the way to the SSD
cannot pass the re-read check.

## 4. Checker and launcher

`scripts/t6040-check-nvme-root-install-transcript.py` (same commit):
requires the p3 pins line, `write_cache=write through`, exactly one
`wrote 17179869184 bytes … sha256=X expected=Y` line with X == Y, the
re-read hash equal to it, optional `--expect-sha256` equal to it, exactly
one clean `e2fsck -fn /dev/loopN`, two clean `fsck.exfat -n`, disk == p3
sectors, exactly one PASS line whose `sha256=` equals the same hash; any
`NVME-INSTALL STOP`, SError, panic, BUG, Oops, RTKit exception, I/O error
or timeout fails it. The tune2fs/resize2fs requirements of revision a are
gone, consistent with the installer. Flow test
(`evidence/2026-10-25-t6040-5005-installer-flow-test/output-embedded.txt`):
full-size decode of the shipped xz with the installer's own BusyBox gives
`e3fa66b5…`; the scaled install passes the checker; a second run refuses
with `already exists`.

`scripts/t6040-run-nvmeroot-step.sh A|B|C <run-dir>`: refuses an existing
run dir, `shasum -c SHA256SUMS` before boot, `env -u EXTRA_BOOTARGS`,
`RIG_ENFORCE=1` (lease), `BOOT_MAXCPUS=1 BOOT_IDLE=nop`,
`CHAINLOAD_ATTEMPTS=1`, the nvmeroot DTB for all three steps. A waits up
to 300 s for `NVME-READONLY PASS|STOP` and runs the 6001 checker; B waits
up to `DEADLINE` (900 s) for `NVME-INSTALL PASS|STOP`, sleeps 30 s for the
shutdown lines, and on neither issues `macvdmtool reboot debugusb` and
records it; the installer checker then runs with `--expect-sha256
e3fa66b5…`. C only boots and captures. `IMAGE=$P/Image` is the same
`$OUT`-relative convention as `t6040-run-nvme-write.sh`, which has run.

## Notes (non-blocking)

1. **Deadline headroom.** 16 GiB is written once and read back once at
   `maxcpus=1`, each pass hashed by BusyBox `sha256sum`, then `e2fsck`
   walks 4 M blocks; the flow test's 1 GiB took ~7 s on the host, which
   says nothing about the rig. If step B hits the deadline with the
   console still progressing (a `wrote … in t0..t1 s` line not yet
   printed), that is a slow copy, not a hang: the DebugUSB reboot leaves
   a `.partial` and a dirty bit on p3, both of which the next install
   run handles (`rm -f $DST.partial`, `fsck.exfat -y` repair before the
   gates), so re-run with a larger `DEADLINE=`. Record the `wrote` and
   `re-read` timings in the run evidence to calibrate.
2. **Expect `Deferred flush failed` at the clean reboot** (as in 5003c):
   the checker does not treat it as a stop condition and it is not one.
3. **The ext4 feature set** includes `orphan_file` and
   `metadata_csum_seed`; the installer's e2fsck handles them (checked),
   and the asahi-wip-based kernel does. A future e2fsck from an older
   e2fsprogs would refuse the image rather than damage it.
4. `usr/sbin/dumpe2fs` stays in the initramfs (the builder keeps it on
   purpose) but revision b's installer no longer calls it; read-only,
   harmless, could be dropped from the keep-list next time.
5. **Step A's checker** (`t6040-check-nvme-ioq-transcript.py`) pins only
   test-level values (64 MiB/16 KiB/4 passes start line, 256 MiB PASS
   line, block and auxiliary-namespace stats, the pinned namespace
   topology), nothing tied to the 6001 kernel or DTB, so it is valid for
   the new kernel. The launcher's fixed 300 s wait for A is the only
   timing assumption; in the 6001 run-3 transcript the test exits at
   uptime 3.4 s.
6. The BusyBox in B is a newer binary (`97d52efa…`) than the one the
   5003 reviews covered (`61781806…`); the `xzcat`, `od -tu2`, `reboot -f`
   and `sha256sum` behaviours the installer relies on were exercised by
   the flow test with this binary (full-size decode and scaled install).

## Commands run

```text
cd linux-build-out && shasum -a 256 -c nvmeroot-20261025/payload-{A-nvmeread,B-install,C-nvmeroot}/SHA256SUMS
gzip -dc payload-B-install/initramfs.cpio.gz | cpio -idm; cmp init ~/Code/wallace/scripts/t6040-init-nvme-root-install
shasum -a 256 wallace-root.img.xz init bin/busybox sbin/fsck.exfat sbin/e2fsck; cat wallace-root.img.sha256; strings bin/busybox | grep -x xzcat
test -e for tune2fs/resize2fs/mke2fs/mkfs.ext4/blkdiscard/fdisk/debugfs/dumpe2fs; strings sbin/e2fsck | grep orphan
cmp payload-A-nvmeread/initramfs.cpio.gz nvme-ioq-20261024b/payload/initramfs.cpio.gz
podman run --platform linux/arm64 alpine:3.22: xz -dc; sha256sum; e2fsck -fn; dumpe2fs -h; debugfs -R 'ls -p / cat / stat' (runlevels, init.d, usr/local/sbin, keymap files, fstab, hostname)
git diff d948ba7 HEAD -- scripts/t6040-init-nvme-root-install scripts/t6040-check-nvme-root-install-transcript.py
cat scripts/t6040-build-nvmeroot-image.sh scripts/t6040-build-nvme-root-install-initramfs.sh scripts/t6040-run-nvmeroot-step.sh scripts/t6040-usb-root-keymap.initd
tail evidence/2026-10-25-t6040-5005-installer-flow-test/output-embedded.txt; cat linux-build-out/nvmeroot-image-20261025/dumpe2fs.txt
```
