# Independent review: ticket 217 fault-205 characterisation artifact

Reviewer: independent (non-builder) offline review, 2026-10-24. No rig, lease,
boot or build.

**Verdict: PASS-with-notes.** Hashes and the three Linux source citations
check out. Two honest caveats about what the artifact is a "control" for.

## Hashes (recomputed)

```text
a9a2096f…  Image-…-daily301.build{1,2} (identical);  93cfaa38… System.map;  96e83d85… config
30b01736…  t6040-j614s-dcuart.dtb
de1a5cd7…  initramfs-cow-report.build{1,2}.cpio.gz (identical)
545646a4…  scripts/t6040-init-cow-report      (= embedded /init)
25a62b52…  scripts/t6040-cow-repro.sh         (= embedded usr/local/bin copy)
0c7ff0b4…  scripts/t6040-build-cow-report-initramfs.sh
61781806…  embedded bin/busybox;  606ecd98… embedded etc/wallace-no.bmap
fa603bb1…  kbuild-control.log (says "building … at 2532b17125cb")
51199bfa…  smp-maxcpus14-console-20260729.log
```

The initramfs holds only `init`, `bin/busybox`, the keymap and the reproducer.
Preflight on the kernel plus initramfs: OK (warnings: no fsck.exfat, no WiFi
firmware, as expected for a storage-free image).

## Source citations at `4f2429104009` (read via `git show`)

- `arch/arm64/kernel/traps.c:191` is `show_regs(regs)` inside `__die`. ✓
- `arch/arm64/kernel/process.c:221` is `show_regs_print_info(KERN_DEFAULT)` in
  `__show_regs`. ✓
- `lib/dump_stack.c:86-88` `show_regs_print_info → dump_stack_print_info`;
  `:55-58` prints `CPU: %d UID: %u PID: %d Comm: …` with `raw_smp_processor_id()`. ✓
- `arch/arm64/kernel/smp.c:252` `CPU%u: Booted secondary processor 0x%010lx
  [0x%08x]`; `setup.c:95` `Booting Linux on physical CPU 0x%010lx [0x%08x]`. ✓
- The 07-29 log has `Booting Linux on physical CPU 0x0000010100 [0x611f0551]`,
  `CPU1: Booted secondary … [0x611f0541]`, and `CPU: 6 UID: 0 PID: 109 …` (line
  218). ✓ (that log is from tree `246843ff67a8-dirty`, not `4f24291`; the
  mechanism is the same generic arm64 code, but it is not the same build.)

## Hardware-operation scope

Default DTB: `nvme@44dcc0000`, `spmi@509014000`, `smc@50c600000` and all three
USB controllers are `disabled`; `hid@514600000` is `okay`. The init mounts
proc/sysfs/devtmpfs only, reads sysfs and runs the unchanged reproducer; no
block device, no SMC/SPMI, no firmware write. ✓

## How it could be wrong

1. *"Uninstrumented control" is not minimal.* `daily301` carries the trackpad
   stack, PPP, the `hid@514600000` node and the dockchannel/MTP coprocessor boot.
   Any fault-205 sensitivity to those would be baked into the "control". The
   artifact note already says the fault rate must be re-baselined, which I accept;
   it should also say the control is "daily-feature", not "bare".
2. *Missing HID firmware.* The 217 initramfs omits `tpmtfw-j614s.bin`, unlike the
   230 fixture. The HID node still probes (coprocessor/mailbox traffic that 207/208
   also had); the firmware is requested at `open()` per ticket 230, which the init
   never does. Not a new hardware op, but the behaviour differs from 230 and from
   a daily boot (where the blob exists).
3. *Empirical evidence from a different tree.* See above.

## Notes

- The earlier control Image really was overwritten: the unsuffixed
  `Image-…-cpufreq` (Aug 3 18:26, `Linux version 7.1.3-g4f2429104009-dirty`) is
  not the 2532b17 build named in `kbuild-control.log`. No byte-exact 208 control
  survives. ✓

## Commands run

```text
shasum -a 256 initramfs-cow-report.build{1,2}.cpio.gz scripts/t6040-{init-cow-report,cow-repro.sh,build-cow-report-initramfs.sh} t6040-j614s-dcuart.dtb smp-maxcpus14-console-20260729.log kbuild-control.log
gunzip -c initramfs-cow-report.build1.cpio.gz | cpio -idm; shasum -a 256 init bin/busybox etc/wallace-no.bmap usr/local/bin/t6040-cow-repro.sh
scripts/t6040-image-preflight.sh --kernel Image-…daily301.build1 --initramfs initramfs-cow-report.build1.cpio.gz
git show 4f2429104009:{arch/arm64/kernel/traps.c,process.c,smp.c,setup.c,lib/dump_stack.c} | sed -n …
dtc -I dtb -O dts t6040-j614s-dcuart.dtb; status walk
grep -n 'CPU: [0-9]* UID' smp-maxcpus14-console-20260729.log; grep -n 'Linux version' kbuild-control.log; strings -a Image-…-cpufreq | grep 'Linux version'
```
