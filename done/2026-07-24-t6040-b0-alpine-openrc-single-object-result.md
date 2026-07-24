# T6040 B0 Alpine/OpenRC release single-object — LIVE PASS (2026-07-24)

Ticket 100 (rig, P1, distro). The **B0 release object** — the enrolled-boot
candidate with real OpenRC release userspace — chainloads from a single upload
and reaches a fully usable on-device Alpine login: internal **panel** shows the
shell and the internal **keyboard** echoes locally. This closes ticket 081 and
unblocks ticket 082 (reversible enrollment → untethered cold boot).

Maintainer-attended: CJ was at the machine and confirmed the panel + keyboard.

## What ran

- Object: `linux-build-out/m1n1-b0-alpine-openrc.bin`, SHA-256
  `2371ee5dfbfab591397fc333e7da212fb7582bfb2eaddaa6438005f5bb41759b`,
  22,183,563 B, entry 0x800 (author codex/sol; cross-reviewed by claude — strict
  verifier + 6-gate audit PASS, see
  `done/2026-07-24-t6040-alpine-openrc-single-object-preflight.md`).
- Components (all content-hash matched): safe m1n1 `1394c345`, 078 kernel
  `df7657c`/`d76463e5`, storage-disabled DTB `2782b922`, OpenRC root initramfs
  `ddd98171` (699 entries, 0 block nodes), bootargs `… rdinit=/sbin/init
  maxcpus=1 idle=nop` (no root/USB/SMP/cpufreq/PCIe/storage).
- Delivery: `scripts/t6040-boot-raw-object.sh` (venv-python fix, `6b435913`) →
  `chainload.py -r` once. No `linux.py`, no second payload/target command.
- Recovery reboot to a clean m1n1 proxy first; lease held by claude throughout;
  parked back to proxy + released healthy after.

## Result — all pass criteria met

Console-side (captured on `alpine-openrc-chainload.log`, the ttydc0 `TTY>`
stream held by chainload.py through the jump):

- **Embedded payload discovery + Linux handoff** — `Preparing to boot kernel at
  0x10007800000 with fdt at 0x1000ba04000`; kernel `Linux wallace-b0
  7.1.3-g96ac043df12f-dirty #3 SMP PREEMPT aarch64`.
- **OpenRC default runlevel + watchdog** — the default-runlevel health-report
  service ran begin→end and reported `watchdog0=present`.
- **Health report end marker + input0/event0** — `=== t6040 B0 health report
  begin === … === t6040 B0 health report end ===`, with
  `S: Sysfs=…/0019:05AC:0359.0003/input/input0`, `H: Handlers=sysrq kbd leds
  event0`.
- **`/proc/partitions` empty** — `-- partitions (must be empty) --` followed
  immediately by the next section (no device rows). No USB/NVMe/storage probe
  anywhere in the log.
- **No network runlevel** — `-- network runlevel (must be empty) --` empty.
- Reached `Alpine B0 RAM distro — local diagnostic shell (no persistence)`.

Maintainer-confirmed on the internal display + keyboard (the two criteria only
verifiable at the machine):

- **Panel** — the M4 internal display shows the Alpine B0 diagnostic shell.
- **Keyboard** — a line typed on the internal keyboard echoes on the panel.

Machine healthy: the only `SError` strings in the log are m1n1's expected
`dapf: Skipping /arm-io/dart-* (async L2C SError on this M4 SoC)` boot lines (a
normal M4 DART skip, not a fault); no kernel panic, DART fault, reset loop, or
watchdog-stop. The `Starting CPU 0..14` lines are m1n1 core bring-up; Linux
still honors `maxcpus=1`.

## Note — chainload.py exit status is cosmetic (as in 089)

`chainload.py` exited 1 on the trailing `iface.nop()` `UartTimeout`: the B0
object auto-boots without re-entering the m1n1 proxy, so there is no proxy for
`nop()` to poll after the jump. The full boot printing before the timeout is the
proof the payload ran.

## Significance / next

- This is the **release** object (real OpenRC userspace, on-device panel +
  keyboard console), not the 089 diagnostic control — so it **closes ticket
  081** and is the artifact the B0 enrollment path will enroll.
- Unblocks **ticket 082**: prepare (do not execute) the reversible enrollment /
  cold-boot procedure. Enrollment + cold boot are separate maintainer approvals
  (new risk class: `kmutil configure-boot --raw` / Boot Policy / APFS boot
  volume). No enrollment or APFS action was part of this control.
- Independent of Sol's USB-stick path (SPMI ladder), which remains the
  persistent-root route.

Ticket 100 done; ticket 081 closed (its release object passed the tethered
single-object proof).
