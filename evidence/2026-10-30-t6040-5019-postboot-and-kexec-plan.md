# 5019 post-boot checks and kexec follow-ups: offline plan (claude, 2026-10-30)

Offline and read-only. Nothing here was booted. It records why 5020 and 5021
were amended and why tickets for a kexec kernel trial and a crash-kernel design
were added.

**Merged with the on-device results (later the same day).** The on-device
session booted 5019
([5020 evidence](2026-10-30-t6040-5020-onboard-debug-kernel-boot.md)) before
this plan was pushed. Its live checks cover the planned read-only post-boot
ticket: identity, ramoops region and registration, pmsg 0, tracing, kprobes and
dynamic debug. That ticket was dropped, and its number, 5024, belongs to the
on-device `kexec-nrcpus-object`. The on-device session also replaced the pmsg
step with a `/dev/kmsg` marker (`scripts/t6040-onboard-pstore-reboot.sh`).
**One prediction here was wrong.** This plan said a `maxcpus=1` kernel would
not hit arm64's stuck-CPU kexec refusal. It does: Apple uses spin-table with no
`cpu_die`, and `maxcpus=1` still leaves CPUs 0-13 possible. 5024 adds
`nr_cpus=1`.

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
   configured and the region has no pmsg area (confirmed live: pmsg 0). The
   marker goes through `/dev/kmsg` and the console region instead.
4. **Only a crash kernel can preserve a panic record.** A kdump kernel loaded
   with `kexec -p` runs in place on panic, without iBoot, and can save pstore
   and `/proc/vmcore`. That is a design ticket, not a build. arm64's
   stuck-CPU refusal skips `KEXEC_TYPE_CRASH`
   (`machine_kexec_prepare`, read in
   `~/code/gravitylinux/linux/arch/arm64/kernel/machine_kexec.c:57`), so a
   crash kernel should load even on a `maxcpus=1` kernel without `nr_cpus=1`.
   This is unverified on the 5019 tree.
5. **Enrolling on `m1n1` replaces the DebugUSB rollback loader.** 5020's old
   text ("the m1n1 DebugUSB rollback volume stays enrolled") assumed a second
   boot volume.

## Region and tracing

Both are done live in 5020: reserved-mem `0x10300000000..0x103001fffff`,
ramoops registered, `function` tracer and a `do_sys_openat2` kprobe both hit.

## Ticket map

- **5020** amended: enrolled on `/Volumes/m1n1`, which replaced the rollback
  loader. A missing reboot marker is a finding, not a failure. Rollback is
  re-enrolling 5014 or the rollback object.
- **5021** amended: pstore-across-kexec check. It runs on the 5024 object.
- **5022**: no change. Its finished recipe (3c4a3ec) already pins `kexec-tools`.
- **5025** (rig, proposed): kexec kernel trial. New kernels go in through kexec,
  tester initramfs first, and nothing is enrolled.
- **5026** (offline): crash-kernel design.

5020's approval (CJ, 2026-10-30) is recorded with `queue approve`. It is not
runnable until the exact-artifact review and `queue ready`.
