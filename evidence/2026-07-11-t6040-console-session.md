# t6040 session 2026-07-11 — early kernel console on M4 raw-boot

Continuation of the Stage-C boot work. Goal: get a kernel console (we were blind:
logo, no text) and move toward a real boot. Driven by #asahi-dev IRC intel.

## The big realisation (why we were blind — it's not an M4 bug)

In **raw kboot**, once m1n1 jumps to the kernel, **no m1n1 code runs anymore**, so
nothing bridges the kernel's console to USB. Our two USB serials are m1n1's two
CDC-ACM pipes: **YG1 = proxy/console**, **YG3 = vuart**. The vuart only carries
bytes when the **hypervisor** drives it (`hv_vuart.c`) — so YG3 is silent the
instant m1n1 hands off. This is true on *every* Apple Silicon Mac. The old
`t6040-bootcap.sh` capture on YG3 could never have worked for raw kboot.

The usual fix (boot under `m1n1 hv`, which stays resident and relays the guest
console over USB) is **impossible on M4**: SPTM blocks the hypervisor, and Linux
can't run under SPTM at all (confirmed repeatedly on IRC — chadmed, NickChan,
JamesCalligeros). So on M4 the kernel must drive a **real** console:

- serial (`earlycon=s5l` / `ttySAC0`) — **dead on M4** (enverbalalic, t6041:
  "dockchannel is the only way to get logs out of it"). Our cmdline was using
  `console=ttySAC0` → guaranteed silent.
- **dockchannel-uart** (debugusb/KIS) — the real M4 serial, but needs a
  **DP-capable USB-C cable (SBU pins wired)** + `kisd` on the host, and yuka's
  kernel driver isn't upstream yet. We only have a plain tether → not available.
- **on-screen framebuffer console** (simpledrm + fbcon) — **the de-facto M4
  bring-up console.** mischa85 booted the sibling **t6041 to userspace** this way,
  no serial, no hv. THIS is our path.

## Root-causes of "logo, no text"

1. **No fbcon in the build.** defconfig ships `DRM=m`, simpledrm off, and even with
   DRM=y you need `DRM_FBDEV_EMULATION` + `FRAMEBUFFER_CONSOLE` for text to render.
2. **Boot CPU dies in idle-WFI before simpledrm probes.** "M4 loses CPU state on
   WFI/WFE" (mischa85/sven). The kernel's first idle hits WFI and the core is lost
   *before* fbcon comes up → blank. Fix: **`nohlt`** (Asahi kernel honors it on
   arm64). Our old cmdline had `idle=nop`, which is not enough.
   (The m1n1 `broken_wfi` patch only handles m1n1's *secondary* parking — it does
   NOT fix the kernel boot-CPU idle loop.)

Once the boot CPU survives idle, init reaches simpledrm, fbcon registers, and
`register_console` **replays the whole dmesg to the screen** → we see the full
boot log up to wherever it dies.

## Changes made this session (all build-verified)

### m1n1 (src/) — rebuilt: build/m1n1.bin, m1n1.macho
- **dapf gate** (`src/dapf.c`, `src/kboot.c`): replaced the whole-function
  `dapf_init_all()` skip with a surgical gate — skip only the `dart-aop`/`dart-isp`
  filters (the ones that raise the async L2C SError) on M4-family SoCs
  (`chip_id == T6040 || T8132`), keep dart-mtp/pmp. Matches yuka's t8132 fix.
  `dapf_init_all()` is called again (no longer commented out).
- **watchdog auto-reset** (`src/wdt.c`, `src/wdt.h`, `src/kboot.c`): new
  `wdt_arm_secs()`. `kboot_boot` arms the WDT for ~20s on M4-family before handoff.
  A hung kernel → **warm** reset → back to "Running proxy" (the auto-power-cycle we
  wanted) with **DRAM retained** (enables the RAM-dump fallback). Assumes 24 MHz
  WDT clock; tune `WDT_CLK_HZ` if the real timeout differs. NOTE: once the kernel
  boots far enough to run the apple_wdt driver (needs the /soc/wdt DT node), drop
  this arm or it'll reset a healthy system after 20s.

