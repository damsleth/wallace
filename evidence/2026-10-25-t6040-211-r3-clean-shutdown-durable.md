# 211 stage 1 r3: write-through plus clean controller shutdown is durable across a hard reset

claude, 2026-10-25, payload `nvme-exfat-write-20261025c` (initramfs
`62bab9e3`). Mythos review of the delta: PASS-with-notes,
`evidence/2026-10-25-review-5003c-delta.md`.

## Write r3 (`nvmewritedir=r3 nvmewc=through nvmeend=reboot`), console `519af672c84bf0c4…`

- Checker **PASS**. 1 GiB, sha256 `dc4a8a77…`. The read-back after
  `drop_caches` matches. Disk writes equal p3 writes. Others unchanged.
- At `reboot -f`, `device_shutdown` reached `apple_nvme_shutdown`:
  ```text
  host_ans2.c:1616: cmd parsing error for tag 0 fast decode err 0x7   (x2: admin delete SQ/CQ, BAD_CMD; same as m1n1)
  cmd.c:9822: NVMe shutdown start seg->lba: 0, seg->size: 0
  cmd.c:9852: seg->lba 0 saveCtx 1 took 599 ms - clog 23891060
  ```
  The firmware performed its shutdown context save after CC.SHN.
- Then `syscore_shutdown` hit `kvm_shutdown`, then `kvm_timer_cpu_down`, then
  `aic_fiq_set_mask`, which raised **Oops: Undefined instruction**
  (`d51df160`, an Apple IMP-DEF sysreg write). The kernel is not at EL2, so
  the KVM vtimer FIQ mask traps. `reboot -f` never reboots. This happens after
  the storage shutdown, so it doesn't affect data, but it is a daily-driver
  reboot bug of its own (ticket 5007).

## Hard reset, then verify r3 (`nvmewritedir=r3 nvmewc=through`), console `eff7fb441fa2ea49…`

- Checker **PASS**: `pattern.bin` hash equals `dc4a8a77…`, **and
  `pattern.sha256` is present**. That file was written last and is exactly
  what r2 lost without a controller shutdown. fsck clean. Zero writes.
- `VolumeFlags=2` (dirty) at boot is inherited from r2's lost unmount. The r3
  write boot already printed "not properly unmounted" at mount, and Linux
  exFAT does not clear a dirty bit it did not set. It is not a new loss. The
  nvmeroot init's dirty gate runs `fsck.exfat -y` on first boot.

## Conclusion for the daily driver (5005)

- ANS2 rejects NVMe Flush (5006), so Linux must run nvme0n1 **write-through**
  (no Flush/FUA requests).
- Recent writes stay in the controller's volatile cache until a **controller
  shutdown** (CC.SHN, followed by the firmware's saveCtx), and they are lost on
  a hard reset or crash. A clean shutdown commits them.
- The nvmeroot init must set `write_cache` to `write through` before the
  exFAT mount. The PID-1 shutdown must reach the `reboot`/`poweroff`
  syscall so that `device_shutdown` runs. The KVM oops (5007) follows it
  harmlessly but leaves the machine hung; a hard reset is then safe.
- A crash still loses the last writes. ext4's journal on the loop root bounds
  that to recent data; this is an accepted caveat for CJ.
