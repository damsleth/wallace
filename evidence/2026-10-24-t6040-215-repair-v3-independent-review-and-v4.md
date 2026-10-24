# Ticket 215: independent review of repair v3, and a console-order v4

Claude, 2026-10-24. Offline review and recomposition. No rig, card,
enrollment or boot.

## Why

v3 (`bf395c6e…`) was rebuilt by fable on 2026-08-04 and reviewed only by its
builder. It had no independent review. Today's preflight also rejects it.

## Independent review of v3 members (PASS)

- Hashes match every 215 pin: v3 object (both builds), prefix `97a30488…`,
  `Image-sd-gl9755` `bd3dd526…`, kernel member `8fa32648…`, DTB `4e482173…`
  (`t6040-j614s-dcuart-sd-v2.build{1,2}.dtb`), initramfs `901ad007…` (both
  builds), embedded `/init` `8fcd4f1d…`, `t6040-sdroot-fsck` `f6192dbe…`,
  builder `7fe5bf10…`, keymap `606ecd98…`.
- Strict raw-object verifier: PASS (36,945,920 B, entry `0x800`).
- `/init`: mounts only proc/sysfs/devtmpfs/tmpfs, loads the Norwegian keymap
  before any shell, waits for `ttydc0`, runs the repair exactly once, prints
  `T6040_TICKET_215_PASS` or `…_STOP rc=<n>`, and leaves a shell. It starts no
  network, OpenRC, automount or background jobs.
- `t6040-sdroot-fsck`: an explicit approval variable, then every identity gate
  before any mutation: GL9755 `17a0:9755` bound to `sdhci-pci` with an IOMMU
  group, `mmcblk0` a sysfs child of that controller, label `SD64`, type exFAT,
  not mounted, and ext4 UUID `4c41b99c…` via a read-only loop. Read-only
  assessment comes first. Repair is automatic-only (`fsck.exfat -p`,
  `e2fsck -f -p`); rc > 1 stops with no forced repair. Read-only rechecks
  follow each repair, plus a final post-unmount exFAT check. There is no
  format, resize, discard, repartition or raw-write path.
- DTB scope: ANS mailbox, NVMe and the PMU SPMI bus `spmi@509014000` are
  disabled. On the PCIe root, port 0 (BCM4388 WiFi/BT) and ports 2–3 are
  disabled; only `pci@1,0` (GL9755) is enabled, with the single
  `pwren-gpios` = SMC GPIO `0x19` (`gP19`, permitted). SMC rtc/reboot nodes
  have no nvmem provider with the PMU bus disabled, so they cannot reach the
  PMU.
- `fsck.exfat` sits at `/usr/sbin` (Alpine exfatprogs), so the preflight's
  `./sbin/fsck.exfat` warning is a path convention, not a missing tool.

## The blocking defect: console order

v3's bootargs end in `console=ttydc0`. Today's `t6040-image-preflight.sh`
(BUILD_RECIPE §3) fails any image whose last console is not `tty0`. Per
AGENTS.md, v3 must not be booted.

## v4 (same members, corrected bootargs)

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused fbcon=font:TER16x32 ignore_loglevel console=ttydc0 console=tty0 rdinit=/init
```

```text
6ae7244e0dba756fa6c28af34a17853397289467d207904ac3729f11fa8a187b  m1n1-sdroot-repair-v4.build1.bin
6ae7244e0dba756fa6c28af34a17853397289467d207904ac3729f11fa8a187b  m1n1-sdroot-repair-v4.build2.bin
8fa32648489aeb4dac97e39dcf932121706b05b264bffd58bac26511059a9648  kernel member (identical to v3)
```

Both compositions use the build1 and build2 inputs respectively and are
byte-identical. Strict verifier: PASS on both. Preflight: OK on both, with only
the benign `/usr/sbin` warning. Only the 155-byte bootargs record differs from
v3. The repair script writes to ttydc0 explicitly, so moving `/dev/console` to
the panel does not change the observation channel.

## Remaining gates for 215

1. Object-level review of v4 by an agent other than claude. Members are
   unchanged and reviewed above; checking the recomposition is quick.
2. CJ acknowledges the v4 hash (the approval covered `bf395c6e…`).
3. Rig: the always-proxy rollback must be enrolled (the 2026-08-04 blocker; it
   was later re-enrolled for the 230/108 runs). SD64 in the GL9755 reader,
   nothing else attached, attended, under a lease.
