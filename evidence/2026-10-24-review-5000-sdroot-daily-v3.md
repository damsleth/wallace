# Independent review: ticket 5000 SD-root daily v3

Reviewer: independent (non-builder) offline review, 2026-10-24. No rig, lease,
card, enrollment or boot.

**Verdict: PASS-with-notes.** The object is what the build note says, and the
embedded init/shutdown set is byte-identical to the set that scored 23/23 in
the 3006 harness. Notes concern what is *not* covered.

## Findings

- `m1n1-alpine-sdroot-daily-v3.build{1,2}.bin` = `3dae3812…b9703a`
  (25,870,336 B); initramfs `build{1,2}` = `f089ffa7…`; kernel member
  `Image-alpine-sdroot-daily-v3.raw-object.build{1,2}.gz` = `b5d33b33…`
  (identical to daily-v2's); Image `3e129466…`; DTB `c5c3b4c3…` both builds.
  All recomputed.
- Strict verifier (m1n1 prefix `m1n1-sdroot-hardened.bin`, exact kernel/DTB/
  initramfs members, bootargs `… ignore_loglevel console=ttydc0 console=tty0
  rdinit=/init`): PASS both builds. Preflight: OK, no FAIL/WARN.
- Extracted the initramfs and hashed: `/init` `95f1e268…`, `/shutdown`
  `c5c05855…`, `opt/wallace/t6040-sdroot-inittab` `f5e1628e…`,
  `…-powerctl` `791c0f8a…`, `…-openrc` `47e7504d…`, `…-early-console`
  `9fba64d6…`. All six equal the `variant/*` hashes in
  `evidence/2026-10-24-t6040-3006-sdroot-shutdown/fixed/manifest.txt`, and
  `verdicts.tsv` there is 23/23 PASS (7 clean cases, 1 bad action, 15 injections).
  The initramfs `bin/busybox` is `61781806…`, the BusyBox the harness used.
  `wpa_supplicant.conf` `c65245bc…` and `tpmtfw-j614s.bin` `a1f4131d…` match the note.
- DTB (decompiled with `dtc`): `nvme@44dcc0000`, `mailbox@409608000` (ANS),
  `spmi@509014000`, `smc/rtc`, `smc/reboot`, `usb@382280000/38a280000/392280000`
  and PCIe `pci@2,0`/`pci@3,0` are `disabled`; `smc@50c600000`, the HID and its
  two mailboxes are `okay`. No PMU/SPMI/NVMe path is reachable.
- Differences vs the 3006 harness are only as stated: the build script
  (`9d0a1b94…`) is a working-tree version; its output matches the harness set.

## How it could be wrong

1. *Harness ≠ real boot.* The 3006 harness runs the scripts in a container
   namespace with a mock; the SD-root shutdown path with this kernel is untested
   on hardware. Ruled neither in nor out; the note says so. Open until the attended boot.
2. *Embedded `/init` differs from the one tested.* Ruled out by hash.
3. *Stale daily-v2 kernel.* It is the pinned reproducible v2 kernel (Aug), which
   predates the trackpad stack; it lacks `TRACKPAD_FW` so the HIDF blob is inert,
   as stated. Not a defect, but daily-v3 is superseded in capability by v4.

## Notes

- `smc_reboot`/`smc_rtc` are disabled, so the last step of poweroff/reboot may no-op.
- The build script is not committed in this state (`working-tree`); pin it before
  anyone rebuilds.

## Commands run

```text
shasum -a 256 m1n1-alpine-sdroot-daily-v3.build{1,2}.bin initramfs-sdroot-daily-v3.build{1,2}.cpio.gz Image-alpine-sdroot-daily-v{2,3}.* t6040-j614s-dcuart-wifi-cpufreq-sdroot.build{1,2}.dtb scripts/t6040-build-sdroot-initramfs.sh
gunzip -c initramfs-sdroot-daily-v3.build1.cpio.gz | cpio -idm; shasum -a 256 init shutdown opt/wallace/* bin/busybox lib/firmware/apple/tpmtfw-j614s.bin
python3 scripts/t6040-raw-object-verify.py --strict --m1n1 … --kernel … --dtb … --initramfs … --expect-bootargs '…' <object>   # x2
scripts/t6040-image-preflight.sh --kernel Image-alpine-sdroot-daily-v2.build1 --initramfs … --object … --bootargs '…' --m1n1 m1n1-sdroot-hardened.bin
dtc -I dtb -O dts t6040-j614s-dcuart-wifi-cpufreq-sdroot.build1.dtb; status walk
cat evidence/2026-10-24-t6040-3006-sdroot-shutdown/fixed/{manifest.txt,verdicts.tsv}
```
