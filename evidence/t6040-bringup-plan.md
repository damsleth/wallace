# m1n1 bring-up plan: M4 Pro (T6040) → proxy prompt

Goal: m1n1 boots on an M4 Pro Mac to a working USB proxy with all CPU cores online.
Target machine is a daily driver — everything below is confined to a separate APFS
volume with trivial rollback; the main macOS install and its Full Security are untouched.

## 0. State of the world (as of 2026-07, m1n1 v1.6.0)

Already in your checkout (`git log e706101`, plus the T8132 groundwork):

| What | Where |
|---|---|
| Chip id `T6040 0x6040` | `src/soc.h:33` |
| `EARLY_UART_BASE` for T6040 (`0x429200000`) | `src/soc.h:56` |
| MIDR parts Brava Chop E/P core (0x54/0x55) | `src/midr.h:48-49` |
| chickens table entries — **init fn is NULL**, `features_m4` is a stub (`sleep_mode = SLEEP_NONE`, "XXX figure out features") | `src/chickens.c:111-116,156-157` |
| SMP start offset: T6040 → `CPU_START_OFF_T6031` (0x88000) | `src/smp.c:296` |
| pmgr support for M4 Pro/Max (upstream PR #578, in v1.6.0) | `src/pmgr.c` (ADT-driven) |

Missing for this goal: nothing *known* — the pieces above are the proxy-prompt
prerequisites, but T6040 has had far less real-hardware testing than T8132, so
expect to validate rather than to write large amounts of new code. Missing for
later goals (Linux boot): cpufreq cluster tables, `mcc,t8132`-family layout,
`apcie` entries, ISP, GPU FDT init, all Python-side chip knowledge.

The hard constraint on M4: the **mach-o boot path is gone**. iBoot on M4 drops
mach-o kernels into an SPTM (Secure Page Table Monitor, GL2) environment with the
MMU already on — unusable for m1n1/Linux. The **raw boot object** path works and is
what all M4 m1n1 work uses, but Apple-private sysregs (GXF, virt extensions, most
`SYS_IMP_APL_*` chicken registers) are locked there. That's *why* the chicken init
fns are NULL — leave them NULL; writing those regs would trap. Consequences:
- Proxy + Linux: fine.
- Hypervisor: only via the "!apple_sysregs_unlocked" work (upstream PR #604); XNU
  guests remain broken. Out of scope here.
- macOS version: install the latest macOS 26. Raw boot confirmed working on M4
  (T8132, macOS 26.2 firmware) per tester in upstream PR #604 (2026-07); the
  mach-o path fails there ("Failed to find __TEXT segment"), so `--raw` is the
  only path regardless. Same tester needed PR #616 cherry-picked for
  proxyclient on T8132 — check its merge status.

## 1. Phase 0 — dev environment (one-time)

**Host side.** You need a second device to drive the proxy. Any machine works,
including another Mac: `pip install pyserial construct`, device shows up as
`/dev/cu.usbmodem*` (macOS) or `/dev/ttyACM0` (Linux). Set
`export M1N1DEVICE=/dev/cu.usbmodemXXXX`. A plain USB-C↔USB-C cable, target's
left/rear port preferred (check ADT if the first port doesn't enumerate).

**Build.** On this Mac: `brew install llvm imagemagick`, then in the repo:
```sh
make -j8            # → build/m1n1.bin, build/m1n1-raw.elf
```
v1.6.0+ needs Rust (rustup, aarch64 target) for stage-2/chainload builds; for the
proxy-prompt goal the plain `make` stage-1 binary is enough.

**Target volume (daily driver, reversible).**
1. Disk Utility → add APFS volume "m1n1" to the internal container (no
   partitioning; shares space).
2. Install the latest macOS 26 onto it (full installer, point it at "m1n1").
   This must be a real macOS install — `kmutil` enrolls custom kernels into a
   volume's Boot Policy, so the volume needs one. Raw boot is confirmed on
   macOS 26.2 firmware (see above).
3. Boot into 1TR (hold power button → Options), Utilities → Terminal:
   ```sh
   csrutil disable          # choose the m1n1 volume when prompted
   bputil -n -v /Volumes/m1n1   # Permissive Security — m1n1 volume ONLY
   ```
   Your main volume's Full Security is per-volume and unaffected.
4. Boot the m1n1-volume macOS, then enroll m1n1 as its "kernel":
   ```sh
   kmutil configure-boot -c build/m1n1.bin --raw --entry-point 2048 \
       --lowest-virtual-address 0 -v /Volumes/m1n1
   ```
   `--raw` is mandatory on M4 (see SPTM note). Re-run after every m1n1 rebuild —
   or better, only ever enroll a known-good m1n1 once and iterate with
   `proxyclient/tools/chainload.py -r build/m1n1.bin` over USB.

**Rollback:** boot picker → main volume; delete the m1n1 volume in Disk
Utility when done. Nothing else to undo.

## 2. Phase 1 — first light

1. Boot picker (hold power) → m1n1. Screen should show the m1n1 banner +
   ADT summary.
2. From the host: `python proxyclient/tools/proxyclient_shell.py` (or
   `picocom` on the ACM1 virtual UART for the console).
3. If the screen stays black: fall back to serial. Apple Macs expose a UART over
   USB-C PD VDMs — from another Mac run `macvdmtool serial` (github.com/AsahiLinux/macvdmtool)
   on a Thunderbolt cable into the target's DFU port, and build m1n1 with early
   UART: uncomment `#define TARGET T6040` in `config.h` (this wires
   `EARLY_UART_BASE` into `src/start.S` so you get output before ADT parsing).

Triage order for a silent boot, based on what's untested on T6040:
- `EARLY_UART_BASE 0x429200000` wrong → no early output at all. Verify against
  the ADT (`/arm-io/uart0` reg + arm-io base) dumped from macOS on the same
  machine, or ask upstream (@yuyuyureka did the T8132/T614x work).
- Hang before banner → usually an errant `SYS_IMP_APL_*` access trapping under
  locked sysregs; bisect with early-UART prints in `_start`/`init_cpu()`.
- Banner but no USB → ADT USB paths differ; compare `/arm-io/atc-phy*`/`dwc3*`
  node names with what `src/usb.c` expects.

## 3. Phase 2 — all cores online

`smp_start_secondaries()` uses the `CPU_START_OFF_T6031` guess (`src/smp.c:296`).
From the proxy:
```py
proxyclient> smp.start_secondaries()   # or run tools/smp test
```
- All 14 (or 12, binned) cores report in → done, this phase was free.
- Secondaries don't come up → the PMGR `CPU_START` offset guess is wrong. Find
  the real one: dump the ADT `/cpus` + pmgr nodes, or trace macOS's startup writes
  on T8132 precedent (T8132 uses the T8112 offset 0x34000; T6040 inheriting the
  T6031 offset 0x88000 is plausible but unverified). Fix is a one-liner in
  `src/smp.c` + mirror in `proxyclient/m1n1/hv/__init__.py:1563` if you later
  use the hv.
- Also sanity-check `features_m4`: `sleep_mode = SLEEP_NONE` means no deep-WFI —
  correct/safe for now. Don't enable AMX/SPRR/fast-IPI flags without testing;
  those gate sysreg writes that may trap on raw-boot M4.

## 4. Phase 3 — prove the proxy is solid

The "bootable" acceptance test:
```sh
python proxyclient/tools/chainload.py -r build/m1n1.bin   # reload m1n1 over USB
python proxyclient/tools/shell.py                          # peek/poke MMIO, read ADT
```
Both working reliably across reboots = goal met. From here the dev loop never
touches kmutil again — edit, `make`, `chainload.py`, ~10 s.

## 5. Phase 4 (optional) — upstream what you learned

Anything you had to fix is valuable upstream because T6040 testers are scarce:
- Corrected `CPU_START_OFF` / `EARLY_UART_BASE` values.
- `features_m4` findings (relevant: open PR #603 "fetch and parse cpu_features").
- A `docs`-style note on which macOS/iBoot version raw boot works with.
Coordinate on #asahi-dev (OFTC) / GitHub before writing code beyond fixes — the
M4 effort is active (progress report 2026-06: "laying the groundwork for M4").

## 6. Explicitly out of scope (and what each would add)

- **Linux boot**: cpufreq cluster tables (`src/cpufreq.c`), MCC (`src/mcc.c`),
  PCIe (`src/pcie.c`), display reserved-regions + `apple,t6040` FDT compatibles
  (`src/kboot.c`), ATC tunables, kernel-side devicetrees. Weeks of work, most of
  it paralleling what M3 needed (commit trail: `83364d0`→`5393f41`).
- **Hypervisor**: track upstream PR #604; blocked for XNU guests by SPTM.
- **T6041 (M4 Max)**: zero code exists anywhere in the tree.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Raw boot broken on current macOS/iBoot (regression seen on ≥15.2 in 2025) | Pin m1n1 volume's macOS to a version confirmed by M4 devs before debugging |
| T6040 constants (`CPU_START_OFF`, `EARLY_UART_BASE`) are untested guesses | Phase 1/2 verify them against the machine's own ADT; fixes are one-liners |
| Chicken-bit sysregs locked → can't fix errata | Accept; upstream ships NULL init for M4 and boots anyway |
| kmutil enrolls a broken m1n1 → volume won't boot | Boot picker still works; re-enroll from main volume or delete m1n1. Main volume never at risk |

## References

- m1n1 user guide: https://asahilinux.org/docs/sw/m1n1-user-guide/
- Tethered boot doc: https://asahilinux.org/docs/sw/tethered-boot/
- Platform/boot intro: https://asahilinux.org/docs/platform/introduction/
- M4 SPTM findings (Sven Peter): https://social.treehouse.systems/@sven/114278224116678776
- Upstream M4 PRs: #507, #536 (T8132 SMP), #578 (M4 Pro/Max pmgr), #603, #604
- M3 bring-up commit trail (template): 83364d0, 0753d8e, 09db6f3, a925356, c45da55
