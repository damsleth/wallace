# T6040 (M4 Pro, Mac16,8 / J614s) — roadmap: first light → full Linux desktop

End-goal: a bootable Linux distro on this MacBook Pro 14" M4 Pro with GPU accel,
WiFi, Bluetooth, keyboard/trackpad, audio, webcam, power management — daily-driver
comfort comparable to macOS.

Written 2026-07-10, last updated **2026-07-23** (Alpine RAM-root and bounded
HID state-trace candidate).
Companion docs: `NEXT_STEPS.md` (immediate work), `DEVLOG.md`
(operational reference + solved blockers), `t6040-dt-checklist.md` (Stage C
reference), and `BOOTABLE_BUILD_EXPERIMENTS.md` (B0 cold-boot ladder).
All finished per-topic plans/write-ups are archived in `done/`.
Unposted #asahi-dev drafts awaiting review: `done/2026-07-10-t6040-smp-writeup.md`,
`done/2026-07-10-t6040-cpufreq-writeup.md`,
`done/2026-07-14-t6040-sptm-asahi-question.md` (M4 NVMe SPTM boundary question).

## Where we are

**Linux reaches userspace on bare metal (2026-07-11).** Mainline 7.2-rc2 plus
the local bring-up patch series boots to a BusyBox shell on the full 214-domain
PMGR DT (maxcpus=1, idle=nop), reproducibly. The internal keyboard works there
(dockchannel-HID,
2026-07-11); the Linux watchdog takes over m1n1's (shell persists); the
framebuffer (simpledrm+fbcon) is the early console.

**Fully remote dev loop (2026-07-12).** Two-way m1n1 proxy AND a two-way Linux
shell (`/dev/ttydc0`, poll-mode dockchannel driver; the ADT's UART IRQ 360 is
wrong and bounded M4 Pro measurement found the real input at 816) over a single
DebugUSB/KIS cable in the DFU port, plus
remote reboot via `macvdmtool`: reboot → chainload → boot → interactive shell
with zero physical access. SBU analog serial was proven a dead end on ACE3.

**Alpine RAM-root boots (2026-07-23).** Alpine 3.24.0/aarch64 now reaches a
responsive, storage-free shell loaded entirely through m1n1; RAM writes pass
and no block device or storage controller probes. The tested 7.1.3 USB-host
kernel regresses internal HID registration even though MTP reports `Keyboard
ready`. A storage-disabled test of the suspected unmasked
acknowledge/threaded-drain race booted successfully but still registered no
input device, so that change is not a sufficient fix. The next gate is bounded
observation-only tracing across the DockChannel IRQ/FIFO and DCHID
event/identity boundary. Ticket 072 built and statically verified that trace.
Ticket 074 booted it once, but ttydc0 RX was non-responsive despite working TX,
so no trace command ran. Offline ticket 075 built a host-tested replacement
that automatically reports over TX without depending on shell input;
independent exact-artifact review passed, and proposed one-shot capture 076
awaits explicit maintainer approval.

**Bootable-build path defined (2026-07-23).** The immediate B0 milestone is an
enrolled raw m1n1 object carrying a self-contained Alpine RAM distro, reaching
simpledrm/fbcon and internal keyboard without a host payload upload. It does
not wait for USB or internal NVMe. Tickets 077–079 restore HID and produce the
release-like distro. Ticket 080 completed the raw payload audit and selected
direct m1n1: exact prefix + command line + compressed kernel + raw DTB +
compressed initramfs, entry `0x800`, with a strict host verifier. Ticket 081 builds a
single-object tethered proof; 082 prepares reversible enrollment/cold boot.
Full sequence: `docs/BOOTABLE_BUILD_EXPERIMENTS.md`. Layout result:
`done/2026-07-23-t6040-raw-boot-object-layout.md`.

**Stage A complete 2026-07-10** — proxy solid, 14/14 cores (4E+5P+5P), MPIDR
map, execute-and-return, broken_wfi handled (WFE park), ~10 s chainload loop.

