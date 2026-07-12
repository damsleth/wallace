# t6040 (M4 Pro, Mac16,8 / J614s) Linux bring-up — DEVLOG & operational reference

State of the world, how to operate the rig, solved blockers, investigation
history, and dead ends. Forward-looking work lives in `NEXT_STEPS.md`; the
long-term plan in `roadmap.md`; per-session write-ups in `done/`.

## Current working state (2026-07-12)

| Works | Notes |
|---|---|
| Mainline Linux (7.2-rc2 + 3 small patches) to BusyBox userspace | minimal DT, maxcpus=1, reproducible |
| Two-way m1n1 proxy/console over DebugUSB (KIS) | one DP/TB cable in the DFU port; no second machine-side cable needed |
| Two-way **Linux shell** on `/dev/ttydc0` over the same cable | poll-mode dockchannel driver; full remote dev loop, no screen-reading |
| Internal keyboard (+trackpad registers) at the shell | dockchannel-HID; trackpad start currently fails |
| Framebuffer console (simpledrm + fbcon) | the early-boot console; dcuart covers post-probe |
| Linux `apple_wdt` takes over m1n1's watchdog | shell survives past the 20 s bite |
| Remote reboot via `macvdmtool` | full autonomous reboot→chainload→boot→shell cycle |

Active: full PMGR topology boots reproducibly with the exact minimal raw-boot
policy; only its upstream shape remains (see PMGR section).
Trackpad firmware loading is implemented; provisioning the paired J614s blob is
next. Parked: USB gadget console (EP0 dies post-enumeration;
`done/2026-07-11-t6040-usb-gadget-plan.md`).

## Operating the rig

### The DebugUSB (KIS) link

`bash ~/Code/wallace/scripts/t6040-debugusb-console.sh [reboot]` — starts kisd, enters
DebugUSB via `sudo -n macvdmtool [reboot] debugusb`, symlinks the kisd pty to
`/tmp/m1n1`. `M1N1DEVICE=/tmp/m1n1` for all proxyclient tools; `screen /tmp/m1n1`
for an interactive console. kisd auto-detects the t6040 KIS base 0x548700000;
kisd uart channel 0 = dock side of AP `/arm-io/dockchannel-uart` (AP data block
0x50882c000 + 0x40004000 = 0x548830000; same offset on t8140).

**Hard-won operational rules (skip these and the link "dies"):**
1. **A reader must be attached to the kisd pty at (almost) all times.** With
   nobody reading, ~15 KB of boot output fills the pty buffer, kisd blocks, and
   the KIS stream wedges into an apparently one-way link (writes ACK at the USB
   level, nothing ever returns). Recovery: `pkill kisd`, restart kisd, re-enter
   `sudo -n macvdmtool debugusb`, attach `cat` immediately.
2. **Never leave a `cat` running while a proxyclient tool uses the pty** — it
   steals reply bytes. Sequence: kill reader → run tool → reattach reader.
3. First proxy attempt after a boot often hits `UartCMDError` (desync from
   leftover console bytes) — **just retry once**.
4. Reboot → "Running proxy" takes **<20 s**. Poll every 2–3 s; never wait minutes.
5. DebugUSB replaces m1n1's dwc3 gadget on the DFU port (no `/dev/cu.usbmodem*`
   while active). A plain cable in another target port coexists for fast
   chainload.
6. `t6040-boot-dcuart.sh` passes linux.py `--no-tty`, then owns the raw reader
   transition itself. Older m1n1 trees lack that option and end handoff with a
   harmless miniterm/termios traceback after the kernel is already booting.
   Live-verified with build #15: linux.py exits normally, the helper attaches
   its reader immediately, and BusyBox arrives without traceback noise.

Host prerequisites: root-owned `/usr/local/bin/macvdmtool` (patched fork at
`~/Code/macvdmtool`: new cmds `actions`/`vdm`/`dven`/`localserial`) with a
NOPASSWD sudoers entry; `/usr/local/bin/kisd` (AsahiLinux/kisd, builds on macOS
as-is). proxyclient pty support is committed (`proxyclient: support pty devices`).

### Boot recipes

