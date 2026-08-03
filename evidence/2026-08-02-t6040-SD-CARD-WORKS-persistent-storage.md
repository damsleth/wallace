# ✅ SD card works end to end — the persistent-storage milestone, via mmc0

2026-08-02, autonomous overnight session, ticket 193. CJ inserted a card before going AFK.

## Result

```
mmc0: SDHCI controller on PCI [0000:02:00.0] using ADMA 64-bit
mmc0: new UHS-I speed SDR104 SDXC card at address 0001
mmcblk0: mmc0:0001 SD 58.2 GiB
 mmcblk0: p1
/dev/mmcblk0p1   58.2G   12.6M   58.2G   0%   /mnt/sd
```

Write + persistence, verified across a **full reboot**:

```
SDWRITE:  wrote rc=0
          Sun Aug  2 20:22:33 UTC 2026 / t6040 SD write test
          8+0 records out
          83cc39a95ac8b2d0e95b67f7eb8a6960  /mnt/sd/wallace-8m.bin
--- reboot ---
PERSIST:  Sun Aug  2 20:22:33 UTC 2026 / t6040 SD write test
          83cc39a95ac8b2d0e95b67f7eb8a6960  /mnt/sd/wallace-8m.bin   <-- identical
```

**This is the first persistent storage on the M4 under Linux.** It needs no USB VBUS (still
knowledge-blocked) and no NVMe (still blocked on the CQ-wrap firmware assert), so the storage
milestone is met independently of both. `t6040-data-mount` already polls `/dev/mmcblk0p1` ->
`/mnt/sd` and `t6040-data-sync` already prefers `/mnt/nvme` then `/mnt/sd`, so the daily image
picks this up with no changes once it boots (see the blocker below).

## Two operational lessons

1. **The minimal dcuart root has a static `/dev`.** `mount /dev/mmcblk0p1` fails with
   `Can't open blockdev` until `mount -t devtmpfs none /dev` runs. Not an SD problem.
2. **That root's shell writes to the panel, not to ttydc0.** Commands sent via `/tmp/m1n1`
   execute but their output is invisible to the host. Wrap them: `{ ...; } > /dev/kmsg 2>&1`
   and the output joins the kernel stream the host is already reading. This is the general
   recipe for driving that image headlessly.

## New blocker found in passing (separate ticket)

The **i3/Alpine image no longer boots** on the current kernel: m1n1 hands off
(`Vectoring to next stage...`) and the kernel produces zero console output, reproducibly, twice.
The *same kernel + DTB* boots the minimal `initramfs-dcuart.cpio.gz` fine (508 lines, SD and
`nvme0n1: p1 p2 p3 p4` both enumerated), so the kernel and DT are good and the large image is the
variable. Note this image booted on the E8-bisect kernel earlier the same evening, so it is a
regression from one of the reverts (DT window 0x60000 -> 0x10000, or tagset queue_depth 3 ->
stock) or an intermittency that has now become reproducible. Tracked as ticket 198 — it blocks
the daily-driver image, not SD.
