# Exact-artifact review: 5005 NVMe daily-root payloads A / B / C — PASS-with-notes (one must-do before B)

Date: 2026-10-25. Reviewer: claude (Mythos Wallace session). Offline:
host tools, `dtc`, and the payloads' own arm64 binaries run under
`podman run --platform linux/arm64` in a read-only chroot; no rig, nothing
edited (one accidental regeneration of `scripts/t6040-nvmeroot-init` by the
generator reproduced the committed file byte for byte, which doubles as the
determinism check). Requested by Opus Wallace; pins in
`tickets/5005-nvme-daily-root.json`, author evidence
`evidence/2026-10-25-t6040-5005-payloads.md`, rig steps ticket 5008.

## Verdict

**PASS-with-notes.** All three payloads verify against their pins; the
shared kernel pair is byte-identical and its config differs from daily301
only by KVM and KVM-selected symbols; the DTB differs from the SD-root
daily DTB only by the three ANS nodes and the model string; the installer
cannot write outside p3 (and the SD is read-only by construction); the
nvmeroot init differs from the proven SD-root init only in the storage gates
and the write-through setting, with the 3006 shutdown pivot untouched.
**One must-do:** nothing on the host enforces the 15-minute deadline for
the installer boot (the 5003 launcher is write-test specific); add or adapt
a launcher before B, for the same reason the 5003 one exists.

## 1. Hashes and shared artifacts

`shasum -c SHA256SUMS` in each of `payload-A-sdroot-ro`, `payload-B-install`,
`payload-C-nvmeroot`: all OK, and every value equals the ticket pin.

- Kernel `Image 2234baad…`, `System.map c0739fd7…`, `config 7045ae19…`:
  `dailynvme.build1 == build2` (cmp) and the payload Image is that file.
- DTB `6d2d3da6…` (`t6040-nvmeroot.dtb`), same file in all three payloads.
- m1n1 `7de07c71…`, same object as 5001/5003/6001.
- A initramfs `f089ffa7…` = daily v3; its `/init` is `cmp`-identical to
  `scripts/t6040-sdroot-init` at HEAD.
- B initramfs `073bb3e1…`; `/init` `cmp`-identical to
  `scripts/t6040-init-nvme-root-install` at HEAD (clean).
- C initramfs `9adabb1b…`; `/init` `cmp`-identical to
  `scripts/t6040-nvmeroot-init` at HEAD (clean). **A and C are identical in
  every other member** (89 files compared by hash).

## 2. Kernel config vs daily301 (`96e83d85…` → `7045ae19…`)

The complete `diff` is 21 lines, every one a consequence of `CONFIG_KVM=n`:
`KVM`, `KVM_COMMON`, the `HAVE_KVM_*`/`KVM_*` helper symbols, `KVM_VFIO`,
`KVM_GUEST_MEMFD`, `VIRT_XFER_TO_GUEST_WORK`, `GUEST_PERF_EVENTS`,
`PREEMPT_NOTIFIERS`, `SCHED_INFO` (all `select`ed by KVM on arm64), the
two KVM debug `# not set` lines, and `# CONFIG_ARM64_ERRATUM_834220 is
not set` (a KVM-dependent option that disappears from the file). No NVMe,
EXFAT, SPMI, DART or driver symbol moved. The kbuild `NO_KVM=1` block
(`scripts/t6040-kbuild.sh:1446-1451`) is a single `config -d KVM` with the
5007 rationale, and the post-`olddefconfig` assert (`:1925-1928`) fails the
build if `CONFIG_KVM=y` survives. Correct and minimal.

## 3. DTB vs the SD-root daily DTB (`c5c3b4c3…`)

`dtc -I dtb -O dts` on both, `diff`: the model string, and `status`
`disabled → okay` on exactly `mailbox@409608000` (ANS mailbox),
`iommu@40dc50000` (ANS DART/SART) and `nvme@44dcc0000`. The PMU SPMI bus,
`smc_rtc` and `smc_reboot` remain disabled. Matches the author's claim.

## 4. Payload B, the installer: write surface

Walked every command in `scripts/t6040-init-nvme-root-install`. Writers:

| Writer | Target | Bound |
|---|---|---|
| `blockdev --setro` on p1/p2/p4/n2/n3 (line 70) and on `mmcblk0` + `mmcblk0p1` (121) | ioctls, no media write | before any gate read or mount |
| `fsck.exfat -y $DEV` (99), only when VolumeFlags bit 1 is set | p3 metadata repair | p3 only; the same repair the SD-root init performs on SD64; the flow test shows it clears the bit on this binary (`dirty-repair-output.txt`: 2 → 0) |
| `echo "write through" > queue/write_cache` (98, 144) | sysfs attribute | not a media write; readback gate stops otherwise |
| `mount -t exfat -o rw $DEV`, `rm -f $DST.partial`, `tee $DST.partial`, `truncate`, the e2fsprogs through a `losetup` over that file, `mv`, `sync`, `umount` | the file `wallace-root.img(.partial)` on p3 | p3 only; the `rm -f` removes only a previous partial of this installer |
| `reboot -f` after PASS (200) | kernel reboot → `device_shutdown` → `apple_nvme_shutdown` (CC.SHN) | the 211 r3 durability path |

Reads only: all GPT/boot-sector/label pins (`dd if=`), the SD64 side
(`mount -o ro`, `losetup -r`, `findfs`, `blkid`, `dumpe2fs -h`, the
`s_state` byte), `fsck.exfat -n` before and final, `e2fsck -fn` twice. The
SD card is set read-only at the block layer before its mount, so even a
wrong command could not write it. No partition tool, no mkfs, no discard:
the builder (`t6040-build-nvme-root-install-initramfs.sh`) deletes
`mke2fs/mkfs.*/mkswap/fdisk/blkdiscard/fstrim/badblocks/debugfs/e2image/…`
and asserts the forbidden set is absent; the extracted initramfs confirms
only `e2fsck`, `tune2fs`, `resize2fs`, `dumpe2fs` and `fsck.exfat` remain.

Order of gates: NVMe topology/identity → others read-only → p3 GPT and
exFAT pins → dirty check/repair → SD64 identity (GL9755 ancestry, LABEL,
size, ext4 UUID, clean state) → write-through readback → `fsck -n` → first
write. Every stop parks before the first write except the dirty repair,
which is itself a write to p3 only. After the copy: in-stream hash,
`drop_caches`, re-read hash equality, size check, `e2fsck -fn` → `-fp`
→ `tune2fs -U` → `resize2fs` → `e2fsck -fn`, UUID visible, loop size
exact, rename, `fsck -n` final, `others()` unchanged, disk-vs-p3 written
sectors equal. The 16 GiB `truncate` on exFAT is a real zero-fill by the
Linux driver (hence the long deadline), all of it inside the file.

Tooling verified on the payload's own binaries under arm64 chroot: BusyBox
1.37 `sh` honours `set -o pipefail` (the copy's `dd | tee | sha256sum`
status), `od -An -tu2` decodes VolumeFlags, `losetup` has `-r/-f/-d`,
`truncate`, `findfs`, `blkid`, `stat -c`, `tee` exist; `tune2fs`/`resize2fs`
1.47.4 start (musl loader and `libext2fs/libcom_err/libe2p/libblkid/libuuid`
are all in the image). `fsck.exfat` is the static `d56b877d…`.

Checker `t6040-check-nvme-root-install-transcript.py`: stop tokens as in
5003 plus `EXT4-fs error`; requires the exact pins line and SD64 line, one
copy hash equal to the re-read hash, the four e2fsprogs steps `rc=0` on a
loop device, two clean `e2fsck -fn`, two clean `fsck.exfat -n`, equal
disk/p3 written sectors, and one PASS line whose hash equals the copy hash.
Sound.

Flow test (`evidence/2026-10-25-t6040-5005-installer-flow-test/`): the
copy/adapt/commit section it ran differs from the shipped script only by
the sysfs-path substitution (`diff` verified), so it exercised the shipped
logic including write-through; results: PASS twice (two ext4 feature sets),
full-scale 6→16 GiB adapt clean, second run refuses, dirty-bit repair clears.

## 5. Payload C, the daily root

The authoritative check is `diff A/init C/init` from the extracted
initramfs images, not the generator. The diff is confined to:

1. constants: `PART=/dev/nvme0n1p3`, `ROOT_UUID=988d97b4…`,
   `ROOT_BYTES=17179869184`, the `PCI_DEV` constant removed;
2. the GL9755/sdhci/mmcblk ancestry and `LABEL=SD64` gates replaced by the
   NVMe gates from 5003/B: namespace wait, no second controller, the three
   namespace sizes, transport/model, `setro` on p1/p2/p4/n2/n3, no p5, the
   GPT type/GUID/LBA pins, exFAT signature/serial/label pins (same bytes as
   B and 5003b);