**Stage B effectively complete 2026-07-10** — cpufreq minimal (APSC/pstate;
throttle offsets deferred, need RE), MCC t6041 Ph1+2 (cache-enable proven;
unknown TZ offsets reduced to non-blocking m1n1 EL2 hardening by ticket 020),
PCIe register map plus clock/PLL targets resolved (the traced
`[70]` SError was a top-of-RAM log-buffer artifact; with the guard, Apple's
complete 105-operation clock/tunable prefix runs and boots Linux cleanly),
ATC/USB DART audited
(DART done, PHY tunables deferred → USB2 fallback), kboot FDT display carveout
fixed, dapf gate + watchdog arm added for M4.

### Current working / not-working snapshot

| Works | Not yet |
|---|---|
| BusyBox userspace; full PMGR with property-free T6041 quirk, reproducible | PMGR draft review/submission (split, checkpatch/schema-clean; NEXT_STEPS #2) |
| Internal keyboard at the shell; trackpad registers + validated firmware-loader path | Target ESP's paired trackpad blob; PMU-backed reset remains forbidden; maxcpus>1/idle states |
| Two-way Linux shell + m1n1 proxy over one DebugUSB cable; remote reboot | Printk over ttydc needs a separate polled/atomic TX path; current TTY queue is not console-safe |
| Linux apple_wdt; fbcon early console | NVMe rootfs (power/SART/ANS work; queue and per-command TCB setup require unavailable raw-boot SPTM entry) |
| Kernel build env (podman, arm64-native) with patch pipeline | USB gadget console (parked: EP0 dies post-enumeration) |
| SMP/cpufreq/MCC groundwork; PCIe host+wireless DT and drivers build | board-audited Linux secondary-core test, cpufreq throttles, gated PCIe link-up test, wireless firmware, USB3/TB PHY tunables |

**Upstreaming pending**: the SMP/broken_wfi/MPIDR + cpufreq channel drafts are
finalized in `done/` (ticket 019); actual m1n1 patch-mail rebase/series shaping
is ticket 046. Also pending: dockchannel-uart per-instance IRQ masks + poll-mode patch to the
dockchannel-branch authors (retire ADT IRQ 360; measured UART input is 816);
curated code-only branch `t6040-bringup` tracks main's src/ (main merged AsahiLinux
upstream 2026-07-14 at `16b1f61f`; curated branch rebased onto it the same
day, tip `f0738eee`; series audit/shaping is ticket 046).

One structural constraint colors everything below: **M4 = raw boot only** (SPTM
owns the mach-o path). Apple-private sysregs are locked. Linux itself doesn't
care (it runs at EL2/EL1 normally), but: no hypervisor tracing of macOS drivers
on this machine — the classic Asahi reverse-engineering tool (`hv` + tracers) is
crippled on M4. Reverse engineering of new hardware blocks largely has to happen
on M1/M2/M3 machines upstream, or via static ADT/firmware analysis. This is the
single biggest reason most of Stages E–G are "track upstream" rather than "build
it here". *Watch this space: upstream m1n1 (merged 2026-07-14) now gates hv's
SPRR/GXF/AMX use on `apple_sysregs_unlocked` and knows the T6040 CPUSTART —
yuka appears to be making hv tolerate locked-sysreg machines. A degraded hv on
the T6040 is untested here, but if it becomes viable it would reopen (some)
tracing on this rig.*

*Locked-AIC status (from #asahi-dev 2026-07-21, yuka;
`done/2026-07-21-asahi-dev-irc-review.md`): iBoot builds that leave the relevant
AIC reg **unlocked** exist for t8132/t8140/t6050 but **not** for
t6040/t6041/t8142 — so our machine keeps the `aic_init_cpu` locked-sysreg skip
(flokli patch). An Apple radar already unlocked one machine; a follow-up radar
to cover t6040/t6041/t8142 in a future iBoot is under discussion upstream, which
would be the clean long-term fix. SPTM/GXF itself remains the wall (no signed
guarded entry for a raw-boot object) — the SEP-loads-keys-into-the-NVMe-
controller remark (chaos_princess, 2026-07-20) is a lead for the internal-NVMe
route, tracked under the SPTM tickets.*