**Linux with the DockChannel shell (the standard loop):** target at m1n1
"Running proxy" with kisd attached →
`bash ~/Code/wallace/scripts/t6040-boot-dcuart.sh` (defaults:
`t6040-j614s-dcuart.dtb` + `initramfs-dcuart.cpio.gz`). Chainloads
`build/m1n1.bin`, uploads over the pty, hands off, attaches a reader. Console
tails to `~/Code/linux-build-out/dcuart-console.log`; type with
`printf 'cmd\n' > /tmp/m1n1`.

**Framebuffer-console variant (for pre-userspace debugging):**
`bash ~/Code/wallace/scripts/t6040-bootcap-fb.sh <dtb> <initramfs>` over a plain-cable
proxy (`/dev/cu.usbmodemJ22GYCN4YG1`). Output on the laptop panel. Cmdline:
`maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0
fbcon=font:TER16x32 ignore_loglevel`. `EXTRA_BOOTARGS=initcall_debug` to trace
init hangs. A hung kernel warm-resets in ~20 s (m1n1 arms WD1 before handoff).

**Initramfs:** `bash ~/Code/wallace/scripts/t6040-make-initramfs.sh` (defaults:
INIT_SOURCE=`scripts/t6040-init-dcuart`, DEST=`initramfs-dcuart.cpio.gz`).
The init holds an fd open on ttydc0 for the life of init (the tty driver does
not enjoy full close/reopen cycles), prints a `[dcuart] spawning shell` marker,
respawns `busybox sh -i <>/dev/ttydc0` via setsid, pets `/dev/watchdog0`, and
keeps the fbcon shell as before.

### Kernel build

Native mac builds are impossible (case-insensitive FS corrupts the tree);
everything builds arm64-natively in the podman container `kbuild`
(see memory `t6040-kernel-build-env`). Kernel tree: `~/Code/linux`, branch
`feature/m4-m5-minimal-device-trees` (yuka's remote; mainline 7.2-rc2 + DT
commits). Working build dir inside the container: `/build/linux-keyboard`.

```
cp ~/Code/wallace/scripts/t6040-kbuild.sh ~/Code/wallace/patches/*.patch ~/Code/linux-build-out/
podman exec -e DOCKCHANNEL=1 -e BUILD_DIR=/build/linux-keyboard kbuild \
    bash /out/t6040-kbuild.sh image
```

kbuild.sh clones committed state, copies in the t6040 DT files from `/src`,
applies `/out/flokli-code.patch` (aic locked-sysreg skip + arm64 `idle=` param),
imports the DockChannel series (`origin/dockchannel`: mailbox `d2acb86f70a2`,
tty `b8dcbdcb`, HID transport) with `DOCKCHANNEL=1`, applies
`t6040-dockchannel-fixes.patch` (hid .stop) and `t6040-dockchannel-poll.patch`
(apple,poll-mode), forces the fbcon config, and builds Image + DTBs to `/out`.

- **BUILD GOTCHA:** the build uses COMMITTED kernel code + copies only DT
  files. Uncommitted host code edits are silently dropped — put code changes
  in a patch applied by kbuild.sh.
- `PMGR_FUNCTIONAL=1` additionally applies `t6040-pmgr-functional.patch` for
  the full-pmgr experiments.
- Fast DTB-only rebuild: `podman exec kbuild bash -c 'cd /build/linux-keyboard
  && make ARCH=arm64 apple/<name>.dtb && cp arch/arm64/boot/dts/apple/<name>.dtb /out/'`
  (explicit dtb targets build without a Makefile `dtb-y` entry).
- **zsh gotcha:** unquoted `$var` does not word-split.

DT sources: `t6040.dtsi` / `t6040-j614s*.dts` / `t6040-pmgr.dtsi` in
`~/Code/linux` (partly uncommitted); the dcuart board variant is preserved at
`~/Code/wallace/dts/t6040-j614s-dcuart.dts` (self-contained: defines the
dockchannel-uart nodes under &soc itself).

Known-good artifacts (in `~/Code/linux-build-out/`), kernel build #15:
- `Image` `14da8640398fc64b89d9241a75be0ffc8d4260b681068a3c27251cc79c3abaf4`
- `t6040-j614s-dcuart.dtb` `a99ad7c3f304198280814de1e4a31d83c268751af608afad7003aa982a69f65a`
- `initramfs-dcuart.cpio.gz` `512c69da94884f3ea83f9a6a4ea0731dcad6b5aaa87eb875ca5a6d7b24c317ca`

