# Gravity Linux survey (claude, 2026-10-29): what Wallace can integrate

Gravity Linux (github.com/GravityLinux, gravitylinux.org) is a Fedora remix
for M4-and-later Apple Silicon. It forked from Asahi over LLM policy. It ships
an early alpha for the M4 Mac mini (T8132/J773g) with DCP and GPU. Their
website lists the M4 Pro and M4 Max MacBook Pro as "WIP". The team owns a
MacBook Neo, an M5 Air and an M4 mini. Contributors have M4 Max (T6041/J616c)
hardware, and the kernel branches gained J616c support on 2026-10-28/29.

All repos are cloned (blobless) under `~/code/gravitylinux/` on the d0 host:
`bootloader` (m1n1 fork), `linux` (all branches fetched), `u-boot`,
`adt-collection`, `packages`, `kiwi-descriptions`, `scripts`, `installer`,
`installer-next`, `macvdmtool`, `website`. Mesa and artwork were not cloned.

## Headline: the missing piece for fault 205 is probably CTRR_C

5012 v2 (`evidence/2026-10-25-t6040-5012-secondaries-deny-writes-near-adt.md`)
found that **the secondaries deny writes to a physical range near the ADT
end**, while the boot core allows them. Registers, descriptors and coherency
are all identical across CPUs. 5012 ruled out CTRR, but it read only the
legacy `CTRR_A_*`/`CTRR_B_*` set (`s3_4_c15_c2_*`), which is the only CTRR set
our proxyclient `apple_regs.json` knew about.

M4 has a second CTRR instance that both Asahi and Gravity now handle:

| Source | Commit | What it does |
|---|---|---|
| Asahi m1n1 `main` | `a735ea2` 2026-08-14 Yureka, "kboot: add reserved CTRR_M4 region" | "The region configured in this CTRR instance, which is enabled on secondary cores only, is 48KiB sized on M4 / M4 Pro / A18 Pro … In combination with disabling WFI/WFIT instructions, this makes smp boot reliable on M4 / M4 Pro." Adds an FDT mem-rsv |
| Asahi m1n1 `main` | `442c7a2` 2026-09-29 Sven, "cpu_regs: Add CTRR/CTXR sysregs used by SPTM" | Names the `s3_0_c11_*` space: `CTRR_C_LWR_EL1` = `[3,0,11,0,0]`, `CTRR_C_UPR_EL1` = `[3,0,11,0,1]`, plus D, EL12, EL2, CTXR and ACC variants |
| Asahi m1n1 `main` | `00b8814` 2026-09-30 Janne, "kboot: Fix M4* boot under hypervisor" | Uses the `_EL1` encodings; the reservation is gated on `!cpu_features->apple_sysregs_unlocked` (M4*, A18 Pro, M5*) |
| Gravity bootloader | `eb6cab7` 2026-08-13 Niklas Sheth, "kboot: reserve the firmware CTRR range" | Same register pair (`3,0,11,0,{0,1}`), T8132/T8140 only. "iBoot leaves a CTRR range writable only by the boot CPU. Linux can otherwise allocate those pages to secondary CPUs, causing write permission faults." It also bails if the range falls outside DRAM |

