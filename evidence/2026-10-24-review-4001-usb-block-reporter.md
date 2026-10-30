# Independent review: ticket 4001 right-port USB block reporter

Reviewer: independent (non-builder) offline review, 2026-10-24. Mocked/sysfs
fixtures only; no device, rig, mount or storage access.

**Verdict: PASS-with-notes.** I could not make it select a device other than
the one pinned by vendor, product, serial, exact sector count, removable flag
and right-port controller path, and it has no write, mount or ioctl path. One
fail-open gate and two hardening items below should be fixed before 109 runs,
none of them can cause a write.

## Artifacts (recomputed)

```text
89b3911e2fbdde38b13b95ba0cf456ec94b9711131eb002e7d6a9df703ca9b80  scripts/t6040-usb-block-report.sh
da223657340678f551ed93750e84b360aeb74937ef592911ee9e43f92f5ebbfe  scripts/t6040-test-usb-block-report.sh
```

The shipped tests: 19/19 PASS on the host shell (I did not use a container; the
evidence's BusyBox 1.35 run is therefore not independently reproduced).

## Attempts to break it (own fixture: `/tmp`-style fake sysfs, copy-free, script unmodified)

| Attempt | Result |
|---|---|
| Right device, correct pins | OK; ranges 0, 1–33, last 33, sda1 head |
| `/proc/mounts` path missing/unreadable | **reports OK, no mounted check** |
| Disk mounted as an alias path (`/dev/disk/by-id/...-part1`) | reports OK (alias not matched) |
| Another disk `sdaa1` mounted while `sda` is reported | correctly not blocked |
| Extra sysfs dir `sda/sda1x` with `start`/`size` | treated as a partition, reads LBA from it (bogus start) |
| Wrong serial/product/vendor/size, non-removable, wrong controller | STOP (tests) |
| Two matching disks, NVMe present, held by dm, short device | STOP (tests) |
| Regular file as device outside test hook | STOP (test) |

## Findings

1. **Should-fix (fail-open):** `grep -Eq … "$MOUNTS" && stop …` stops only when
   grep succeeds. If `/proc/mounts` is unreadable (proc not mounted), grep
   returns 2 and the script proceeds as "not mounted". Fix: `[ -r "$MOUNTS" ] ||
   stop "cannot read mounts"` before the grep. It is read-only regardless.
2. **Hardening:** the node `/dev/$match` is never tied to the sysfs device. Add a
   comparison of `$SYS/block/$match/dev` (major:minor) with `stat -c '%t:%T'`
   of the node. On a devtmpfs initramfs it will match; it removes the
   assumption.
3. **Hardening:** each range is read twice (`dd | sha256sum`, then `dd | wc -c`);
   the hash is not tied to the counted read. A flaky device could pass the count
   on one read and hash a short/different stream on the other. Hash and count
   the same read (`tee` to a counter, or read into a temp file in RAM). The
   `|| stop` after `sha256sum` only tests `sha256sum`, not `dd`.
4. **Note:** the partition glob `"$match"[0-9]*` accepts any matching sysfs dir
   with a `start` file; real kernels expose `sda1`, so benign.
5. **Note (unverified assumption):** the controller gate requires a path of the
   form `*/392280000.usb/xhci-hcd.*`. `usb@392280000` in `t6040.dtsi` is a single
   dwc3 node (`apple,t8103-dwc3`), whose xhci child is `xhci-hcd.N.auto`, so the
   pattern is plausible, but the repo evidence confirms only `io mem 0x392280000`
   from ticket 108, not the sysfs path. If wrong the reporter STOPs (fails
   closed) and costs a rig cycle; check against the 108 boot log's
   `/sys/devices/…` path first if any exists.
6. **Note:** the `T6040_REPORT_*` environment hooks are honoured in production;
   keep them unset in the 109 init. Reading is `dd if=… of=/dev/stdout` only;
   no mount/write/fsck/ioctl.

## Commands run

```text
shasum -a 256 scripts/t6040-usb-block-report.sh scripts/t6040-test-usb-block-report.sh
sh scripts/t6040-test-usb-block-report.sh                  # 19 passed, 0 failed
bash adv.sh   # scratchpad: builds a fake sysfs and runs the reporter under the T6040_REPORT_* hooks:
              # baseline, mounts file missing, alias mount, sdaa1 mount, sda1x dir, slaves dir
grep -n -A25 'usb@392280000' ~/code/linux/arch/arm64/boot/dts/apple/t6040.dtsi
```
