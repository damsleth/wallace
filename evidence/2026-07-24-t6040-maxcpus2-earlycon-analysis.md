# T6040 maxcpus=2 no-console analysis and replacement (ticket 122)

Date: 2026-07-24  
Scope: offline source/log analysis and storage-disabled artifact build. No rig
or target transaction occurred.

## Result

Ticket 005 must not be retried unchanged. It proved only that enabling a second
Linux CPU correlates with a failure after m1n1 vectors to the kernel and before
the normal polling DockChannel TTY emits anything. It did not prove which
secondary-start phase failed.

The smallest replacement is a direct, TX-only early console using only the
already-live-proven DockChannel data registers. It exposes printk before the
mailbox/TTY probe and keeps that console through init so a kmsg-only reporter
can identify whether Linux logical CPU 1 reached online/task execution.

## Source and topology findings

### Repeated `maxcpus`

The exact kernel's `kernel/smp.c` registers `maxcpus()` as an `early_param`.
Each occurrence overwrites `setup_max_cpus`; the command-line parser visits
parameters left to right. Therefore the harness's:

```text
maxcpus=1 ... maxcpus=2 ...
```

ends at two. A repeated argument is untidy but not the cause of ticket 005.
The replacement still records the complete effective command line.

### Physical boot CPU

The previous preflight incorrectly called DT `cpu@0` the boot CPU. Live m1n1
evidence shows the physical boot CPU is P-core `smp_id 4`, MPIDR
`0x80010100`. Arm64 matches that MPIDR and assigns it Linux logical CPU 0.
The first other enabled node in DT order is E-core `smp_id 0`, expected as
Linux logical CPU 1.

m1n1 has already started and execute-and-return tested all 13 secondaries.
Its kboot logs populate valid spin-table release addresses for every active DT
CPU and disable only fused `smp_id 9`. The existing `broken_wfi` handling parks
secondaries in WFE. The kernel build retains `idle=nop` and the two T6040 AIC
locked-sysreg skips. These facts clear obvious topology/release prerequisites,
but do not prove Linux secondary init succeeds.

### Blind interval

Ticket 005's final m1n1 line is `Vectoring to next stage...`; no Linux text
follows. The regular `apple_dctty_init` path occurs much later at device init.
The first useful boundary is therefore printk from early arm64/SMP setup,
before mailbox and TTY probe.

## Early DockChannel design

Patch `t6040-dockchannel-earlycon-debug.patch` adds an
`EARLYCON_DECLARE(dockchannel, ...)` implementation to the existing
DockChannel TTY source.

The explicit earlycon mapping is the known J614s data window
`0x50882c000`. Each output byte:

1. reads 32-bit `TX_FREE` at `+0x14`;
2. immediately drops the byte if no slot is free;
3. otherwise writes the byte with the proven 32-bit `TX8` accessor at `+0x4`.

There is no wait loop, RX, interrupt/config access, new offset, SPMI, PCIe,
USB-host, or storage operation. Losing text is preferable to delaying boot
when DebugUSB is absent.

`keep_bootcon` retains the early console after fbcon registration.
`initcall_blacklist=apple_dctty_init` suppresses the normal UART TTY client so
there is never a second TX FIFO owner. This exact symbol is proved by
`System.map`; `apple_dockchannel_driver_init` is the separate mailbox
controller and is not the blacklist target.

## Exact artifact set

The kernel was built from a new dedicated container tree
`/build/linux-dcuart-earlycon-v2` using the current harness and patch, not the
earlier reused build directory.

| Input | Size | SHA-256 |
|---|---:|---|
| safe m1n1 `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | — | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `Image-dcuart-earlycon` | 53,303,808 | `0c1811804ac6cca6f3c539b7b513f3463ebf4ab9868ae8e35d49dcc19118b9ac` |
| `System.map-dcuart-earlycon` | 10,002,510 | `f926a2af144811ffb09df587ce1177c209d6022449a535d4b00846010597b7fc` |
| `config-dcuart-earlycon` | 322,007 | `27c615803298a366e93c1858caaf4ad6ce95db7dfcbff51ecd404d980f6f4228` |
| `t6040-j614s-dcuart.dtb` | 51,659 | `2782b92237c35c8950212207391c3ae28c44b6b9c635b2e864c5748a77bb3cce` |
| `initramfs-smp-kmsg-report.cpio.gz` | 987,211 | `43944ef26f93eb52558cda5d4283007b4af5fa2c30715bccae07a5824dec7149` |
| second initramfs build | 987,211 | `43944ef26f93eb52558cda5d4283007b4af5fa2c30715bccae07a5824dec7149` |
| earlycon patch | — | `c70a9b2c215be2212d7794f8895b707fc54759c99baf7b9e20c68a7b4facd725` |
| reporter source | — | `b9884700bcad261084bc2995e49abcb95b18874555b6569a6238e625e80c40a6` |
| build harness | — | `ac2140b5b1a83435857db72401858071b10ce3c5c0bfaca89c46576d1874c1ea` |

The two current-source initramfs builds compare byte-for-byte. Its embedded
`/init` matches the reporter source, is root-owned mode 0755, and the archive
contains no block or character device nodes. The config has `CONFIG_SMP=y`,
`CONFIG_SERIAL_EARLYCON=y`, `CONFIG_APPLE_DOCKCHANNEL=y`, and
`CONFIG_APPLE_DOCKCHANNEL_TTY=y`.

The DTB is the storage-disabled base: ANS/SART/NVMe and all USB/DART paths are
disabled, with no PCIe or SPMI experiment enabled.

Independent review reproduced every hash and the two-build initramfs identity,
confirmed the one-read/drop-or-write TX semantics and exact blacklist symbol,
and recorded **PASS** for this bounded candidate. It also found and corrected
one loose staging copy of the reporter; the reviewed archive already contained
the current source, and the loose copy now matches it for future rebuilds.

## Exact proposed ticket-123 command line

Append exactly:

```text
maxcpus=2 earlycon=dockchannel,mmio32,0x50882c000 keep_bootcon initcall_blacklist=apple_dctty_init
```

to the standard storage-disabled harness arguments. The final
`maxcpus=2` wins. The early console is the only UART TX owner; the reporter
writes its bounded CPU mask/count, CPU-1 `taskset` proof, and dmesg tail to
`/dev/kmsg`, then sleeps while the watchdog remains serviced.

## Pass, stop, and authorization

Pass requires early Linux text, online mask `0-1`, processor count 2, a task
observed on Linux CPU 1, explicit `T6040_SMP_EARLY_RESULT_PASS`, watchdog
stability, and no forbidden probe.

Any early exception identifies the actual failing phase and is a useful
negative result. Stop on lost KIS drainage, watchdog reset, SError, DART,
storage/USB/PCIe/SPMI probe, missing earlycon registration, or a command-line
mismatch. Recover directly to the known proxy; never retry unchanged after a
negative.

Ticket 123 was created after the maintainer's previous approve-all action and
remains proposed. Even after independent artifact review, no live run is
authorized until the maintainer explicitly approves 123 and the normal
lease/healthy-proxy gate passes.