3. `write through` on `nvme0n1` with readback, placed **before** the
   VolumeFlags dirty check, so the `fsck.exfat -y` repair and both mounts
   run without Flush;
4. message strings ("SD64" → "linux exFAT").

Everything else, including the 3006 `/run` tmpfs, the ro identity mount →
`losetup -r` → detach → rw mount → `losetup` → `switch_root`, the
`mount --move`/`--bind` of the exFAT under `/run/initramfs/sd`, and the
PID-1 shutdown pivot (`umount /sd`, `losetup -d`, then reboot/poweroff), is
byte-identical to the SD-root init. Those operations act on `$PART` and the
loop device by name, so they apply to `nvme0n1p3` exactly as to
`mmcblk0p1`; the final reboot/poweroff goes through `device_shutdown` →
`apple_nvme_shutdown` → CC.SHN, which 211 r3 showed commits the cache.
`scripts/t6040-gen-nvmeroot-init.py` regenerates the committed
`t6040-nvmeroot-init` byte for byte.

One property worth stating for the daily use: `wallace-root.img` is
preallocated at 16 GiB, so after install the exFAT container's own
metadata never changes during normal operation; a crash or hard reset can
lose only the ext4 tail (journaled, recovered on the next mount) and leaves
the exFAT dirty bit set, which the init's existing `fsck.exfat -y` path
clears. The SD card is never touched by C; if it is inserted nothing mounts
it.

## Must-do before B

**Host deadline.** Ticket 5008 says "checker + 15 min host deadline", but
no script enforces it: `t6040-run-nvme-write.sh` hard-codes the write-test
payload, initramfs args and `nvmewrite=` cmdline. The installer's in-image
`watchdog` keeps petting while a stuck `dd` blocks (the same gap Sonnet
flagged for 5003 and `3e9adca` closed). Add a `DEADLINE=900` launcher for
B (a parametrised copy of the 5003 one is enough), with the DebugUSB reboot
on no `NVME-INSTALL (PASS|STOP)`, and run the checker from it.

## Notes

1. The B initramfs is the full Alpine bootstrap (529 files: apk, OpenSSL,
   dbus, glib, OpenRC…) with the dangerous tools removed. Larger surface
   than the install needs, but nothing in it runs unless `/init` calls it,
   and `/init` calls only BusyBox, the four e2fsprogs tools and `fsck.exfat`.
2. The dirty-p3 repair is the first automated *repair* write to the SSD.
   It is bounded to p3 and mirrors the SD-root behaviour, but note it in the
   run evidence if it fires (the `p3 dirty (VolumeFlags=…)` line), since
   211 r2/r3 left the bit set.
3. The installer refuses if `wallace-root.img` exists and never deletes
   it; a re-install needs an explicit, separately reviewed step.
4. The `others()` guard counts reads too, so any benign read of p1/p2/p4
   after the baseline stops the run (conservative; same as 5003).
5. Sequence A → B → C → three cold boots with clean poweroff is the right
   order: A proves the never-booted kernel+DTB with NVMe only enumerating,
   B is the only writer, C is the daily path. All at `maxcpus=1`. CJ must
   insert SD64 for A and B and remove it for C's cold boots.

## Commands run

```text
shasum -a 256 -c nvmeroot-20261025/payload-{A-sdroot-ro,B-install,C-nvmeroot}/SHA256SUMS; compare with ticket hashes
cmp dailynvme.build{1,2} Image/System.map/config; diff config-…daily301.build1 config-…dailynvme.build1
dtc -I dtb -O dts on t6040-j614s-dcuart-wifi-cpufreq-sdroot.build1.dtb (c5c3b4c3) and the payload DTB; diff
gzip -dc | cpio -idm for A/B/C; cmp inits against scripts/t6040-{sdroot-init,init-nvme-root-install,nvmeroot-init}; diff A/init C/init
find/sha256 all A and C members except init; diff
podman run --platform linux/arm64 … chroot B: busybox pipefail/od/losetup/truncate/findfs/blkid/stat/tee; tune2fs -V; resize2fs -V
sed -n '/^# --- copy/,/PASS installed/p' installer | diff against evidence/…/installer-flow-test/flow-section.sh
python3 scripts/t6040-gen-nvmeroot-init.py (reproduced the committed file; git diff empty)
```
