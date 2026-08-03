# Session log 2026-07-09 — m1n1 first light on M4 Pro (T6040)

Companion to `t6040-bringup-plan.md`. Outcome: **m1n1 boots to "Running proxy..." on the
MacBook Pro M4 Pro, first attempt.** Display console, AIC3, pmgr (485 devices), 3 USB
DARTs all initialized. Photo of boot log taken 2026-07-09 evening.

## What we established (research phase)

- Upstream m1n1 v1.6.0 already had initial T6040 support (commit `e706101`): chip-id,
  `EARLY_UART_BASE`, MIDR parts (Brava Chop), chickens stubs, SMP start offset guess.
- M4 must boot as a **raw boot object** (`kmutil --raw`); the mach-o path lands in an
  SPTM/GL2 environment that's unusable. Raw boot confirmed working on macOS 26.2
  firmware by a tester in upstream PR #604.
- Chicken-bit init fns are deliberately NULL on M4 — Apple sysregs are locked under
  raw boot; iBoot applies the chicken bits itself now.
- Hypervisor on M4 is limited (PR #604, "!apple_sysregs_unlocked"); XNU guests broken.
- PR #616 (proxyclient SPMI gen4 fix) still open — may need cherry-picking for shell.py.

## Machine facts (verified via ioreg on the target)

- Mac16,8 / J614sAP = MacBook Pro 14" M4 Pro, chip-id **0x6040**, board-id 0x04
- 14 cores: 4E + 10P. ADT quirks: arm-io compat is `arm-io,t6041` (shared Brava die),
  CPU compats reuse M3 names (`apple,everest`/`apple,sawtooth`). m1n1 keys on
  chip-id/MIDR, so no code impact.
- `EARLY_UART_BASE 0x429200000` verified: arm-io base 0x200000000 + uart0 reg
  0x229200000. ✔

## What we did

1. Built m1n1 on the target Mac. Two toolchain fixes needed:
   - rustup installed to `~/.local/share/cargo` (`--no-modify-path`) with the
     `aarch64-unknown-none-softfloat` target (Homebrew rust can't build stage 2)
   - `brew install lld` (Makefile hardcodes `/opt/homebrew/opt/lld/bin`)
   - Build cmd: `PATH="$HOME/.local/share/cargo/bin:/opt/homebrew/opt/llvm/bin:$PATH" make -j8`
2. Created APFS volume `m1n1` (space-shared, ~no cost), installed macOS Tahoe 26.x
   onto it, copied user settings.
3. From 1TR (power-button hold): `csrutil disable` + `bputil -n -v /Volumes/m1n1`
   (per-volume Permissive; main volume untouched, still Full Security).
4. From the m1n1-volume macOS:
   `kmutil configure-boot -c .../build/m1n1.bin --raw --entry-point 2048 --lowest-virtual-address 0 -v /Volumes/m1n1`
5. Rebooted into the m1n1 volume → **first light**. Log highlights: fb console
   3024x1964, `pmgr: initialized, 485 devices on 1 dies`, DARTs t8110 for usb0-2,
   `cpufreq: Chip 0x6040 is unsupported` (expected gap), `Running proxy...`.

## Next session TODO

- [ ] Second machine (any OS) with `pip install pyserial construct`; USB-C data cable;
      `export M1N1DEVICE=/dev/cu.usbmodem*` (or `/dev/ttyACM0`)
- [ ] `python proxyclient/tools/shell.py` — get a proxy prompt
- [ ] Cherry-pick PR #616 if proxyclient chokes on SPMI during init
- [ ] **SMP test**: start secondaries — validates `CPU_START_OFF_T6031` (0x88000)
      reused for T6040 at `src/smp.c:296`, the last unverified constant.
      All 14 cores up = goal met. Failure = hunt real PMGR offset (one-line fix).
- [ ] Verify `chainload.py -r build/m1n1.bin` works → fast dev loop, no more kmutil
- [ ] Report findings to #asahi-dev (OFTC) — T6040/j614s testers are scarce;
      confirm-or-fix of the SMP offset is upstreamable either way