m1n1: `export PATH="$(brew --prefix llvm)/bin:$PATH"; make -j8` →
`build/m1n1.bin`. All t6040 changes are committed on `main`; the curated
code-only series lives on branch `t6040-bringup` (worktree `~/Code/m1n1-clean`).

## Solved blockers

### The 5 original M4 raw-boot blockers (common root: SPTM/firmware-locked resources trap)
1. **m1n1 async L2C SError at kboot handoff** — the dapf init; on t6040 ALL
   dapf entries trap. Fixed in `src/dapf.c` (`dapf_skip_entry()`), refined to
   still allow dart-mtp programming (keyboard needs it).
2. **AIC locked-sysreg trap** — `aic_init_cpu` writes
   `SYS_IMP_APL_VM_TMR_FIQ_ENA_EL2` + `SYS_ICH_HCR_EL2` in hyp mode → traps →
   hang before console. flokli patch comments out both (in `flokli-code.patch`).
3. **WFI state-loss** — M4 loses CPU state on WFI/WFE; flokli patch adds arm64
   `idle=[wfi|nop]`; boot with `idle=nop` (plain mainline ignores `idle=`).
4. **No fbcon in defconfig** — DRM_SIMPLEDRM + DRM_FBDEV_EMULATION +
   FRAMEBUFFER_CONSOLE + ARM64_SME=off, forced by kbuild.sh.
5. **Fuller-DT hang = pmgr** — see PMGR section below; isolated and worked
   around with a proven minimal policy.

### Internal keyboard (2026-07-11, session 4) — three independent bugs
(a) m1n1 skipped dart-mtp DAPF programming on t6040 (src/dapf.c);
(b) t6040.dtsi ASC mailbox IRQs were pairwise swapped — Apple's ADT lists
not-empty first per pair, the binding wants ascending;
(c) dockchannel-hid lacked hid_ll_driver `.stop` → NULL-deref oops
(`patches/t6040-dockchannel-fixes.patch`). Full story:
`done/2026-07-11-t6040-mtp-wake-findings.md`.

### Trackpad firmware path (2026-07-12, session 5)

The upstream-oriented DockChannel transport is deliberately keyboard-only: it
omitted the older Asahi driver's external firmware upload, while M2-and-newer
multi-touch requires a board-paired blob produced by `asahi-fwextract`.
`patches/t6040-dockchannel-trackpad-fw.patch` restores the bounded HIDF loader,
runtime interface-number patch, coherent-DMA upload, post-upload reset, and
retry-safe error cleanup. J614s DT names `apple/tpmtfw-j614s.bin` (Linux commit
`6399cdc1bb94`).

Kernel build #12 (`Image` SHA-256 `93c33ea10dddcc69b50c39a7c0b64a7a8d9c5485bfcc94119839ed4501fdadfb`)
booted to BusyBox. Two event0 opens independently returned `-ENOENT` for the
missing blob; neither sent command `0x40`, timed out, nor left `starting` stuck.
Use `TRACKPAD_FIRMWARE=... scripts/t6040-make-initramfs.sh` after extracting the
paired file. GPIO proxying remains intentionally absent until any request and
its J614s ADT mapping are captured and reviewed. A later ADT-only capture found
`function-afe-reset = pKW4('gp1c', 0x10000)` through phandle 294,
`/arm-io/smc/iop-smc-nub/smc-pmu`. The legacy pulse would write SMC key `gp1c`
as `0x10001` then `0x10000`; do not implement or exercise it under the absolute
no-PMU-write rule. Details:
`done/2026-07-12-t6040-trackpad-firmware.md`.

### DockChannel-UART Linux console (2026-07-12)
Kernel side: `origin/dockchannel` mailbox + tty drivers + a t6040 board DT
variant. **The t6040-specific discovery: the ADT-declared AIC irq 360 for the
dockchannel-uart AP FIFO NEVER fires.** Probed live from m1n1: the FIFO irq
block (+0xc000) latches flags and takes mask writes fine, but with all 4096
AIC inputs unmasked, no HW_STATE bit tracks the FIFO mask toggle. Without an
IRQ the stock driver TX-stalls at exactly one 2 KiB FIFO fill (send_data
completes only from the IRQ handler) and RX is dead — the "banner then
silence" signature. Fix: `patches/t6040-dockchannel-poll.patch` adds an
`apple,poll-mode` DT property (5 ms delayed-work poll; TX-done on FIFO-drain,
RX via RX_COUNT). m1n1 and the KIS dock-side agent poll this FIFO too.

