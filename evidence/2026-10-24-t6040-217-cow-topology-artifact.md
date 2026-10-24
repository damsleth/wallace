# Ticket 217: storage-free fault-205 characterisation artifact

Claude, 2026-10-24. Offline build and source review only. No kernel
instrumentation and no hardware access.

## The original control Image is gone

Ticket 208's uninstrumented control was built on 2026-08-03 10:06 from Linux
`2532b17125cb` as `Image-macsmc-hid-type-fix-trackpad-nbcon-ppp-cpufreq`
(kbuild log `kbuild-control.log` `fa603bb1…`, pinned in 208). It was never
hash-pinned. That unsuffixed name was overwritten at 18:26 the same day by a
`4f2429104009` build; the file now reports
`7.1.3-g4f2429104009-dirty`. **No byte-exact 208 control exists.**
Artifact builds must always use `ARTIFACT_SUFFIX`.

## New pinned control

The uninstrumented, two-build-reproducible daily kernel from ticket 301:

```text
a9a2096ff47cc8538090ad28cd0bc41b75b09354e90abff8135b3d242d987bc8  Image (…-daily301.build{1,2}, identical)
93cfaa38bc4b3906485b66d0f081a30d8963c46fd9d7d75a2c100a3a39fbc253  System.map
96e83d858ddbbcf19027d3ea56411158f75ae75fe4c42c0b03dbdd28b6da3eee  config
30b01736b5291aaa864f37f73192ec9877da97ab8ecf5d72c1ca92cf9c8af05d  t6040-j614s-dcuart.dtb (default DTB, as in 230)
de1a5cd79e030468bff7f7f1fccaf03f2e34d705a4dc77a5aedd927d94fc9b29  initramfs-cow-report.build{1,2}.cpio.gz (identical)
545646a453287d7574d612eff41bfdab160e76aa1ad738756324a8ead634f385  scripts/t6040-init-cow-report
25a62b522ea83234393e7205e1d968ed40983b23359ca187545899f99804d209  scripts/t6040-cow-repro.sh (unchanged)
0c7ff0b4f437ec2a095b6e9279f7599ef0e19d9d4c2192eb7575162ac670c8f8  scripts/t6040-build-cow-report-initramfs.sh
```

This is also the kernel criterion 9's "stable with more than one CPU" must
eventually run. It differs from the lost control in tree (`4f24291` vs
`2532b17`), so its fault rate must be re-baselined at maxcpus=2 before any
comparison with the 207/208 counts.

## The initramfs

It contains only BusyBox 1.35 (`61781806…`), the Norwegian keymap
(`606ecd98…`, loaded before anything else), `/init` and the unmodified
reproducer. The init mounts proc/sysfs/devtmpfs only and touches no block
device. It logs `cmdline`, the possible/present/online sets, each online
logical CPU's `midr_el1`, cluster, core and package from sysfs, and the
kernel's boot lines. It then runs the reproducer four times in the same boot
with per-run BEGIN/END markers, all via `/dev/kmsg` so it interleaves with
the kernel's oops output on ttydc0, and idles at the end. Preflight is OK.
The warnings are expected: no fsck or WiFi firmware in a storage-free
diagnostic, and `maxcpus>1` by design.

## The stock kernel already names the CPUs (source at 4f2429104009)

- `die → __die → show_regs → __show_regs` (`arch/arm64/kernel/traps.c:191`,
  `process.c:221`) → `show_regs_print_info → dump_stack_print_info`
  (`lib/dump_stack.c:86-88, 55-58`) prints
  `CPU: %d UID: … PID: … Comm: …` with `raw_smp_processor_id()`, the
  logical CPU of the faulting context.
- `arch/arm64/kernel/smp.c:252` prints
  `CPU%u: Booted secondary processor 0x<MPIDR> [0x<MIDR>]`, and `setup.c:95`
  prints the boot CPU's line. Together they give logical → MPIDR/MIDR.
- Empirically, `smp-maxcpus14-console-20260729.log` (`51199bfa…`) shows the
  boot CPU `0x0000010100 [0x611f0551]`, secondaries with MIDR `…0541`, and
  oops lines such as `CPU: 6 UID: 0 PID: 109 …`.

So 209 needs no instrumentation: the oops names the victim's logical CPU and
the boot/sysfs lines name its MPIDR, MIDR and cluster.

## Zero-new-hardware-operation note for 209

Nothing here adds a hardware write. The kernel is the reviewed daily feature
set, the DTB is the existing default dcuart DTB, and the initramfs performs
only proc/sysfs reads and user-space page copies. 209's existing controlled
online-set DTBs and maxcpus discipline apply unchanged. An independent
reviewer must still confirm this before 209 is readied.