Gravity's whole SMP recipe is that reservation plus `nohlt idle=nop
arm64.nowfxt` (`kiwi-descriptions/platforms/workstation.xml`). Their M4 Max
bring-up doc (`Documentation/arch/arm64/apple-m4max-experimental.rst` on
`replacement/000-devicetree`) says "Max hardware tests use all sixteen CPUs."
Wallace already has the `idle=nop` + `arm64.nowfxt` half (`docs/BUILD_RECIPE.md`
line 502, `docs/DEVLOG.md` line 456). We have no reference to `CTRR_C`, `CTRR_M4`, `a735ea2` or
`00b8814` anywhere. The 2026-10-24 IRC review lists PR 688 in a table but does
not connect it to 205.

The match with 5012 is strong but not proven. One mismatch is that 5012
measured a denied window of more than 256 KiB, while Asahi says the region is
48 KiB. That could be an AT-granularity effect, a larger region on T6040 (the
Asahi code only warns above 48 KiB), or a second mechanism. **Ticket 5015**
covers this: read `CTRR_C_{LWR,UPR}_EL1` (and D) on every core, overlay the
range on the 5012 v3 bitmap, then boot with the reservation at `maxcpus>1`.

## Ranked integration candidates

| # | Item | Source | Wallace target | Fit |
|---|---|---|---|---|
| 1 | CTRR_C mem-rsv in kboot, plus `CTRR_C/D` names in `apple_regs.json` | Asahi `a735ea2`+`442c7a2`+`00b8814` (prefer upstream); Gravity `eb6cab7` as cross-check | m1n1 fork, `scripts/t6040-cpu-sysreg-diff.py` | **5015.** Likely 205 root cause |
| 2 | brcmfmac: `4388C2` firmware mapping (rev ID 6, `BIT(6)` mask), `bus->chiprev`, `cfg80211_port_authorized` after FWSUP SAE/PSK connect, bidirectional msgbuf packet-ID map, don't drain an uninitialised `bus_reset` work | `bits/084-bcm4388-wifi` (`fb50041b58`, `426ef46e3a`, `406b59b0a0`, `9c150e234d`) | kernel patches | **5016.** Our chip is BCM4388**C2** (`evidence/2026-07-14-t6040-bcm4388-fw-extract.md`). Port-authorized matters for WPA2/WPA3 with firmware supplicant; we have only proven an open network |
| 3 | RTKit crash-log copy with `GFP_NOIO`; skip CSTS MMIO once ANS is known dead; `panic_on_crash` parameter | `replacement/010-soc` `91a96361b3` (Niklas) | kernel patch | **5017.** We now run an NVMe root (5005/5008). An ANS crash under writeback can otherwise hang without reporting |
| 4 | T6041 (M4 Max, J616c) DT fragments: `t6041-{aop,audio,cpufreq,display,isp,mtp,pmgr,pmp,wireless}.dtsi` | `replacement/000-devicetree` `d2e4f4e4fd` | `dts/t6040*.dtsi` | **5018.** Sibling die of T6040; the closest public board description to J614s. Reference only: diff against our ADT, never copy addresses blind |
| 5 | DCP `iomfb_v26_6` panel/VRR for M4 Max; T8132 DCP hotplug | `replacement/200-dcp` `83fb190f11`, `a8aa5e2f7d` | backlight/display (open) | Covered by 5018. Firmware-ABI bound: needs a 26.6 stub, and our firmware pairing must be checked first |
| 6 | GPU: Rust `drm/asahi` G16C and G17P backends (`g16*.rs`, `asahi_m4.rs`), `m4_gpu_defconfig`, Mesa fork | `replacement/210-gpu` `ed2c67a9f6` | ticket 4004 matrix | Add to 4004. Gravity says "No GPU-driver changes" for Max yet, and the T6040 GPU variant must be confirmed before any reuse. G14 relabel rules still apply |
| 7 | tipd `sn201202x`: HPD state/IRQ handling, retained partner identity, `read_power_status` | `replacement/260-spmi-typec` `459871dc98`, `e6337f4995` | 305 follow-on | Diff against `patches/0001-usb-typec-tps6598x-add-SPMI-transport-for-T6040-SN20.patch` before 305 run 8. Their SPMI transport is Asahi's (`550afd1aa62b`, Finkelstein); our audit already chose not to import broad SN201202x nodes. Their `neo_system_power` sysfs issues SSPS and is outside SPMI_SAFETY Entry 1, so do not import it |
| 8 | dockchannel-hid: frame-size validation (`dchid_frame_size`), checksum-covered padding, `MAX_INTERFACES 32`, ring transport (T8132-only) | `replacement/090-spi-hid` `d4e7c10c30`; `187be74189` adds `tests/mtp-input-watch.c` | 5013 HID boot stall | Read during 5013's offline comparison. The ring path is T8132-only; our FIFO path works |
| 9 | U-Boot: Apple ANS2 (T8132), "Service RTKit messages while waiting for the controller", "Hold ANS reset during controller removal", M4 memory map with more DRAM banks | `u-boot` `gravity-alpha-20260925`: `61d4b40d37`, `4b738f4f51`, `ddecfb8eb6`, `49840d5797`, `9b06f6cddc` | 3013–3020 SD stage2, 3018 USB stage2 | Useful if stage2 ever reads NVMe. The memory map is T8132; T6040 needs its own |
| 10 | m1n1: clear the PMU panic counter at boot, so repeated crashes don't drop the Mac into recovery | Gravity `7243b81` | rig loop robustness | **Not without a new SPMI_SAFETY exception.** It is an SPMI write to the primary PMU scratchpad (`info-leg_scrpad + 2`). Only relevant if we see recovery fallbacks |
| 11 | m1n1: Normal-NC mapping for the iBoot handoff and `/vram` (AMCC `UNEXP_RT_HIT_DIR`); ADT carveout fallback in `mcc.c`; `pcie: Add t8132/t6040 support` (`APCIE_PHY_CTRL_RESET` BIT(4)); SPMI gen 4 | Gravity `d919a38`, `3c5b962`, `20cb4ff`; Yureka `0c1ba6b`, `14704b0` | m1n1 fork | Check whether our fork already carries these. `d919a38` was later dropped on `PR_sptm_hv` (`0902a9a`), so treat it as HV-only |
| 12 | ADT dumps: `adt-collection/26.6.2/t6040-j773s.txt` (M4 Pro Mac mini, same SoC), `t6041-j616c.txt` | Unlicense | ADT cross-checks | Free reference for comparing T6040 nodes on macOS 26.6.2 with our J614s capture |

## Progress (2026-10-29, same day)

- 5015 prep: `scripts/t6040-cpu-sysreg-diff.py --ctrr` now also reads
  `CTRR_C/D_{LWR,UPR,CTL}_EL1`. The upstream series is exported to
  `patches/m1n1-ctrr-c-v1/`; its README covers the `apple_sysregs_unlocked`
  prerequisite and the UPR end-address caveat (Asahi vs Gravity).
- 5016: `patches/brcmfmac-gravity-v1/` holds three fixes. Gravity
  `fb50041b58` is rejected: at their branch tip it calls
  `cfg80211_port_authorized()` twice per connect. **Rebase hazard for 6002/6004:**
  upstream `f0ba5fd51ff2` ("Set DMA direction for msgbuf packet IDs") breaks
  BCM4388 association. Any 7.3-based refresh needs patch 0002 with it.
- 5017: `patches/t6040-rtkit-crashlog-gfp-noio.patch` is the public half. The
  nvme CSTS-skip and `panic_on_crash` parts are in unpublished Gravity commit
  `4a0545d5`.
- 5018: `evidence/2026-10-29-t6040-5018-t6041-dt-reference-diff.md`.
- 305 cross-reference (no ticket change): the Asahi `sn201202x` SPMI
  transport that Gravity carries (`drivers/usb/typec/tipd/spmi.c`, from
  `550afd1aa62b`) is interrupt-driven. It requests three extra named IRQs
  (`select`, `sleep`, `wake`). After `spmi_command_wakeup()` it **waits for
  the `wake` IRQ (100 ms timeout)** before `tipd_init()`. Every select waits
  for the `select` IRQ (100 ms) and then confirms by reading register 0
  (`reg | 0x80` = still busy, 20 ms retry). Our transport polls register 0
  with a 100 × 1 ms budget and settles 10 ms after WAKEUP. If 305 run 7 sees
  a flaky first read, the upstream wake-IRQ wait is the reference. The
  `select`/`sleep`/`wake` interrupt numbers would have to come from our J614s
  ADT `hpm2` node.
- 5013: Codex comparison of Gravity's dockchannel-hid FIFO-path changes
  (in progress).

## Not useful or out of scope

- `installer`, `installer-next`, `kiwi-descriptions`, `packages`: Fedora/KDE
  distro plumbing. The only reuse is the cmdline above and the kernel config
  pattern (`packages/kernel/gravity*.config`).
- `macvdmtool`: adds `--rid`. Our fork already has DebugUSB + reboot.
- Hypervisor/SPTM work (`PR_sptm_hv`): macOS-under-HV for tracing. Relevant to
  6003 only, and their HV is T8132/T8140-targeted.

## Provenance and policy notes

- Code is GPL-2.0 (m1n1 is MIT+GPL-2.0, ADTs are Unlicense). Importing into our
  patch series is licence-compatible. Keep the original `From:` author and add
  our sign-off per AGENTS.md "Patch identity".
- Gravity's policy (`website/content/policies/llm.md`) forbids contributions
  from anyone whose LLM has seen Apple disassembly of the component in
  question. Wallace evidence includes firmware disassembly (for example the
  trackpad reset contract and the 25F84 hpm2 RE). So **Wallace cannot
  contribute those components back to Gravity**. Consuming their code is not
  restricted by that policy.
- Prefer the upstream Asahi form of anything that exists in both trees (CTRR,
  NVMe, tipd). Gravity's topic branches are force-rebuilt on Linux 7.3 and
  marked `EXPERIMENTAL`, so pin by SHA.