Open question (not blocking): where does that irq line actually go —
fused off on the chopped die, routed to AOP, or KIS-agent-only? XNU's
pe_serial dockchannel path may answer (ADT has `enable-sw-drain=1`).

MMIO caution: the dockchannel-uart block maps ONLY +0xc000 (irq, 24 B) and
+0x28000..+0x38004 (config/data). Reading other offsets (e.g. +0x20000) raises
an async SError that kills m1n1 — unlike dockchannel-mtp, which maps
+0x0/+0x14000/+0x28000../+0x30000..

Note: the tty driver registers no printk console — `console=ttydc0` does
nothing yet; the shell + dmesg cover post-userspace, fbcon covers early boot.

### ANS/NVMe map (2026-07-13, session 5)

Read-only live ADT inspection established the T6040 storage layout: ASC control
`0x209600000`, mailbox `0x209608000` (IRQs 1530–1533 after normalizing Apple's
pair order), SART v3 `0x20dc50000`, and NVMe/NVMMU `0x20dcc0000` (IRQ 2583).
Storage uses SART plus the embedded NVMMU, not DART. Disabled nodes are committed
in Linux `9cf4a92fa16f`; the standard DT therefore performs no new accesses.

`scripts/t6040-build-nvme-candidate.sh` builds a separate, conspicuously named
first-probe DTB. Do not boot it without maintainer approval: enabling it invokes
normal but not-yet-exercised T6040 PMGR, SART, ASC, and NVMe writes. Exact map,
candidate hash, and write classes: `done/2026-07-13-t6040-nvme-map.md`.

### Watchdog (2026-07-11)
Linux `apple_wdt` takes over m1n1's WD1; BusyBox pings `/dev/watchdog0` every
10 s. m1n1 arms WD1 for ~20 s on M4 before handoff (`src/kboot.c`,
`src/wdt.c: wdt_arm_secs`) so hung kernels warm-reset back to "Running proxy".

## PMGR investigation (sessions 2–4, 2026-07-11/12)

**Deterministic result (2026-07-12): the full 214-domain topology boots 3/3**
with this exact minimal temporary raw-boot policy:
- preserve every domain found active at probe (`apple,preserve-active` on all
  four controllers);
- disable only `disp_cpu`;
- skip auto-enable only on `dispext0_cpu` and `dispext1_cpu`.

The legacy raw tree fails 3/3. The five ANE exclusions in the previous broad
functional policy are unnecessary, as are both banks' `sys` and `fe` skips.
Removing either CPU bank's exception fails; the two CPU skips alone boot 3/3.
PMGR1 reparent-only fails while removal-only boots, proving that
the old curated regression came from flattening, not class removal. Removing
only AMCC/DCS/fabric/`soc_dpe` does not boot. Exact DTB hashes, negative controls,
and caveats about invalid whole-controller deletion tests are in
`done/2026-07-12-t6040-pmgr-matrix.md`.

The policy is now in the kernel DT source at Linux commit `4da589ce34d6`. The
rebuilt standard `t6040-j614s-dcuart.dtb`
(`34d6e8f574dec2d1b0669e3f03fb1df7b5e3cee278ac23a4cc304e903187d9c0`)
reached the Linux banner and BusyBox, so the standard build no longer depends
on an experiment-only variant DTB.

**Upstream-shaped selection (2026-07-13):**
`patches/t6040-pmgr-t6041-quirks.patch` keys preserve-active behavior and the
two `dispext*_cpu` auto-enable exclusions from the already-present T6041
compatible, and documents the compatible in both PMGR bindings. Linux commit
`37339d595765` removes all six experiment-only booleans from the standard DT;
`disp_cpu` remains disabled. Kernel build #14 reached BusyBox with zero
`apple,preserve-active`/`apple,skip-auto-enable` properties in its DTB.
Artifacts: `Image` SHA-256
`925303d09ae6190e8b0bc59824af6d621daefcbedc162f9787d495d3ed7c965a`,
DTB `a99ad7c3f304198280814de1e4a31d83c268751af608afad7003aa982a69f65a`.