## Stage map

```
A. Proxy solid ──► B. m1n1 Linux-boot ──► C. Kernel DT + boot ──► D. Storage/USB/HID/console
                                                                        │
        ┌───────────────────────────────────────────────────────────────┤
        ▼                          ▼                        ▼           ▼
E. WiFi + Bluetooth        F. GPU (long pole)        G. Audio/ISP/PM   H. Distro integration
```

A→D are sequential. E/F/G parallelize after D. H wraps it all.

---

## Stage A — proxy solid, all cores ✅ COMPLETE (2026-07-10)

*Was `done/t6040-bringup-plan.md` phases 2–4. Took days, as scoped.*

- [x] Second machine + `shell.py` → proxy prompt (M1 host over USB; no PR #616 needed)
- [x] `smp.start_secondaries()` — `CPU_START_OFF_T6031` 0x88000 (src/smp.c:296)
      **validated correct**; all 14 cores up. Plus execute-and-return + MPIDR map.
- [x] `chainload.py -r build/m1n1.bin` reliable → ~10-second dev loop, kmutil retired
      **(done 2026-07-10, build chain fixed)**
- [x] Upstream posting draft: confirmed constants, MPIDRs, and the
      features_m4/broken_wfi raw-boot note, finalized by ticket 019 in
      `2026-07-10-t6040-smp-writeup.md`. Upstream m1n1 already carries T6040
      CPUSTART `0x88000` in proxyclient/hv via yuka `0ec216de`; the draft
      correctly frames WFE parking as the locked-sysreg fallback after Sven's
      `c22ca847` retention-bit diagnosis. Actual patch mail is ticket 046.

**Exit:** ✅ proxy stable across reboots, 14/14 cores. (chainload dev loop + upstream
carry forward as small residuals; neither blocks Stage B.)

## Stage B — m1n1 grows Linux-boot support for T6040

*What `kboot` needs before it can hand a kernel a usable machine. This is the
M3 template (commits 83364d0→5393f41) replayed on T6040. Weeks. All of it is
doable solo with the proxy + ADT dumps; this is the highest-leverage local work.*

1. ✅ **cpufreq** (`src/cpufreq.c`) — **DONE (minimal) 2026-07-10; throttle
   residual bounded 2026-07-23.** T6040 reuses `t6031_clusters`; pstate/APSC
   works. T6030 throttle offsets SError on T6040 P-clusters. Paired
   `AppleT6041PMGR` analysis recovered no safe replacement and shows a
   target-specific generic-throttler override plus RegMap-mediated paths.
   Keep throttles omitted; they are not required for Linux DVFS. See
   `2026-07-10-t6040-cpufreq-plan.md` and
   `2026-07-23-t6040-cpufreq-throttle-analysis.md`.
2. ✅ **MCC** (`src/mcc.c`) — **Phases 1+2 DONE (2026-07-10); residual
   bounded 2026-07-23.** `mcc_init_t6041()`
   added: t6031 reuse mis-parsed the ADT (AMCCs at `reg[12..15]` per `amcc-reg-idx`/
   `amcc-count`, no `plane-count-per-amcc`). Phase 2 hardware-RE'd the SLC: 1 plane
   per AMCC, status = 0x00010101 (T6031 decode wrong) — both encoded as `T6041_*`
   constants. The idempotent cache-enable write is proven by repeated Linux
   boots. T603x TZ offsets still read zero, but region-id-4 begins at the
   exclusive normal-RAM limit and region-id-2 is higher, so Linux never sees
   either range. Remaining work is non-blocking m1n1 EL2 hardening via an
   ADT-backed unmap or static iBoot decode; no live sweep. See
   `2026-07-23-t6040-mcc-carveout-analysis.md`.
3. **PCIe** (`src/pcie.c` + tunables) — **HOST-SIDE COMPLETE; LIVE GATED
   (2026-07-14).** Added
   `regs_t6040` + `apcie,t6040` dispatch branch. ADT-verified against live
   `/arm-io/apcie0`: 35 regs, #ports=4, shared block = reg[0..6] then 4×7 port
   regs ⇒ `shared_reg_count=7` (the one delta vs t6031; 8 would fail the
   even-divide check). Static analysis of `AppleT6040PCIe::start()` proves the
   two new clock groups target reg[5] (CIO3 PLL) and reg[6] (PCIe clkgen); m1n1
   now applies both and reuses the T6031/T8122 init path. The matching
   PCIe/DART/BCM4388/GL9755 Linux DT and driver image build cleanly. The first
   live attempt reached `No common tunables`; the traced retry delivered an
   asynchronous SError after AXI `[70]` and before `[71]`. Static disassembly
   then proved Apple keeps clock gate 7 (`APCIE_PHY_SW`) off through AXI/CIO3/
   clkgen programming, whereas m1n1 enabled it early. The approved corrected
   105-write run matched Apple's gate order but delivered the same SError after
   `[70]`, disproving the early-gate hypothesis. Barriers plus immediate L2C
   status reads also repeated `[70]` with a zero post-write sample. A zero-PCIe-
   write trace reproduced it, proving a log-buffer artifact: the 16 KiB ring
   ends at top-of-RAM and crosses its boundary during `[61] done`. An upper-guard
   dry-run control completed all 77 entries and booted Linux, proving the guard.
   The approved guarded stop-before-PHY run then completed all 105 operations,
   including CIO3, clkgen, and the late PHY clock gate, and booted Linux without
   an L2 error or SError. The next bounded stage is PHY setup only, with a return
   before the first per-port write. Detailed in
   `2026-07-14-t6040-wireless-pcie-map.md`. WiFi/BT prerequisite.
4. **ATC/USB tunables + DART config** — **AUDITED 2026-07-10 (mostly verify+defer).**
   All kboot-only, FDT-only (safe). **DART = done** (t6040 DARTs are `dart,t8110`,
   fully supported). **ACIO USB4 rc+pcie_adapter = works as-is** (prop names match).
   **ATC PHY tunables = blocked** on the t6040 PHY reg-bucket offsets (FDT bucket
   names are stable; only per-bucket reg_offset/size is the unknown — mustn't
   invent). Graceful USB2-only fallback means this does NOT block Stage C; USB3/TB
   is a Stage D comfort. NHI/apciec (Thunderbolt) name-mapping also deferred.
   The old `upstream/atcphy-new-tunables` pointer is stale at a January 2025
   tip, not an active T6040 branch. Watch broader m1n1/Linux/#asahi-dev work for
   an explicit T6040 44-bank map and SN201202x HPM path. Detailed in
   `done/2026-07-10-t6040-atc-usb-dart-plan.md` and
   `done/2026-07-23-t6040-atcphy-upstream-checkpoint.md`.
5. **kboot FDT init** (`src/kboot.c` and friends) — **AUDITED + display FIXED
   2026-07-10.** kboot-only, FDT-only (safe), Stage-C-coupled (patches a kernel DT
   that doesn't exist yet). Generic parts already work for t6040: spin-table/
   CPU-release (`dt_set_cpus`, SMP done), DART (t8110), ACIO. **Fixed:**
   `dt_set_display` now has a t6040 branch — was hitting "unknown compatible, skip",
   now reuses the t602x carveout scheme (region-id 49/50/57/94/95/157 verified on
   the live carveout map) + dcpext firmware. **Deferred:** compat fixup (speculative
   until a real t6040 DT exists), GPU carveout (Stage F), dcpext data-region
   validation, ISP/SEP/SMC (verify at Stage C). Detailed in
   `2026-07-10-t6040-kboot-fdt-plan.md`.
6. **Python side** (`proxyclient/m1n1/`) — T6040 chip knowledge for the tools
   used to dump/verify all of the above.

**Exit:** m1n1 boots a kernel image with a correct, complete FDT; kernel gets to
early console. (Testable incrementally against Stage C.)

## Stage C — kernel devicetree + core boot (Asahi kernel tree)

*Target: linux-asahi boots to a shell on this machine. Weeks, parallel with B.*

- **Device trees:** **FULL 214-DOMAIN PMGR TO USERSPACE (2026-07-12, temporary
  policy).** `t6040.dtsi`
  + `t6040-j614s*.dts` + generated `t6040-pmgr.dtsi` in `~/code/linux`
  (templated from t8132/t6050, ADT-verified). The 2026-07-10 async-L2C-SError
  handoff blocker was the m1n1 dapf init (all t6040 dapf entries trap; gated in
  `src/dapf.c`). Board variants: `-kbd` (keyboard, known-good) and `-dcuart`
  (keyboard + DockChannel shell, preserved at `~/Code/wallace/dts/`). **Remaining:
  full-pmgr legacy policy hangs pre-console, but the exact deterministic minimum
  (preserve active, disable `disp_cpu`, skip auto-enable only for
  `dispext0_cpu` and `dispext1_cpu`) boots 3/3. Both CPU skips are necessary;
  the former `sys`, `fe`, and ANE restrictions are not.
  The live-tested T6041-compatible quirk now carries that policy without custom
  DT booleans; review/upstream submission is the remaining Stage C PMGR work**;
  see NEXT_STEPS #2 and DEVLOG's PMGR section.
- **AIC3:** **works** — the AsahiLinux `asahi-wip` base has
  `apple,t8122-aic3` support; boots and
  delivers interrupts (keyboard mailbox IRQs verified live). Two locked-sysreg
  writes in `aic_init_cpu` must be skipped on M4 raw-boot (flokli patch).
- **Core platform drivers** (mostly compat-string + minor deltas on existing
  Asahi drivers): UART, watchdog, PMGR power domains, pinctrl/GPIO, I2C/SPI,
  mailbox/RTKit (new firmware version strings for 26.x!), DART t8110, cpufreq
  (`apple,cluster-cpufreq`), SMC, SPMI/PMU.
- **RTKit firmware versioning:** every coprocessor (NVMe/ANS, SMC, DCP, ISP…)
  ships firmware from the macOS 26.x install; Asahi drivers whitelist known
  ABI versions. Expect a steady trickle of "add fw 26.x compat" patches.

**Exit:** linux-asahi + our DT boots to initramfs shell over USB gadget/serial,
all 14 cores online, cpufreq working.
**Status 2026-07-21:** initramfs shell and full PMGR are proven locally at
maxcpus=1. A WIP `more-t6041` branch independently reached an M4 Pro shell with
all cores and PMGR, but its inherited CPU/domain topology is not J614s-correct;
ticket 034 still gates a 14-core-board-specific secondary test. T6040/T6041 AIC
sysregs remain firmware-locked, so the trap-avoidance patch and `idle=nop`
remain required.

## Stage D — storage, USB, HID, display console (usable machine)

*The "it's a real computer now" stage. Weeks.*

- **NVMe** (apple-nvme + SART + ANS RTKit): internal SSD. PCIe parents can be
  forced actual-on; CoastGuard/SART activation, RTKit buffers, ANS boot, and
  boot status all succeed. T8140 then rejects direct legacy and standard NVMe
  queue-register programming. macOS uses guarded SPTM service 6 for queue and
  per-command TCB authorization. Its ABI is decoded, but raw boot has
  SPRR/GXF disabled and the exact GENTER call hangs. iBoot's queue buffers are
  ordinary, unreserved RAM and the macOS path performs per-command TCB
  authorization, so preserving only the firmware ASQ/ACQ is not a complete
  Linux design. Do not repeat direct register or GENTER attempts unchanged
  (NEXT_STEPS #3).
- **USB** (dwc3 + ATC PHY): the J614s physical map is captured and independently
  reviewed (`usb-drd0` left-back/KIS, `usb-drd1` left-front, `usb-drd2` right).
  The right-only no-root smoke initialized its DARTs and xHCI root hubs cleanly,
  but no attached device enumerated. The saved ADT maps that port through a
  right-side SPMI HPM, `atc-phy,t6040`, and `acio2`, while Linux describes none
  of that connector/PHY path; force-host therefore starts xHCI with no generic
  PHY provider. The failed device was a directly attached bus-powered USB-C
  stick, but ticket 065's powered fixture is unavailable. Ticket 067 therefore
  supplies the interim distro milestone: Alpine booted entirely from a
  m1n1-uploaded RAM-root with all storage paths disabled. Persistent external
  root remains gated on a powered-device discriminator, then reviewed T6040
  HPM/ATC work if it fails.
  M3 ATC PHY work
  enumerated a real device on 2026-07-20, but its SPMI wake and PHY data are not
  T6040 parameters; USB3/TB stays track-and-test. The 2026-07-23 upstream
  refresh found no published T6040 compatible, SN201202x path, or mapping for
  the target's 44 PHY register entries.
- **Internal keyboard + trackpad:** ✅ **keyboard DONE early (2026-07-11)** via
  dockchannel-HID (three bugs fixed — see DEVLOG); trackpad registers as
  input0. Its missing HIDF loader and retry recovery are fixed. Ticket 016
  reproducibly staged the paired 25F84 `tpmtfw-j614s.bin` (`a1f4131d...`);
  rebuild/review ticket 004, then determine whether J614s needs the forbidden
  legacy PMU-backed GPIO proxy path without exercising that write
  (NEXT_STEPS #1).
- **Display:** two steps.
  1. `simpledrm` on the m1n1-provided framebuffer — works immediately, no
     driver; gives a desktop-capable (unaccelerated) console. This alone plus
     NVMe/USB/HID = installable, usable-in-anger machine.
  2. **DCP driver** for real display control (brightness, DPMS, mode switch,
     external DP alt-mode). Firmware-version-locked; M4 + macOS 26.x firmware
     support must exist in the asahi DCP driver. The July 2026 `dcp/14.8.3`
     work now boots and has HPD/brightness progress, but is ABI groundwork rather
     than 26.x/T6040 support. The 2026-07-23 J614s ADT inventory prepares the
     internal/external DT topology but also proves the local blockers: a fifth
     display MMIO window, eight-input ASC wrapper, SID/register-bank deltas, and
     the intentionally isolated raw-boot display power domain. Do not enable a
     borrowed 14.x node; see
     `done/2026-07-23-t6040-dcp-upstream-dt-prep.md`.
- **SMC:** power button, lid, battery/charger via macsmc — mostly compat work.
  Track the July 2026 v2 hwmon/RTC DT-subdevice series; it has not established
  T6040 compatibility and does not relax the no-unreviewed-PMU/SPMI-write rule.

**Exit:** boot an external USB root to a desktop on simpledrm, with working
built-in keyboard/trackpad and battery status. Internal NVMe is a later secure-
firmware integration goal, not the Stage-D gate. Daily-drivable without
GPU/WiFi (USB ethernet).

## Stage E — WiFi + Bluetooth

*Moderate; mostly enablement, not R&E — the drivers exist. Depends on Stage B PCIe.*

- **Mapped and host-built 2026-07-14:** port 0 is BCM4388 WiFi (`14e4:4434`)
  plus Bluetooth (`14e4:5f72`), board module `mriya`; port 1 is the GL9755 SD
  reader. Linux already carries both Broadcom IDs and explicit BCM4388 support.
  The complete PCIe/GPIO/DART child topology is in the separately gated
  `t6040-j614s-dcuart-pcie` DT; see
  `done/2026-07-14-t6040-wireless-pcie-map.md`.
- **Shared-PHY boundary:** the approved continuation after the successful
  Apple-ordered 105-operation prefix ran at main `85b01036`, binary
  SHA-256
  `add3cef43947dab1605bd95ad602b6dcbf8e89de0a3f1b43f278005cd52dd9da`,
  used the PCIe-free base DT and returned before ports. Operations 1–114
  completed; the target stopped during operation 115, the first PHY-IP PLL RMW
  at `0x417040090`. Linux did not hand off and no port or storage access ran.
  Exact result in `done/2026-07-14-t6040-pcie-phy-diagnostic.md`. Until link-up
  succeeds, firmware work cannot be exercised.
- **WiFi:** `brcmfmac` PCIe path; m1n1 already copies the MAC, antenna SKU and
  calibration blob from ADT when `wifi0` is aliased. Firmware still has to be
  extracted from the paired macOS install for board type `apple,mriya`.
- **Bluetooth:** `hci_bcm4377`; m1n1 copies the address and calibration blobs.
  The paired BCM4388 firmware still has to be packaged in the initramfs/rootfs.
- If the chip generation is genuinely new (not just a new ID), this becomes
  upstream-collab work — but Broadcom generations have been incremental so far.

**Exit:** WiFi associates + BT pairs on mainline-asahi drivers with extracted fw.

## Stage F — GPU (the long pole)

*This is the item that decides when "all the comforts" arrives. Not a solo project.*

- M4 GPU is the G15/G16 family (M3 introduced Dynamic Caching — a large
  architectural break from the G13/G14 the shipping drm/asahi driver grew up on).
  Kernel driver (Rust, drm/asahi) + firmware ABI + Mesa compiler (agx) all need
  the M3/M4-generation work that the upstream Asahi team has been driving since
  the M3 bring-up; the 2026-06 progress report explicitly says M4 groundwork is
  being laid.
- Firmware ABI is version-locked per macOS release → our 26.x install needs
  explicit support.
- **Realistic role for this machine:** be the T6040 test mule — provide ADT/fw
  dumps, run bring-up branches, report. Writing a G16 GPU driver from scratch
  here is out of scope; the raw-boot hypervisor limitation (no XNU tracing on
  M4) means even upstream does the RE on other hardware.
- **Until it lands:** simpledrm desktop. KDE on simpledrm at 3024x1964 is
  serviceable; no video decode offload, no games, high CPU for compositing.

**Exit:** drm/asahi + Mesa honeykrisp/agx running the desktop with GL/Vulkan.

## Stage G — comforts: audio, camera, power

- **Speakers/headphones:** macaudio stack (tas2764 amps + cs42l84 jack codec are
  the recurring parts) — needs j614s DT wiring, `speakersafetyd` limits, and an
  **asahi-audio DSP profile measured for this exact chassis** (each model gets
  tuned EQ; 14" M4 Pro won't exist yet). Speaker safety is a hard gate: no
  profile → speakers stay muted. Headphones/USB audio work much earlier.
- **Webcam:** apple-isp driver + m1n1 ISP prealloc (Stage B item) + new sensor/
  firmware handling for the 12MP Center Stage camera. Upstream-tracking.
- **Power management:** s2idle suspend via SMC (works on M1/M2, needs T6040
  validation); `features_m4` sleep_mode currently SLEEP_NONE in m1n1 — deep-WFI/
  cpuidle needs careful enablement under locked sysregs. EFI-PSCI CPU power-down
  is making upstream progress, but does not yet replace the J614s raw-kboot
  release/WFE audit. Battery life tuning (devfreq, runtime PM on
  DARTs/coprocessors) trails everything else.
- **Explicitly never (or SEP-blocked):** Touch ID. **Late/limited:** Thunderbolt
  tunneling (USB3/DP alt-mode work; full TB is still open upstream), video
  decode engines (AVD is M1/M2-era work, M4 unexplored).

## Stage H — distro integration ("bootable Linux distro")

- **B0, personal cold boot:** use the dedicated APFS/m1n1 volume and raw
  enrollment to boot one self-contained m1n1 + kernel + J614s DTB + Alpine RAM
  distro. DebugUSB may observe but supplies no payload. This is intentionally
  storage-free and is the first “this machine boots Linux” milestone. Tickets
  076–082 and `docs/BOOTABLE_BUILD_EXPERIMENTS.md` define the evidence-gated
  sequence.
- **B1, standard boot flow:** after B0, make U-Boot/EFI work and move toward
  GRUB/systemd-boot or a unified kernel image. Ticket 025 owns this; ticket
  080 confirmed U-Boot is not required for B0.
- **B2, persistent distro:** use external USB root after the HPM/ATC physical
  link enumerates a device; internal NVMe stays a later SPTM integration goal.
- **asahi-installer:** its current second stage already invokes
  `kmutil --raw --entry-point 2048 --lowest-virtual-address 0`. It must add
  Mac16,8/T6040 admission, preserve a complete kernel+DTB+initramfs payload
  atomically across install/repair/upgrade, and support 26.x AEA plus moved
  firmware layouts. Requirements:
  `done/2026-07-23-t6040-asahi-installer-requirements.md`.
- **U-Boot:** T6040 support (usually near-free once m1n1's FDT + dwc3 are right)
  → standard EFI boot flow → GRUB/systemd-boot.
- **Fedora Asahi Remix:** kernel with all of the above, j614s asahi-audio
  profile, mesa builds, calamares/initial-setup — mostly automatic once the
  pieces exist upstream.
- The B0 path deliberately uses direct m1n1 payloads first. It must not be
  blocked on official installer integration, U-Boot, persistent storage, SMP,
  cpufreq, or post-boot comfort drivers.

## Dependencies & effort summary

| Stage | Blocked by | Who realistically does it | Effort |
|---|---|---|---|
| A proxy/SMP | — | you, now | days |
| B m1n1 kboot | A | you (best solo leverage) | weeks |
| C kernel DT/boot | B partial, AIC3 driver | you + upstream | weeks |
| D NVMe/USB/HID/simpledrm | C | you + upstream compat patches | weeks |
| E WiFi/BT | B (PCIe), D | mostly enablement, you | days–weeks |
| F GPU | upstream M3/M4 GPU program | upstream; you = test mule | months (external) |
| G audio/ISP/PM | D; audio profile needs hw measurement | mixed | weeks–months |
| H installer/distro | all above | upstream + you for j614s bits | weeks (external) |

## Risks (beyond the bring-up plan's table)

| Risk | Mitigation |
|---|---|
| No hypervisor tracing on M4 (SPTM) starves RE for new blocks | Static ADT/fw analysis; lean on upstream's M3 machines where blocks are shared |
| macOS 26.x firmware ABIs unsupported by every RTKit driver | Expect per-driver fw-version patches; keep the m1n1 volume's macOS pinned once things work |
| AIC3 unsupported in kernel | Check asahi tree first — if missing, it's the Stage C critical path; raise on #asahi-dev early |
| GPU timeline entirely external | simpledrm desktop is the honest interim; don't plan around a date |
| Speaker safety profile requires acoustic measurement rig | Use headphones/USB audio until a j614s profile exists upstream |

## Operating principle

Everything in Stages A–B and the DT/enablement halves of C–E is scarce-hardware
work where a T6040 owner adds unique value — do it, upstream it fast, coordinate
on #asahi-dev before writing anything big. Stages F and the deep halves of G–H
are upstream programs — track, test, report, don't fork.
