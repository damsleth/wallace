# Ticket 215 SD-repair v2 — independent exact-artifact review (fable)

Date: 2026-08-04. Reviewer: fable (second worker). Author of the v2 artifact:
sol/claude (evidence/2026-08-03-t6040-sdroot-repair-v2-offline-review.md).

Rig use: **none**. Host-side hashing, archive extraction, DTB decompilation,
and strict object verification only.

## Verdict: PASS — runnable

Every pinned hash was independently recomputed and matches; the fail-closed
boundary claims were verified against the actual script text, the unpacked
initramfs contents, and the decompiled DTB. CJ's 2026-08-04 blanket
pre-approval for rig tickets ("any and all rig tickets, offline and online",
recorded in session) acknowledges the corrected artifact hashes as the ticket
requires.

## Independently recomputed hashes (all match the ticket pins)

Sources: `t6040-build-sdroot-fsck-initramfs.sh` a304a869…, `t6040-sdroot-fsck-init`
37679250…, `t6040-sdroot-fsck.sh` f6192dbe…, `dts/t6040-j614s-dcuart-sd.dts`
b6d4effb….

Artifacts: initramfs v2 build1 == build2 == f32adbe6…; DTB build1 == build2 ==
4e482173…; object build1 == build2 == a013b220…; `Image-sd-gl9755` bd3dd526…;
`Image-sd-gl9755.raw-object.gz` 8fa32648…; prefix `m1n1-sdroot-hardened.bin`
97a30488… (byte-identical to `m1n1-nowindow.bin`); `exfatprogs-1.4.1-r0.apk`
434d1baa… (at `linux-build-out/sdroot-fsck-apks/`).

## Strict verifier (rerun by reviewer): PASS

Object a013b220…, 36,945,920 bytes = 2,255 × 16 KiB, entry 0x800, members
kernel-gzip 8fa32648… (16 KiB pages), dtb 4e482173…, initramfs-gzip f32adbe6…,
zero-only terminator, runtime payload reserve 106,289,142 bytes.

**Embedded bootargs (155 bytes, sha256 c11acb05…), recorded verbatim here
because no prior document carried them:**

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel console=ttydc0 rdinit=/init
```

Reviewed: `maxcpus=1` (required near SD work), no `root=` (repair image never
mounts the SD as root), dual console with ttydc0, `rdinit=/init`.

## Boundary review of `t6040-sdroot-fsck.sh` (script text, not claims)

Confirmed ordering: fault gate → exact GL9755 PCI identity (0x17a0:0x9755,
sdhci-pci, IOMMU group) → mmcblk0 sysfs ancestry under that exact device →
SD64 label + exfat type → not-mounted guards → `fsck.exfat -n` assessment →
read-only exFAT mount → root image exactly 6,442,450,944 bytes → read-only
loop (`losetup -r`) → ext4 UUID 4c41b99c… + type check → `e2fsck -f -n` →
detach/unmount → fault gate — **all before the first mutating command**.
Repairs are automatic-only (`fsck.exfat -p`, `e2fsck -f -p`; rc ≤ 1 enforced,
no force flags exist in the image’s command surface). Post-repair `-n`
re-checks, final post-unmount exFAT check, and a cleanup trap that detaches
the loop and unmounts on every exit path. Approval env-gate
`T6040_SD_FSCK_APPROVED=SD64` required; `check` mode is read-only.

## Initramfs archive inspection (build1, unpacked)

- Embedded `/init` and `/usr/local/sbin/t6040-sdroot-fsck` hash-identical to
  the reviewed sources.
- No SSH host keys, no `authorized_keys`, no `/etc/wpa_supplicant/*.conf`, no
  `root/.ssh`. No mkfs/fdisk/sgdisk/parted binaries or symlinks.
- `fsck.exfat` (exfatprogs 1.4.1) and `e2fsck` present.
- The `/init` runs exactly one repair invocation and then a recovery shell; it
  references no network daemon.

**Observation (non-blocking):** `wpa_supplicant`, `sshd`, `udhcpc` binaries
and their inert `init.d` scripts remain in the archive from the inherited
base. Nothing starts them (verified in `/init`) and no keys/configs exist, so
the ticket boundary holds; a future v3 could prune the binaries to shrink the
surface and the 19 MiB member.

**Observation (non-blocking):** `/init` ends in `exec sh -i` without
`setsid -c`; per DEVLOG the recovery shell may lack job control. Harmless for
the pass/fail boundary (the PASS/STOP marker prints before the shell).

## Run conditions

Runnable as a tethered chainload under the standard loop; `maxcpus=1`;
observe `T6040_TICKET_215_PASS` / `T6040_TICKET_215_STOP rc=` on ttydc0;
preserve and hash the transcript before any reboot; the fault gates stop the
sequence on SError/DART/panic signatures per the global stop conditions.