`pmgr_adt2dt.py` was fixed in m1n1 `5dc76503` (curated branch `effcc16c`):
Apple `critical` no longer silently becomes Linux always-on policy, and parents
with `no_ps` no longer produce dangling phandles.

### Earlier blind investigation (historical context)

The full generated four-controller/214-domain `t6040-pmgr.dtsi` hangs the
kernel pre-console (inside apple-pmgr-pwrstate probe, before simpledrm).
Session 3 got the full DT to userspace with a **functional policy**
(`patches/t6040-pmgr-functional.patch`, build with `PMGR_FUNCTIONAL=1`):
- `apple,preserve-active` per controller (domains found active at probe are
  marked always-on);
- `apple,skip-auto-enable` on the locked dispext0/1 sys/fe/cpu domains;
- five ANE domains disabled (delayed async SError on raw boot);
- `disp_cpu@10000` disabled (first register access traps).

**Session-2 findings, with honest confidence** (all HW results are N=1 blind
pre-console hangs; determinism was never established by re-running a DTB):

| variant | pmgr config | result (N=1) |
|---|---|---|
| `pmgr01` | autogen pmgr0+1 (hierarchical), pmgr2+3 OFF | BOOTS userspace |
| `bis-nocpu` | autogen 0+1+2, pmgr3 OFF, only CPU domains disabled | logo-only |
| `safe2` | autogen, pmgr2 core-infra disabled (orphans children) | −517 defer storm, no userspace |
| `cur-pmgr01` | curated/reparented pmgr0+1, pmgr2+3 OFF | logo-only |
| `curated`/`bis-*` | curated, various pmgr2 subsets off | logo-only |

SOLID (~90–95%): the per-domain pmgr2 bisection was logically invalid (the
intersection of all hung tests' enabled sets came out empty — no single
culprit domain exists, assuming determinism); `pmgr_adt2dt.py` derives
`apple,always-on` from the ADT `critical` flag, which disagrees with yuka's
curated t8132 (over-marks pmc/pms_c1ppt/pms_fpwm0-4, misses aic) — a real
generator bug. PLAUSIBLE-not-isolated (~50–80%): pmgr-present→hang;
"killer is pmgr2 core-infra"; "reparent-to-root is fatal" (confounded);
"safe2's stall was the defer storm". The real obstacle was BLINDNESS —
which the DockChannel console now removes for everything post-userspace
(a pre-console printk poller into the FIFO would close the rest).

Curated-pmgr tooling from session 2 (prune_pmgr.py, bisect_build.sh, variant
dtsi/dts) lived in that session's scratchpad; the method is documented in
`done/`-era NEXT_STEPS history in git if needed.

## Dead ends (do not re-investigate)

- **SBU analog serial on M4/ACE3:** ACE3 advertises action 0x306 but rejects
  every enter attempt (host VDM → BUSY 0x40030004; target-side DVEn via SPMI →
  result 0x3 for pin sets 2/7; pin set 0 accepted but no HW drain to SBU; pin
  set 1 maps UART onto D+/D− and kills the USB proxy). The dockchannel FIFO's
  real consumer is the KIS debug agent → DebugUSB is the supported path.
  Details in `done/2026-07-11-t6040-console-session.md` and memory.
- **No s5l serial console on M4 raw-boot;** the `...YG3` device is m1n1's
  vuart (hv-only → dead after handoff); m1n1 hv is SPTM-blocked entirely.
- **RAM-dump post-mortem:** iBoot scrubs DRAM on watchdog reset (verified:
  bytes read back all-zero). The ramdump script was deleted with the refactor.
- **USB gadget console (PARKED, not dead):** gadget enumerates but EP0 dies
  post-enumeration (raw + glue variants). Revisit for gadget-Ethernet+SSH
  after pmgr. `done/2026-07-11-t6040-usb-gadget-plan.md`. Gotchas recorded in
  memory: the ChatGPT desktop app squats USB devices; one enumeration per boot.