### kernel build (.plans/t6040-kbuild.sh)
- After defconfig, force the fbcon config: `DRM=y DRM_SIMPLEDRM=y
  DRM_FBDEV_EMULATION=y FB=y VT_CONSOLE=y FRAMEBUFFER_CONSOLE=y LOGO=y`, and
  **disable `ARM64_SME`** (breaks M4 boot). Also copies `System.map` to /out.
- Verified in the container: all set `=y`, `SME disabled OK`. Full Image rebuild
  was kicked off in the background this session.

### boot harness
- **`.plans/t6040-bootcap-fb.sh`** (new, use this instead of t6040-bootcap.sh):
  chainloads our m1n1, boots with
  `maxcpus=1 nohlt nokaslr pd_ignore_unused clk_ignore_unused console=tty0 ignore_loglevel`,
  and tells you to **read the laptop screen**. No serial capture (it can't work).
- **`.plans/t6040-ramdump.py`** (new, fallback): if the screen stays blank (hang
  before simpledrm), after the watchdog warm-reset lands on "Running proxy", dumps
  the kernel `__log_buf` from physical RAM via the proxy (`kernel_base` from
  linux.py + System.map offset, nokaslr) and strings it.

## WHEN YOU'RE BACK — test procedure

1. Confirm the kernel Image rebuilt: `ls -la ~/Code/linux-build-out/Image
   ~/Code/linux-build-out/System.map` (and `tail ~/Code/linux-build-out/build-fbcon.log`).
2. M4 should be on "Running proxy" (YG1). Then:
   `bash .plans/t6040-bootcap-fb.sh`
3. **Watch the laptop display.** Expected: the m1n1 logo is replaced by scrolling
   kernel text (full dmesg) once simpledrm/fbcon comes up. Photograph the last
   lines if it hangs. The watchdog warm-resets ~20s after a hang.
4. If the screen stays blank (hung before simpledrm even with nohlt): note the
   `Kernel_base: 0x...` linux.py printed, wait for the watchdog reset to "Running
   proxy", then:
   `M1N1DEVICE=/dev/cu.usbmodemJ22GYCN4YG1 python3 .plans/t6040-ramdump.py 0x<KERNEL_BASE>`
   → reads the console out of RAM. If that's garbage, DRAM didn't survive the reset
   and the only remaining path is debugusb (DP-capable USB-C cable + kisd).

## UPDATE (first on-HW test of this session)

Ran `t6040-bootcap-fb.sh`. Two results:
- **The framebuffer console WORKS** — m1n1's own EL2 exception dump rendered
  clearly on the laptop display. The on-screen console path is proven; we just
  didn't reach the kernel yet.
- **My dapf diagnosis was wrong.** The gate correctly skipped dart-aop, but the
  **identical** L2C SError still fired right after `dapf: Initialized dart-mtp`. So
  on **t6040 dart-mtp also SErrors** (t8132 only needed aop/isp). Fixed:
  `src/dapf.c:dapf_skip_entry` now skips **every** dapf entry on t6040 (the proven
  clean-handoff path); t8132 still skips only aop/isp. m1n1 rebuilt.
- linux.py threw `SerialException: Device not configured` — that's just the USB
  gadget vanishing when m1n1 SError-rebooted (not the normal handoff timeout). With
  dapf fully skipped m1n1 should now hand off cleanly instead of crashing.

Next: re-run `t6040-bootcap-fb.sh` with the rebuilt m1n1 → expect a clean handoff,
then watch the screen for the KERNEL's fbcon output.

## References / open items
- flokli owns the t6040 (J773s); m1n1 **PR #597** = initial T6040 support + a
  minimal DT booting maxcpus=1. Worth diffing our tree against it.
- yuka's M4 devicetrees merged to **asahi-wip** 2026-07-09 (`bits/000-devicetree`).
- yuka's dockchannel-uart earlycon driver (2026-07-09) not upstream yet; the future
  "proper" M4 serial console. debugusb self-enter is m1n1 **PR #594** (SPMI).
- Fallback console hardware: any DP-capable USB-C cable (SBU wired) + AsahiLinux/kisd.
</content>
