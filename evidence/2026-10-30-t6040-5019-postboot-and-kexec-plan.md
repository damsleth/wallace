# 5019 post-boot checks and kexec follow-ups: offline plan (claude, 2026-10-30)

Offline and read-only. Nothing here was booted. It records why 5020 and 5021
were amended and why tickets for post-boot checks, a kexec kernel trial and a
crash-kernel design were added.

## Facts checked in the repo

| fact | source |
|---|---|
| 5019's ramoops node: `reg = <0x103 0x0 0x0 0x200000>`, `no-map`, record 0x20000, console 0x40000, ftrace 0x40000, **no `pmsg-size`** | `dts/t6040-j614s-dcuart-wifi-cpufreq-nvmeroot-ramoops.dts` |
| `T6040_ONBOARD_DEBUG=1` asserts FTRACE FUNCTION_TRACER DYNAMIC_FTRACE KPROBES KPROBE_EVENTS DYNAMIC_DEBUG IKHEADERS PSTORE PSTORE_RAM PSTORE_CONSOLE. **PSTORE_PMSG and PSTORE_FTRACE are not asserted** | `scripts/t6040-kbuild.sh` (`onboard_syms`) |
| A warm reboot scrubs or re-keys DRAM: `__log_buf` read back all zeros at its verified physical address | `evidence/2026-07-30-t6040-daily-driver-object-c1529d4c.md` ("Why NO trackpad firmware") |
| Reboot on the NVMe-root kernels ends in a watchdog reset through iBoot | `evidence/2026-10-25-t6040-5008-A-B.md` |
| `m1n1` is the only boot volume. `/Volumes/wallace` is the old name of the exFAT `linux` partition | CJ, 2026-10-30; `docs/RUNBOOK.md` §10 |

## Consequences

1. **pstore cannot be expected to survive a reboot or a power cycle.** If the
   2026-07-30 result holds for this path, every reboot goes back through iBoot
   and clears the ramoops region. A hard power cycle loses DRAM outright. The
   partition README's "hard power cycle, then read the crash record" is
   therefore not expected to work. 5020 keeps one reboot retention check, and
   an empty result is a finding, not a failure.
2. **kexec does not go through iBoot,** so the first kernel's
   `console-ramoops-0` should be readable in the second kernel. 5021 gains
   that check. It is the first positive test of ramoops on this machine.
3. **5020's `/dev/pmsg0` marker step cannot pass as written.** PMSG is not
   configured and the region has no pmsg area. It is replaced by the
   retention check above.
4. **Only a crash kernel can preserve a panic record.** A kdump kernel loaded
   with `kexec -p` runs in place on panic, without iBoot, and can save pstore
   and `/proc/vmcore`. That is a design ticket, not a build.
5. **Enrolling on `m1n1` replaces the DebugUSB rollback loader.** 5020's old
   text ("the m1n1 DebugUSB rollback volume stays enrolled") assumed a second
   boot volume.

## The `/proc/iomem` check

With a `no-map` region the ramoops driver may map it without requesting a
named resource. The range can therefore show as `reserved` rather than
`ramoops`. The dmesg lines are the primary check:

    ramoops: using 0x200000@0x10300000000, ecc: 0
    pstore: Registered ramoops as persistent store backend

`/proc/iomem` (as root) must show `10300000000-103001fffff` inside a
System RAM range, overlapping no kernel code, data or other reserved range.

## Tracing check

Boot-time ftrace already patches every mcount site, so a booted kernel has
proven that text patching works. The first tracer enable is still kept small:
one kprobe on `do_sys_openat2`, then the function tracer with a one-symbol
filter, with CJ present the first time.

## Ticket map

- **5020** amended: enroll on `/Volumes/m1n1` or kexec in from 5014. A
  reboot retention check replaces the pmsg step. Rollback is re-enrolling
  5014 or the rollback object.
- **5021** amended: pstore-across-kexec check, CPU-offline note.
- **5022** amended: `kexec-tools`, plus optional pstore/tracefs mounts.
- **5024** (offline, onboard): read-only post-boot checks on the running 5019
  kernel (identity, ramoops region, pstore, tracing, dynamic debug, baseline).
- **5025** (rig, proposed): kexec kernel trial. New kernels go in through kexec,
  tester initramfs first, and nothing is enrolled.
- **5026** (offline): crash-kernel design.

5020's approval (CJ, 2026-10-30) is recorded with `queue approve`. It is not
runnable until the exact-artifact review and `queue ready`.
