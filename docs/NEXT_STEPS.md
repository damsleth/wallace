# t6040 Linux bring-up — NEXT STEPS

> **2026-07-29 — *** WiFi AND BLUETOOTH WORK ON THE M4 PRO. *** PCIe is fully solved.**
>
> `wlan0` + `phy0` with running firmware and the module's own OTP MAC (`84:2f:57:33:9e:d7`), and
> `hci0` with Bluetooth firmware loaded. The SD reader enumerates too. Full write-up:
> `done/2026-07-29-t6040-WIFI-AND-BLUETOOTH-WORKING.md`.
>
> **Boot it** (fresh proxy first — `scripts/t6040-debugusb-console.sh reboot`):
> ```bash
> RIG_AGENT=claude M1N1_BIN=~/Code/linux-build-out/m1n1-t6040-pcie-V1-upstream-04e8829c.bin IMAGE=Image-macsmc-hid-type-fix bash scripts/t6040-boot-dcuart.sh t6040-j614s-dcuart-wifi.dtb initramfs-dcuart-pcie-fw3.cpio.gz
> ```
>
> The chain of four fixes, in the order they mattered:
> 1. **PCIe PHY reset bit** — upstream's `apcie,t6040` path clears `BIT(4)`, not t602x's `BIT(7)`.
>    That alone ended the op-115 hang; `pcie_init()` completes and Linux enumerates the root ports.
>    Our clkgen/D1 work was never a precondition (V2 is unnecessary; do not run it).
> 2. **Endpoint power — the real link blocker.** WL_REG_ON and the SD power enable are **SMC key
>    writes**, not AP GPIOs (`/amfm function-reg_on = pKW4('gP13')`,
>    `pcie-sdreader function-sd_pwr_en = pKW4('gP19')`). `gpio-macsmc` maps a line to `gP%02x` by
>    hex → `smc_gpio` **19** and **25**, exactly what upstream's M3 Pro MBP
>    (`t603x-j514-j516.dtsi`) uses. Added the `smc_gpio` child + `pwren-gpios` → both links up in
>    4 ms / 8 ms.
> 3. **`apple,antenna-sku = "X3"`** (from ADT `wifi-antenna-sku-info = 0x3358`) — without it
>    brcmfmac never tries the per-module NVRAM name our corpus ships (`apple,mriya-WLMT-u`).
> 4. **BCM4388 rev 6 wants the c2 blobs** even though upstream maps rev ≥ 4 to the **c0 filename**,
>    so c2 content is staged under the c0 `-WLMT-u` names. **Preserve that mapping** when
>    regenerating the firmware corpus; it deserves an upstream question.
>
> **Next, in order:** cross-review and approve ticket 185, which now combines association,
> BlueZ, SDHCI, trackpad firmware/multitouch, and the PPP tether fallback in one
> byte-reproduced graphical object. Its live boot still needs the exact volatile-HIDF exception
> from ticket 126 plus CJ attendance. USB VBUS remains blocked on the `SWSr` power-role decode
> (176) — `SWDF` was data-role only. The final enrolled object must then fold the proven PCIe
> delta into the 10-second dual-mode source shape; ticket 185's diagnostic m1n1 is chainload-only.
>
> **2026-07-29 sol follow-up:** ticket 184 stages the first graphical association-capable object:
> exact live-proven PCIe m1n1 + WiFi DTB, reproducible feature kernel with built-in async PPP, and a
> minilzlib-cleared Alpine/dwm root with `iw`, `wpa_supplicant`, the required c2-under-c0-WLMT-u
> firmware mapping, and dual-ACM PPP tether fallback. Object `32a4afe1…`; exact report:
> `done/2026-07-29-t6040-wifi-ppp-network-candidate.md`. It is proposed, not runnable: Claude review
> and CJ approval/attendance remain required because the boot repeats the proven PCIe-PHY and
> `gP13`/`gP19` endpoint-power writes. It is chainload-only, not the final dual-mode enrolled shape.
>
> **2026-07-29 sol integrated follow-up:** ticket 185 supersedes 184 for the next combined boot.
> Object `m1n1-dwm-wifi-bt-trackpad-ppp.bin` SHA-256 `19690506…` adds built-in multitouch,
> the exact paired J614s HIDF, BlueZ userspace, and SDHCI while retaining graphical WiFi
> association and dual-ACM PPP. Kernel and initramfs each reproduce byte-for-byte; both pass
> m1n1's XZ decoder and the object passes strict verification at 2161 × 16 KiB. It remains
> proposed/unrunnable pending the other agent's exact review, CJ approval/attendance, and the
> explicit exception for only the non-persistent `a1f4131d…` HIDF upload/interface reset.
> Evidence: `done/2026-07-29-t6040-wifi-bt-trackpad-ppp-candidate.md`.
>
> **2026-07-29 dual-mode completion:** the same payload is now packaged behind a
> two-build-reproducible PCIe+10-second-window prefix. Enrollment candidate
> `m1n1-dwm-wifi-bt-trackpad-ppp-dualmode.bin` is `db8ab4e4…`, 2161 × 16 KiB,
> strict-verifier PASS; every byte after `0x10c000` is identical to ticket 185.
> Ticket 186 is the independent exact review. The hash is intentionally not
> allowlisted for enrollment until that review and the exact volatile-HIDF policy
> exception pass. Evidence:
> `done/2026-07-29-t6040-dualmode-wifi-bt-trackpad-ppp-candidate.md`.
>
> **2026-07-29 policy-minimal dual-mode alternative:** ticket 187 removes only
> the trackpad HIDF from the RAM root while retaining the same reproducible
> 10-second PCIe prefix, kernel, WiFi DTB, WiFi/BlueZ userspace, and dual-ACM
> PPP fallback. Object `m1n1-dwm-wifi-bt-ppp-dualmode-no-hidf.bin` is
> `969ba852...`, 2,158 × 16 KiB; its two-build root is `0ff9415f...`, expanded
> 91,717,760 bytes, and both XZ members plus strict layout pass. This variant
> cannot upload the trackpad HIDF and therefore does not need ticket 126's
> narrow firmware exception. It is still review-only: ticket 187 must pass
> independently before any allowlist or CJ-only enrollment work. Evidence:
> `done/2026-07-29-t6040-dualmode-wifi-bt-ppp-no-hidf-candidate.md`.
>
> **2026-07-29 native right-port USB2 build:** ticket 188 stages the first
> native T6040 USB2-only kernel/DT pair. Two clean builds are byte-identical:
> kernel `40670d81...`, DTB `0c39cf06...`; the minilzlib-safe kernel member is
> `50d23449...`. The compiled DT enables only right-port DARTs
> `0x392f00000/0x392f80000`, DWC3 `0x392280000`, and native eUSB2 banks
> `0x392a90000/0x392800000` in high-speed host mode. It adds no USB3,
> retimer/I2C6, role-switch, left-port, or HPM path. This is offline review
> material, not a runnable artifact: `power_on` makes volatile ATC/eUSB2 MMIO
> writes, has no inverse, and still depends on the separately reviewed HPM
> status/VBUS work. Evidence:
> `done/2026-07-29-t6040-native-usb2-right-build.md`.
>
> **2026-07-29 combined wireless + USB2 object:** ticket 189 packages the
> reproducible native right-port USB2 kernel/DT with the proven 10-second
> PCIe/WiFi/Bluetooth prefix and the no-HIDF graphical WiFi/BlueZ/PPP root.
> Object `m1n1-dwm-wifi-bt-ppp-usb2-native-dualmode-no-hidf.bin` is
> `d867bcda...`, 2,158 × 16 KiB; its corrected kernel retains the proven
> internal-keyboard HID type fix, kernel/DT are two-clean-build identical, and
> both XZ members plus strict layout pass. This is review-only, not runnable:
> it adds volatile ATC/eUSB2 writes with no exact inverse, and HPM
> status/VBUS remains a separate prerequisite. Trackpad HIDF is deliberately
> excluded so the first USB2 boot does not combine two new write boundaries.
> Evidence:
> `done/2026-07-29-t6040-integrated-wifi-bt-usb2-dualmode-candidate.md`.
>
> **⚠ For CJ:** `pwren-gpios` makes the kernel's `gpio-macsmc` perform two SMC key writes
> (`gP13`/`gP19`). PMU **GPIO outputs**, the same ones upstream Asahi drives — **approved by CJ
> 2026-07-29**. Not byte-identical to macOS though (macOS writes `0x00800001`, `gpio-macsmc` writes
> `0x01000001`); the honest claim is "the generic upstream API, which the SMC accepts".


> **2026-07-29 — RAM-root read/write path proven; indefinite proxy restored; exact
> candidates remain behind independent review + CJ approval.**
>
> 1. **USB-root software path (149) — PASS.** The approved
>    `m1n1-b0-ramroot-ext4.bin` (`ec111c6d…`) booted Alpine/OpenRC with `/` on ext4 device
>    `1:0`, which sysfs resolves exactly to `ram0`. A bounded create/`sync`/delete test on
>    `/root` passed, the installed root reporter ran, and Norwegian keymap status survived.
>    `/proc/mounts` spells the device `/dev/root`, but mountinfo plus sysfs prove that it is
>    the bootarg's `/dev/ram0`, not tmpfs or another device. This removes root mounting,
>    ext4, OpenRC, and filesystem writes from the USB-storage unknowns; VBUS and right-port
>    enumeration/data path remain. The old rehearsal image's watchdog service showed
>    `crashed` despite `watchdog0=present`; that is recorded but outside ticket 149.
>    The rig was restored to a quiescent `Running proxy` and released healthy. Evidence:
>    `done/2026-07-29-t6040-ramroot-ext4-live-result.md`.
> 2. **Observable WiFi/USB integration smoke (181; supersedes inert 153).** A real
>    DockChannel nbcon diagnostic is now clean-build reproducible:
>    `m1n1-b0-dwm-nbcon-wifi-usb-diag.bin` SHA-256 `8baf5f65…`, 1840 × 16 KiB.
>    Its 16 KiB kernel includes the bounded atomic DockChannel transport and registered
>    `ttydc0` nbcon, SMC/HID, USB storage/UAS/usbnet, and all twelve paired BCM4388 files.
>    Kernel and initramfs pass m1n1's XZ harness; the full object passes the strict verifier.
>    This is the first candidate that can return kernel dmesg over KIS while retaining the
>    graphical target. It is diagnostic-only and still does not enable right-port ATC/VBUS or
>    train the WiFi link. Ticket 181 is proposed; Claude exact-artifact review and CJ approval
>    are required before chainload. Evidence:
>    `done/2026-07-29-t6040-dockchannel-nbcon-wifi-usb-diagnostic.md`.
> 2a. **Tethered-network fallback (183).** Linux DWC3 device mode already reaches
>    UDC `configured`, while this macOS host rejected the generic Linux CDC profiles but
>    accepts m1n1's two ACM functions. A final bounded ConfigFS discriminator now matches
>    the controllable m1n1 shape: `1209:316d`, CDC device class, self-powered 500 mA
>    configuration, and two ACM functions. Exact graphical/WiFi/USB-feature object
>    `m1n1-b0-dwm-m1n1-acm-wifi-usb-diag.bin` is `8ef1da54…`, 1942 × 16 KiB,
>    strict-verifier and minilzlib PASS. A product-gated host libusb helper (`e4131b13…`)
>    can bridge the ACM bulk endpoints to a PTY if macOS still publishes no modem node,
>    while refusing m1n1's proxy gadget. Native tty or fallback bulk success makes PPP a
>    PCIe/VBUS-independent network path; failure of both closes this gadget route.
>    Ticket 183 is proposed pending Claude review and CJ approval. Evidence:
>    `done/2026-07-29-t6040-m1n1-shaped-linux-acm-network-candidate.md`.
> 3. **Proxy / integration smoke (177).** CJ enrolled
>    `rollback-m1n1-1394c345.bin`; the rig is at a stable `Running proxy`, so reviewed
>    chainloads are no longer constrained by the enrolled daily driver's 10 s fall-through.
>    The corrected WiFi/USB feature payload has a window-free smoke object:
>    `m1n1-b0-dwm-smoke-wifi-usb.bin` SHA-256 `b376cd56…`, 1839 × 16 KiB, strict verifier
>    PASS, with payload bytes identical to the dual-mode enrollment candidate `b512b9fd…`.
>    It validates the 16 KiB kernel, graphical integration, SMC/HID, and firmware probe; it
>    does not claim PCIe link-up, right-port VBUS, or ATC functionality. Ticket 177 is
>    proposed with exact hashes; Claude review and CJ approval are still required.
> 4. **USB state capture (176 → 178).** Exhaustive scans of the paired 25F84 raw kernelcache
>    and extracted AppleHPM executable find **no** ASCII or UTF-16LE `SWSr`/`SWSk`.
>    Therefore the generic TPS6598x power-role commands are not paired-Apple evidence and no
>    such write candidate may be invented. Paired
>    `AppleHPMDeviceHAL::getStatus(HPMType1Status *)` instead establishes a four-byte read of
>    logical status register `0x1a`. Exact R0-status artifact:
>    `t6040-hpm2-status-baf2c20dd761/r0-status/m1n1.bin` SHA-256 `d012adcf…`;
>    two byte-identical builds; one selector write, bounded selector reads, one four-byte
>    data read; no wake, extended write, command, role transition, or PHY/USB action.
>    Ticket 178 remains proposed because even the selector is an SPMI write. Next: Claude
>    exact-artifact review, CJ approval, then an attended capture with the passive stick
>    right and DebugUSB left. Evidence:
>    `done/2026-07-29-t6040-hpm2-status-r0-preflight.md`.
> 5. **WiFi / PCIe (175 → 179 → 180) — op-115 SOLVED; root ports enumerate; endpoint links do
>    not train.** In an attended run, V1 (upstream's T6040 PCIe path with the correct
>    BIT(4) PHY reset) completed `pcie_init()` for the first time. Linux then brought up
>    `pcie-apple`, ECAM, and both root ports. The old BIT(7) reset was the entire op-115
>    cause: ticket-058's clkgen sequence and D1 are not preconditions, so **do not run V2**.
>    Both ports still have `DLL_LINK_ACTIVE=0`, so there is no BCM4388 endpoint yet.
>    Static follow-up ruled out the remaining timing and RID leads: Linux already implements
>    the ADT's 100-us/100-ms refclk/PERST shape, and the IOMMU warnings occur after both link
>    timeouts. The `gP19` callback belongs specifically to the port-1 SD-reader child; neither
>    the WiFi child nor its bridge exposes a paired power-enable operation. A complete paired
>    port-enable audit found that J614s lacks `appclk-auto-dis`, so paired Apple clears bit 8
>    at each ADT-derived `port+0x800`; V1 leaves it set. Follow-through into the actual Linux
>    consumer refuted that as a live candidate: `apple_pcie_setup_port()` clears the same bit
>    after refclock/PERST setup and **before** writing `PORT_LTSSMCTL_START`. Ticket 182 is
>    therefore superseded/NO-GO without a rig run. The next isolated candidate remains the
>    paired reset-value delta in ticket 180 (`afd13c03` / `43165007…`), proposed only pending
>    Claude exact-artifact review and CJ approval/presence. The audit also found a paired
>    one-microsecond port-PHY settle delay and `Intr2AXI+0x80=1`; neither is yet a justified
>    live experiment.
>    `pcie_init()` must run only once per power cycle. The feature kernel already embeds the
>    paired BCM4388 firmware. Evidence:
>    `done/2026-07-29-t6040-pcie-op115-SOLVED-links-dont-train.md` and
>    `done/2026-07-29-t6040-pcie-port-enable-full-audit.md`.

> **2026-07-28 LATE (two-agent reconciliation) — no hardware action is currently ready.**
>
> 1. **USB VBUS (105/106) — R3 ran blind and is inconclusive; do not repeat yet.** Sol's exact
>    artifact review found that `SWDF`/`SWUF` are the TPS6598x **data-role** DFP/UFP commands;
>    the separate source/sink power-role commands are `SWSr`/`SWSk`. R3 therefore cannot
>    establish VBUS sourcing, R4 cannot roll back a source transition, and neither artifact
>    reads role/orientation/VBUS state. Nevertheless CJ attended one R3 run while the enrolled
>    dual-mode object's USB gadget was active. The experiment executes before `usb_init()` and
>    warm-reboots, so no transcript could reach the host; command acceptance, rejection, and
>    the identity-gate failure are indistinguishable. The right HPM pre-state is now unknown.
>    Before any repeat: restore the KIS-capable loader through CJ's 1TR flow, perform a reviewed
>    read-only state capture, and replace the inferred-VBUS plan with separately decoded
>    power-role/status/rollback gates. Evidence:
>    `done/2026-07-28-t6040-r3-r4-crossreview-no-go.md` and
>    `done/2026-07-28-t6040-r3-swdf-blind-run-no-transcript.md`.
> 2. **WiFi/PCIe (124) — D1/D2 artifact REVIEWED, but no live rig manifest/approval yet.**
>    The "m1n1 only traces the tunables" claim is refuted
>    (`done/2026-07-28-t6040-pcie-trace-mode-claim-refuted.md`): `tunables_apply_local_trace`
>    traces AND writes, the five phy tunables were applied live twice, and op-115 still hung —
>    so "apply the tunables" is a retry of negative ticket 068; do not stage it. Instead the
>    full `ApplePCIEBaseT8132::_initializePhy()`/`_enableRootComplex()` decode
>    (`done/2026-07-28-t6040-initializephy-full-decode.md`) found **exactly two Apple ops
>    m1n1 omits before the first PHY-IP access**: D1 `clkgen[0]|=BIT(5)` post-PLL-lock,
>    pre-gate-7; D2 the PHY release clears BIT(4), not t602x's BIT(7). (Also: "op-115" is the
>    read half of a plain RMW on a dead aperture — there is no PLL-lock poll in the driver;
>    J614s `lane-cfg`=0 so m1n1's rc+0x4 write is already right.) Candidate: m1n1 `19edc72b`
>    (clean series `9c35cd2c`), binary `m1n1-t6040-pcie-d1d2-19edc72b.bin` `0e065589…`, two
>    byte-identical builds, PHY-IP probe still read-only with a hard stop before any PHY-IP
>    write. Sol independently re-derived D1/D2/D5, checked ADT addresses and hard-stop scope,
>    and passed the exact artifact. Remaining gates: a separate rig ticket pinning the literal
>    command plus exact Image/DTB/initramfs hashes, CJ plan approval, KIS-observable console,
>    and an attended slot. Do not queue it ready from ticket 124 alone. Evidence:
>    `done/2026-07-28-t6040-pcie-d1d2-exact-artifact-crossreview.md`. After the aperture responds:
>    apply PLL/AUSPMA tunables + D6/D7/D8. WiFi firmware staging (168) is now complete
>    offline: corrected `Image-macsmc-hid-type-fix-wifi-fw` (`eae54e62…`) embeds the
>    exact paired C0/C2 `apple,mriya` set while retaining the live keyboard fix, SMC,
>    USB storage/UAS, and usbnet. Strict-verified dual-mode graphical object
>    `m1n1-b0-dwm-dualmode-wifi-usb-candidate.bin` is `b512b9fd…`; it is not
>    enrollment-ready until a controlled 16 KiB-kernel smoke and the hardware link gates.
>    The persistent corpus is
>    `/Users/damsleth/Code/linux-build-out/t6040-paired-fw-25F84/vendorfw`; the initramfs
>    fallback still takes `T6040_WIFI_FW=1`. Evidence:
>    `done/2026-07-29-t6040-paired-wifi-firmware-builtin.md`.
> 3. **NVMe REOPENED (174) — probably not SPTM-blocked after all.** Verified locally against our own
>    ADT and fault log: `/arm-io/ans` has 10 reg entries; `reg[9]` = `0x44dcc0000` is the **NVMe
>    controller** aperture (the window we read on 2026-07-13 and *never wrote to*) while `reg[3]` is
>    the **NVMMU** window; and our m1n1 SError was at `reg[3]+0x24908` = `LINEAR_SQ_CTRL`, exactly the
>    register upstream now **skips on firmware ≥ 15.0**. So `asc`/`sart`/`rtkit`/`BOOT_STATUS` all
>    succeeded from raw m1n1 and only that one legacy write faulted; the "protection enforced below the
>    OS" conclusion is not supported by that address. Caveat: `reg[3]` is not cleanly NVMMU-only (its
>    `+0x1300` boot-status poll succeeded while `+0x1210` faulted) — no strict two-window model.
>    **Needs a fresh approval**: the probe cycles `CC.EN` on the controller holding macOS and error
>    paths call `pmgr_reset(ANS)`. Also: upstream's `reg_len >= 10` guard is a byte-vs-count bug worth
>    a drafted upstream note. `done/2026-07-28-upstream-review-nvme-reopened-pcie-d2-confirmed.md`.
> 4. **PCIe candidates V1/V2 now staged on UPSTREAM's t6040 path (175)** — offered as an alternative
>    to the reviewed fork candidate in item 2, because upstream already carries D2: `apcie,t6040` →
>    `regs_t8132` with `APCIE_PHY_CTRL_RESET = BIT(4)` (PR 633, merged; our own ticket-046 audit had
>    recorded this and our fork kept clearing BIT(7) through every op-115 run). **V1** `28a4e0cf…` =
>    upstream `pcie.c` wholesale on our t6040 line (keeps our stage-2 log-buffer guard; inherits
>    upstream's GXF stack fix and ATC EQA offsets) and tests whether the wrong reset bit was the
>    *entire* cause. **V2** `3916bf15…` = V1 + the proven ticket-058 clkgen PLL sequence + delta D1,
>    gated to `apcie,t6040`. Run V1 first — a negative promotes V2, the reverse makes a success
>    unattributable. Both attended-only (upstream has no early return), both need the same exact-artifact
>    review and rig ticket as item 2. `done/2026-07-28-t6040-pcie-upstream-v1-v2-candidates.md`.
> 5. **USB3 DT (170) — exact data path staged fail-closed, not runnable.** The Linux tree and
>    Wallace mirror now carry all 44 translated right-port ATC banks, DWC3 PHY/reset/role
>    wiring, and disabled I2C6 `atcrt0/1/2` inventory. Do not add the old
>    `apple,t8103-atcphy` fallback: its probe resets/writes a different five-window layout.
>    Paired-driver analysis corrects the earlier retimer premise:
>    `AppleTypeCRetimer` monitors health/crash state; neither it nor AppleHPM's
>    `enableOptions()` programs normal lane mode. A Linux `atcrt` mode-control clone is therefore
>    not a demonstrated USB2 prerequisite, but guessed PS883x compatibles remain forbidden and
>    the children stay disabled until physical power/clock/reset ownership is known. The
>    compile-only DTB passes and all functional nodes remain disabled. Evidence:
>    `done/2026-07-28-t6040-usb3-right-data-path-dt-staging.md`,
>    `done/2026-07-29-t6040-atcrt-owner-correction.md`.
>    Yuka independently tried the five-window `apple,t8122-atcphy` fallback and
>    retains it only as `feature/t604x-usb-broken` (`2849873b`): T604x is CIO4/TB5,
>    has fewer tunables, and the paired T6040 USB2 event bank does not match the
>    fallback's core-relative access. Do not import it unchanged. Evidence:
>    `done/2026-07-29-t6040-yuka-usb-branch-review.md`.
>    A native compile-only USB2 slice is now staged as
>    `patches/0001-phy-apple-add-experimental-T6040-USB2-only-slice.patch`: separate
>    bank-0/bank-1 resources, exact paired host ordering, no probe-time ATC writes, no USB3,
>    and no guessed inverse. It builds cleanly but is deliberately not in kbuild and has no
>    runnable DT/object. HPM VBUS, independent review, a USB2-only DT override, attendance,
>    and power-cycle recovery remain gates. Evidence:
>    `done/2026-07-29-t6040-usb2-only-driver-slice.md`.

> **2026-07-28 (state of play) — battery/thermals DONE; USB + WiFi are the frontier.**
>
> Daily driver (`5931f9c3`, enrolled): dwm + Norwegian keyboard + working SMC battery/charger/temp
> (ticket 165 done). USB device mode proven on the M4 (`udc=configured`, all CDC flavors enumerate),
> but macOS attached no interface to the tested Linux CDC descriptors. The old claim that generic
> host CDC drivers are absent is refuted: ACM/ECM/NCM host kexts are loaded and class-match
> generically. Ticket 183 owns the final m1n1-topology discriminator. **The two priorities remain
> USB read/write and WiFi, both decoded and both needing an
> attended rig session:**
>
> 1. **USB host + VBUS (096 → 097 → 108/109/112/113).** Fully decoded:
>    `AppleHPMInterface::roleSwap()` issues the `SWDF` 4CC (Swap-to-DFP = host/source, enables VBUS) to
>    CMD1 `0x08`, confirmed via `execute4Cc`. An **R3 candidate = the proven R2 SSPS path** in
>    `m1n1-hpm2/src/t6040_hpm2.c` with `command[4]={'S','W','D','F'}` instead of `{'S','S','P','S'}`.
>    Gate: byte-level review of the 4CC constant (a DFU-class 4CC exists in the vocab), then an attended
>    run on the 096/097 SPMI framework (right-HPM identity gate + recovery). Worst case is odd port
>    state until a power cycle. If VBUS comes up, the bus-powered stick on the right port enumerates and
>    167's built-in usb-storage/usbnet drivers light up read/write + a dongle NIC.
> 2. **WiFi via PCIe (124 → 068 → 168).** `BRCMFMAC`/`CFG80211` are already built in — WiFi needs no
>    kernel work, only PCIe link-up. m1n1 runs T6040 PCIe in **trace** mode (logs tunables, writes
>    nothing); op-115 is a PLL-lock poll at `0x417040090`. The missing precondition is *applying* the
>    `apcie-phy-tunables` (5 RMWs at `0x417004000`/`0x417008000`, all clearing bits). That is a
>    **hardware write to the PCIe PHY** — beyond the live-read authorization — so it needs a supervised
>    session, a bounded reviewed m1n1 change (apply, don't trace, just those tunables), then re-check
>    the op-115 poll. Then stage the BCM4388 `apple,mriya` firmware (168) into the image.
>
> Everything else (feature kernel, DT, harness, minilzlib fix, address decodes) is landed. The USB and
> WiFi frontiers are the same shape: decode complete, one bounded hardware action left, maintainer-gated.

> **2026-07-28 network campaign (amended 2026-07-29) — DWC3 gadget works; attachment gap narrowed.**
>
> The macsmc feature object (dwm + battery/thermals + usbnet + USB-tether gadget) is enrolled and
> working: keyboard fixed (`HID_TYPE_FIX`), dwm up. Tether-ethernet was chainload-tested in four gadget
> flavors (RNDIS, CDC-ECM, CDC-NCM, ACM+NCM). **All enumerate on this Mac over the tether — Linux dwc3
> gadget mode works on the M4, the biggest unknown, confirmed YES.** But macOS creates no interface for
> any flavor (not even CDC-ACM, which it binds fine from m1n1's own proxy gadget). Later panel evidence
> proved UDC state `configured`, so the M4 completed enumeration. Host inspection then proved generic
> ACM/ECM/NCM drivers are installed, loaded, and class-matched. The remaining gap is macOS composite
> attachment to the tested Linux descriptor shapes; ticket 183 stages one final m1n1-topology test.
>
> **Historical diagnostics (both completed):**
> 1. **Fastest — read the panel.** On the enrolled dwm (getty on tty1), run:
>    `cat /var/log/ecm-gadget.log; ls /sys/class/udc; ls /sys/class/net; dmesg | grep -iE 'dwc3|gadget|configfs|ncm|ecm|udc'`
>    and also `cat /sys/class/power_supply/*/uevent; cat /sys/class/hwmon/*/temp*_input` (the macsmc
>    battery/thermals test, which was never network-observable). That says exactly what the M4 did.
> 2. **Autonomous once enrolled — a dmesg-over-KIS diagnostic kernel** (ticket 153 `nbcon` patch, applies
>    cleanly): `console=ttydc0`, no gadget, booted via DebugUSB → login + dmesg over KIS. KIS and the
>    gadget are mutually exclusive on the DFU port, so this is a separate diagnostic boot, and
>    KIS-chainload needs the bare proxy loader (`rollback-m1n1-1394c345`) enrolled, or the diagnostic
>    object enrolled directly.
>
> **WiFi:** still gated on PCIe op-115, which needs *applying* the PHY tunables (writes to PCIe PHY at
> `0x417004000`/`0x417008000` — m1n1 currently only traces them, ticket 124). That is a hardware WRITE,
> beyond the live-read authorization, and risky to do blind — left for a supervised session.

> **2026-07-27 (offline session) — USB and initramfs threads advanced; one address bug fixed.**
>
> - **Initramfs decode limit (160):** built `scripts/t6040-minilzlib-harness.sh` — a host binary around
>   m1n1's own minilzlib that reproduces the machine's XzDecode pass/fail exactly, so any initramfs is
>   clearable with **zero rig time**. The limit is **content/level dependent**, not a size (200 MiB zeros
>   and 200 MiB `-6` decode; 278 MiB `-9e` fails). Keep the 128 MiB verifier guard as a backstop; use the
>   harness as the real check. Mechanism -> ticket 171.
> - **Type-C / USB (170):** mapped the t6040 Type-C stack from the live ADT. The PHY/dwc3/DART half is
>   DT-describable now -- `atc-phy,t6040` @ `0x393000000`, `usb-drd,t6040`/`t8132` @ `0x392280000`, two
>   DARTs -- adaptable from `t602x-dieX.dtsi`. **But the PD controller is on SPMI, not I2C**, so the merged
>   upstream `cd321x` I2C driver won't source VBUS; that half is still the 096 SPMI wall. New: **ATC
>   retimers** `uatcrt0/1/2` (i2c6) are physically in the data path and our force-host DT never
>   touched them. A 2026-07-29 paired-driver correction shows the macOS `AppleTypeCRetimer`
>   normal paths are health monitoring, not lane-mode programming; keep their DT inventory
>   disabled, but do not treat a Linux mode-control clone as a proven USB2 prerequisite.
> - **Address correction (affects 124 + 170):** `adt.py` `.reg` returns *untranslated* bus addresses;
>   the `/arm-io` `ranges` delta is **+0x200000000** in the low window. So the PCIe op-115 poll is
>   **`0x417040090`** (PhyCommon[0] `0x417004000`, PhyPhy `0x417008000`) -- the trace was right -- and last
>   night's "die alias" guess was wrong. The working `t6040.dtsi` addresses already bake in the delta.
>
> **Next offline step:** the fail-closed atcphy/dwc3/dart/retimer inventory now exists using the
> **`0x3xx`** CPU-physical addresses (not the raw `0x1xx` ADT reads). The next functional step is a
> native or reviewed handoff implementation of the decoded T6040 eUSB2/ATC host sequence; VBUS
> remains an independently reviewed SPMI-HPM prerequisite.

> **2026-07-26 — dwm runs on the panel with a working keyboard.** The graphical target is reached
> (`3ec81ef3`), and `m1n1-b0-dwm-hidpi.bin` `59622e78` is the same thing with the HiDPI font fix.
>
> **Rig etiquette, learned the hard way today.** Every *successful* chainload boots Linux and destroys
> the proxy it needed, so `bash scripts/t6040-debugusb-console.sh reboot` is required before **every**
> `t6040-boot-raw-object.sh`. The script now refuses to upload into a dead proxy (157), kills its
> uploader as a process group so no orphan can corrupt a later run (158), and logs unbuffered — so
> `tail -f ~/Code/linux-build-out/raw-object-chainload.log` shows live progress. Diagnostic tell: CPU
> must climb past ~5 s within the first 10 s; pinned at `0:00.09` means nothing is behind the pty.
>
> **The panel is still the only source of kernel dmesg** — `console=ttydc0` is inert because the
> shipping DockChannel driver registers no console (153/159). Screenshots remain necessary evidence for
> any graphical result. Applying `patches/t6040-dockchannel-nbcon.patch` is one rebuild away
> and would make smokes self-verifying.
>
> **Immediate next steps, in order:**
>
> 1. **162 / 163 — untethered graphical boot.** 162 enrolls `59622e78` directly (maintainer, 1TR). But
>    prefer **163** first: a dual-mode graphical object keeps the 10-second debug door, and an enrolled
>    graphical-only object does not — losing the door makes every later change cost a 1TR cycle.
> 2. **169 — get off one core.** The graphical target runs `maxcpus=1`: one P-core of 14. Land 123 (or
>    121) first, then rebuild the graphical object with the working SMP bootargs, changing one variable.
>    SMP at fixed frequency *before* cpufreq (006), or a failure is unattributable.
> 3. **164 / 165 — backlight and battery.** Both measured absent from the kernel config
>    (`APPLE_DWI_BL`, `MACSMC_POWER`, `HWMON`), so both are cheap offline wins. 165 is read-only
>    telemetry; charger and PMU-voltage writes stay forbidden.
> 4. **167 — USB ethernet.** `USB_USBNET` is absent; enabling it converts the USB milestone straight
>    into networking, well before PCIe is understood. WiFi needs **no** kernel work (`BRCMFMAC` and
>    `CFG80211` are already present) and is gated purely on PCIe op-115 (124/168).
> 5. **149 — `root=/dev/ram0` ext4**, unblocked by 147, object `ec111c6d` staged.
> 6. **160 — the initramfs decode limit** in (97.3, 278.9] MiB. A host harness around m1n1's portable
>    minilzlib can find it with no rig time.
>
> Still attended-only: **124**'s live PCIe read (an ungated-aperture SError could wedge the tether) and
> anything touching HPM/ATC (096/097).

> **2026-07-25 — MILESTONE B0 REACHED.** An enrolled object now cold-boots
> untethered into Alpine/OpenRC on the internal panel (ticket 101 done; object
> `f290833c`, 578 × 16 KiB). Root cause of all prior enrolled failures: **the
> object's total size must be a multiple of 16 KiB** — otherwise m1n1 is never
> entered. The builder enforces it now. The 2026-07-24 handoff text below is
> retained for history; where it says B0/101 is blocked, read it as **done**.
> **Ubuntu 24.04 also boots untethered** (object `4784c29c`), and the dual-mode 10 s
> debug window is proven both ways (ticket 140). No object-size ceiling was found to
> 256 MiB (ticket 137). Open work has shifted to **persistent USB read/write**
> (138, gated on the HPM/ATC link — 096/097 or U-Boot 128), **WiFi** (139, needs PCIe
> op-115 plus a networking-capable DIET kernel, 143), and a **graphical target**
> (142, Alpine + Xorg + dwm).


Handoff state (2026-07-24): the exact B0 release object boots tethered into
Alpine/OpenRC with the internal panel, keyboard, watchdog, and no storage
probe. The right-side HPM2 has also passed the staged inactive → WAKEUP/state
`0x07` → SSPS/S0 `0x00` ladder. The passive USB stick has **not** enumerated,
and the verified OpenRC disk image has not been flashed.

The rig is healthy at `Running proxy`. Ticket 118's post-SSPS recovery control
passed after the maintainer's power cycle and bounded proxy health check; the
earlier VDM failure remains unattributed. Continue to use its exact
fail-closed recovery checklist for every live ticket.

In parallel, seek new primary evidence for ticket 096's R3 rollback no-go and
close the remaining ticket-082 volume identity/backup/action-split fields.
Ticket 119 has conditionally reviewed the dual-mode B0 object; its live trigger
classification remains ticket 101 work. Operational details and history: `DEVLOG.md`; long-term:
`ROADMAP.md`. Read the DebugUSB rules before touching the rig.

The complete approved-ticket overnight disposition is
`done/2026-07-24-t6040-open-rig-ticket-audit.md`: none was both independently
ready and safely unattended, so the healthy `Running proxy` state was
preserved while offline blockers advanced.

## Immediate storage-path gate: finish right-port HPM/ATC host link

The port map and first no-root host smoke are complete historical gates. The
authoritative map is `usb-drd0 = left-back` (DebugUSB), `usb-drd1 = left-front`,
and `usb-drd2 = right` (the attached stick). Keep `usb-drd0` disabled in every
host-mode experiment.

**Result 2026-07-21:** the initial KIS attempts failed even after a cold start
because the tether was on the wrong physical port. Moving it to the previously
proven top-left/rear port restored KIS. Ticket 057 then captured the ADT
successfully and established the authoritative map: `usb-drd0 = left-back`,
`usb-drd1 = left-front`, `usb-drd2 = right`. Keep `usb-drd0` disabled because it
carries DebugUSB. Build/hash/cross-review only the one-port DTB matching the
external drive, then run the no-`root=` smoke. Exact capture result:
`done/2026-07-21-t6040-usb-port-map-adt-result.md`; failed-attempt history:
`done/2026-07-21-t6040-usb-port-map-adt-attempt.md`.

**Drive selection 2026-07-21:** the external drive is on the right-side port,
so the live candidate is exclusively `usb-drd2` /
`t6040-j614s-dcuart-usb-host-right.dtb`, SHA-256
`9bee944b8bb0d6d7ab541962ea2edc9a57c4069fedcd6c32db21e3b824a43759`.
Ticket 063 used the independently reviewed six-file manifest; do not
substitute the left-front or retired all-port DTB.

**Smoke result 2026-07-21:** ticket 063 ran once. The right-side DARTs and xHCI
controller initialized cleanly at `0x392f00000`/`0x392f80000` and
`0x392280000`, but both the initial and ten-second reports showed only the two
root hubs. No child USB device or `sd*` appeared; the shell remained responsive
and there was no SError, DART fault, reset, or NVMe probe. Do not populate the
rootfs yet. Ticket 064 has now bounded the failure: the saved ADT contains a
right-side SPMI HPM (`hpm2`), T6040 ATC PHY (`atc-phy2`), and shared `acio2`
parent, but the Linux DT exposes none of that physical-link path. The
force-host patch creates xHCI while its generic PHY handles are absent; it
cannot establish CC/orientation, eUSB2-repeater state, or host PHY mode. Exact
analysis: `done/2026-07-21-t6040-usb-right-no-connect-analysis.md`.

**Storage-free pivot, 2026-07-23:** the powered hub's supply is unavailable, so
ticket 065 is cancelled unrun. Ticket 066 built and host-validated a
reproducible Alpine 3.24.0 aarch64 RAM-root: 3.9 MB compressed, loaded entirely
through m1n1, with a DockChannel Alpine shell and no storage dependency. Ticket
067 then booted it successfully: Alpine 3.24.0/aarch64 reached a responsive
shell, the RAM-only write test passed, `/proc/partitions` was empty, and no
storage controller probed. The internal keyboard did not register, however:
MTP firmware reached `Keyboard ready`, but the 7.1.3 USB-host kernel stopped
with a zero-ID HID device and no `/dev/input`. This is a kernel/DockChannel
receive-path regression, not an Alpine userspace issue. Offline ticket 069
found no config, DT, or HID-source omission and tested the mailbox driver's
unmasked W1C-acknowledge/threaded-drain window as a possible lost-RX race.
Ticket 071 booted the exact mask/drain/re-arm candidate once. Alpine and ttydc0
worked and `/proc/partitions` stayed empty, but input registration remained
absent: empty `/proc/bus/input/devices`, no `/dev/input`. The race correction
is therefore not a sufficient HID fix.
The independently reviewed local control, ticket 070, was run and repeated once
at the maintainer's request. Both attempts handed off, showed kernel text, then
returned to the Asahi/m1n1 logo without presenting the Alpine framebuffer
shell. With no ttydc0 in that old kernel there is no post-handoff host log, and
the keyboard could not be tested. Do not retry the old-kernel/Alpine
recombination, and do not retry ticket 071. Offline ticket 072 has now built
and statically verified the observation-only current-kernel trace across
DockChannel hard IRQ/pending bits, FIFO drains, DCHID event/report parsing,
STM-ready state, and identity/interface creation. The exact storage-disabled
candidate is `Image-hid-state-trace` (`e7138c03...`) with the unchanged
ticket-071 DTB (`2782b922...`) and ticket-067 config (`8e11399b...`). It adds
read-only counters and sparse semantic logs but no receive kick, retry, new
MMIO access, or control-flow change. Independent exact-artifact review passed.
Ticket 074 then ran once: ttydc0 TX delivered the Alpine banner and prompt, but
RX accepted neither LF, CR, nor the terminal-position response, so none of the
trace commands could run. The host KIS daemon, raw PTY, and persistent reader
were healthy. The pre-registered stop was taken and recovery restored
`Running proxy...`. Do not repeat 074 unchanged. Offline ticket 075 built a
bootarg-gated initramfs reporter that automatically emits the same bounded
trace/input/partition inventory over working ttydc0 TX without requiring an
inbound shell command. Its exact reproducible archive is
`d5b790c63276816a3d69071797da459918717924885174d2a8b84225c6b24093`;
host gating/output tests and embedded-script identity pass. Ticket 076 then
captured the complete report: HID DockChannel IRQ/FIFO RX, DCHID parsing,
identity, and all six `hid_add_device()` calls succeeded, but no Linux input
device appeared. Ticket 077 corrects the first interpretation: relevant
configs and imported DockChannel HID source match the known-good line, while
the failing Asahi `hid-apple` adds a BUS_HOST match and rejects the transport's
unset `hid->type`. Ticket 078's six-line type assignment live-registers
`Apple DockChannel Keyboard` as `input0/event0`. Exact result and decode:
`done/2026-07-24-t6040-076-hid-trace-result.md` and
`done/2026-07-24-t6040-077-hid-boundary-decode.md`, plus
`done/2026-07-24-t6040-hid-type-fix-result.md`.
Analysis, preflight, and result:
`done/2026-07-23-t6040-alpine-hid-regression-analysis.md` and
`done/2026-07-23-t6040-alpine-hid-rx-rearm-preflight.md`, and
`done/2026-07-23-t6040-alpine-hid-rx-rearm-result.md`. Trace artifact and
procedure:
`done/2026-07-23-t6040-alpine-hid-state-trace-preflight.md` and
`done/2026-07-23-t6040-alpine-hid-state-trace-result.md`. Automatic reporter:
`done/2026-07-23-t6040-alpine-hid-trace-auto-reporter.md`; replacement
preflight: `done/2026-07-23-t6040-alpine-hid-trace-auto-preflight.md`. Old
control preflight and result:
`done/2026-07-23-t6040-alpine-keyboard-control-preflight.md` and
`done/2026-07-23-t6040-alpine-keyboard-control-result.md`.
Artifact, preflight, and result:
`done/2026-07-23-t6040-alpine-ramroot-artifact.md`,
`done/2026-07-23-t6040-alpine-ramroot-preflight.md`, and
`done/2026-07-23-t6040-alpine-ramroot-boot-result.md`. A powered-fixture
discriminator is no longer in the plan: the attached passive right-port stick
is the fixed test device, and staged HPM/ATC bring-up remains the
persistent-root blocker. Exact initial USB run result:
`done/2026-07-21-t6040-usb-host-right-smoke-result.md`.

## Bootable-build ladder: B0 first, persistent root later

The next honest machine-level milestone no longer waits on USB or internal
NVMe: boot picker → enrolled raw m1n1 object → self-contained Alpine RAM distro
on simpledrm/fbcon with internal keyboard, watchdog, and no host payload upload.
The detailed experiment contract and safety gates are in
`docs/BOOTABLE_BUILD_EXPERIMENTS.md`.

Tickets 076–081, 089, and the live release proof 100 are complete. Ticket 079 produced the twice-reproducible
Alpine/OpenRC release RAM distro `ddd981711e91...`: normal init/runlevels,
fbcon and delayed ttydc0 consoles, watchdog, bounded health report, locked
password, no enabled networking, and no block nodes. Ticket 080 established
that direct raw m1n1 supports the
required concatenated payloads, entry
`0x800`, and a strict host verifier under a conservative 64 MiB object policy.
A control object using ticket 078's exact live-proven HID-restored payload was
built, twice reproduced, and passed its single-object delivery test:
`m1n1-b0-alpine-hid-restored.bin`,
`b50f52ab1fac473db2e9257c5363ef7905e4d1da5c8535fbf417209b09319172`.
Ticket 089 remained a diagnostic control. The release object was packaged,
twice reproduced, independently reviewed, and live-proven as
`m1n1-b0-alpine-openrc.bin`,
`2371ee5dfbfab591397fc333e7da212fb7582bfb2eaddaa6438005f5bb41759b`.
Ticket 100 reached the OpenRC default runlevel, kept the watchdog alive, found
the internal input device, kept `/proc/partitions` empty, and accepted a line
typed on the internal keyboard at the panel shell. Ticket 081 is done. Ticket
082's procedure exists; only target-volume UUID, current enrolled-object
backup/hash, and split-vs-single execution approval remain before
plan-approved runnable=false ticket 101 can run. Ticket 119 conditionally
passed dual-mode object `46237ade...`, with exact post-prefix identity and an
explicit version/Rust provenance caveat. Ticket 101 owns separate cold-boot
and DebugUSB trigger checks. Exact format,
preflights, and results:
`done/2026-07-23-t6040-raw-boot-object-layout.md` and
`done/2026-07-24-t6040-b0-alpine-single-object-preflight.md`, and
`done/2026-07-24-t6040-alpine-b0-release-bundle.md`, plus
`done/2026-07-24-t6040-b0-alpine-openrc-single-object-result.md` and
`done/2026-07-24-t6040-b0-enrolled-cold-boot-preflight.md`.

Ticket 026's installer audit corrected a stale premise: current
asahi-installer already enrolls `boot.bin` with the required raw entry `2048`
and lowest address zero. Its real M4 gaps are J614s/T6040 admission, treating a
self-contained Linux payload as an atomic object during install/repair/upgrade,
and macOS 26 AEA plus moved/extended firmware layouts. Requirements and safe
patch split: `done/2026-07-23-t6040-asahi-installer-requirements.md`.

Ticket 030 has now completed the restore-recoverable paired-firmware corpus.
The deterministic, read-only 25F84 raw archive (`cb7a4ee2...`) and its
22-file Linux `vendorfw/` tree are staged at
`/private/tmp/t6040-paired-fw-25F84/`; the exact path/hash map is enforced by
`scripts/t6040-build-paired-firmware-corpus.py`. This closes firmware
provisioning for trackpad, BCM4388, ISP setfiles, and kernel-embedded ASMedia,
and preserves DCP/SPTM/TXM/InputDevice raw payloads. The only non-restore item
is machine-private ALS calibration; ticket 087 owns a later read-only capture
from the M4's macOS installation. The exact upstream-derived capture and
fail-closed M1 extractor are prepared at
`done/2026-07-24-t6040-als-calibration-preflight.md`; corrected independent
review passed, and only an attended main-macOS boot remains. It is not a B0 or
USB-root dependency.
Provenance and limits:
`done/2026-07-24-t6040-paired-fw-corpus.md`.

Ticket 025's B1 host preparation is also complete but remains post-B0. The
draft T6040 U-Boot target maps only DT-derived RAM/framebuffer, disables
autoboot and every MMIO-backed bus/device driver, builds reproducibly, and
embeds `bootefi hello`. A raw final U-Boot payload must be zero-padded to its
ARM64 Image `image_size`; exact audit and draft:
`done/2026-07-23-t6040-uboot-noio-prep.md` and
`patches/uboot-t6040-noio-prep.patch`. No live run is proposed.

Persistent Linux state remains B2. Tickets 032, 060, and 098 have completed
the host artifacts, guarded recipe, and verified OpenRC image. The path resumes
only after ticket 096 proves rollback and the decomposed right-port HPM/ATC,
enumeration, read-only block, flash, and write-test tickets pass. Internal NVMe
remains blocked by SPTM/CoastGuard. Do not
fold storage, SMP, cpufreq, PCIe, or enrollment into the first self-contained
boot.

Ticket 060's rootfs recipe is now complete and host-tested. The guarded script
pins Alpine 3.24.0 aarch64, stages matching modules and the paired firmware
corpus, records GPT/PARTUUID/ext4 identities, and refuses destructive deployment
unless given a Linux removable whole disk plus an exact erase confirmation.
This does **not** clear the live gate: no real disk may be populated until a USB
child and `sd*` persist for at least ten seconds. Exact recipe and test:
`done/2026-07-23-t6040-usb-rootfs-recipe.md`.

Ticket 086 turned that recipe into a structurally valid 1 GiB GPT/ext4 Alpine
image without touching a block device. The image SHA-256 is
`32a897cb48bab0f066528b76cc6ef6b364a2807b43371d5b2f3c2abcced42cd1`;
its root selector is
`PARTUUID=1b841e9b-65a5-4687-83f2-6c728961ad14`. A later PID-1 audit found
that its minirootfs lacks `/sbin/openrc`, so it must not be flashed; ticket 098
now supersedes it with a verified OpenRC B0 GPT/ext4 image, SHA-256
`1c493fad1d1b...`, PARTUUID `e4731abe-3566-4c3a-8019-c8828ca27a5a`.
Primary/backup GPT, ext4, OpenRC runlevels, watchdog/health services, consoles,
and 22-file firmware manifest pass independent host inspection. Two builds
have byte-identical normalized trees; raw nondeterminism is fully isolated to
`mkfs.ext4 -d` inode ctimes and checksums. The stick is currently attached to
the M4, not the M1. This does not clear the already-proven M4 enumeration
failure: external root still waits on ticket 096 and the decomposed
right-port link/enumeration/block/flash/root tests. Exact results:
`done/2026-07-24-t6040-usb-root-image.md` and
`done/2026-07-24-t6040-openrc-usb-root-image.md`.

Ticket 023's 2026-07-23 upstream refresh found no published T6040 ATC/HPM
implementation. The 2026-07-24 paired-kext decode has now removed one static
blocker: `AppleT6040TypeCPhy::_sRegisters[44][8]` matches all four target ADT
bank lists exactly, and the tunable encoding byte-proves bank+offset. The
right-port USB2 HOST record is `reg[4]+0x8`, mask `0x7003`, value `0x3`—the
same as DFLT—so replaying that one record cannot test the missing link.
The direct 8,580-byte eUSB2 initializer is now decoded too: it uses only banks
0/1 and six offsets with an exact RMW/reset/event/status/mode sequence. Paired
`AppleT8150USBXHCI` proves its host call uses power level 2, options
`0x40000`, timeout 500 ms, selecting the false/false branch and final mode 2.
This still is not a live candidate. The target ADT explicitly selects Apple
SPMI Gen3 plus an SN201202x class-10 HPM. Paired discovery reads six bounded
register windows, but it first crosses a provider state boundary and its
`readRegs()` changes timer/transaction state; this is not an observation-only
live probe. The class path is now proved as HALType5 plus
`AppleTCControllerType10`, and `turnOnVbus()` reaches an exact nine-byte
address-`0x14` RMW (`raw[1] |= 0x0d`, `raw[7] |= 0x08`). That is still not a
live candidate: no local inverse exists, and cached command, interrupt,
USB-config, power-state, and repeater coordination remain. Do not rerun the
same unpowered topology or synthesize SPMI/PHY writes. Exact checkpoints:
`done/2026-07-23-t6040-atcphy-upstream-checkpoint.md` and
`done/2026-07-24-t6040-atcphy-kext-bank-map.md`, plus
`done/2026-07-24-t6040-eusb2-init-sequence.md` and
`done/2026-07-24-t6040-hpm-spmi-discovery-boundary.md`, plus
`done/2026-07-24-t6040-hpm-class10-host-transition.md`.

**Late 2026-07-24 upstream movement:** yuka's public `tps6598x-spmi` branch
head `dcc5f1bc...` recognizes the exact J614s Gen3 SPMI and SN201202x
compatibles and compiles locally. It is the leading implementation candidate,
but the only reported hardware success is T6000's I2C `foreach-hpm` path.
T6040 initialization is state-changing (WAKEUP/SHUTDOWN, register-select
writes, possible `SSPS`, IRQ clear/mask) and currently has an unbounded poll,
double-shutdown path, and other error/bounds issues. Do not build a rig
candidate or retry the stick from it. Audit:
`done/2026-07-24-t6040-yuka-hpm-spmi-branch-audit.md`.

**Maintainer-approved SPMI policy refinement, 2026-07-24:** SPMI is now
deny-by-default and endpoint/opcode-scoped rather than transport-wide
forbidden. PMU/Abbey, charger, NVRAM, firmware/flash, AOP-SPMI, RESET, unknown
endpoints, scanning, and blind register access remain prohibited. The sole
eligible endpoint is exact right-port `/arm-io/nub-spmi-a1/hpm2` (Gen3,
reg0 `0x309198000`, sole child, SID `0x0c`) under
`docs/SPMI_SAFETY.md`.

Do not run Yuka's branch wholesale. Ticket 092 established the exact-endpoint,
fail-closed candidate pattern. The completed live ladder is:

- 093: selector ACKed but the inactive window returned `0x00`; no data read;
- 094: WAKEUP + 10 ms activated it and logical power state read `0x07`;
- 095: exact DATA1 `00` + CMD1 `SSPS` completed and final state read `0x00`.

No mask/W1C, role/VBUS, USB configuration, PHY, xHCI, or storage operation was
present in those binaries. Ticket 096's final PAC-aware static pass found
paired software-object removal and semantic eUSB2/ACIO shutdown, but no
VBUS-off operation, race-safe `0x14`/W1C/cache inverse, exact mask/detect
restoration, or restoration of pre-SSPS state `0x07`. R3 therefore remains a
no-go and tickets 102–108 must not be built or run without new primary
evidence. Tickets 097 and 099 remain umbrellas for smaller experiments:
post-S0 status, optional mask work only if justified, HPM host transition,
ATC/xHCI enumeration, read-only block access, separate destructive flashing,
tethered read-write root, and a final untethered root boot. Ticket 098's
OpenRC image is complete. New tickets are proposals, not approvals.

**R0/R1/R2 result history:** the original full-tree CRC gate rejected the standard
chainloader's volatile ADT handoff-field rewrites, explicitly logged zero SPMI
transactions, and recovered normally. Replacement commit `ef707f51f181`
then failed closed because `adt_get_reg()` returned the `/arm-io`-translated
`0x509...` addresses while the gate expected raw `0x309...` tuples. A leased,
read-only ADT query confirmed both representations without MMIO or SPMI.
Commit `471700035efd` then passed the gate: its selector command ACKed but read
back `0x00`, proving the endpoint register window remains inactive without
WAKEUP. The independently reviewed narrowed R1 at `3e4ea5b880d1` sent one
WAKEUP, waited exactly 10 ms, then read selector `0x20` and logical power state
`0x07`; it linked no extended write or SSPS and recovered healthy. Tickets
093 and 094 are done. Independently reviewed m1n1 `276f4059d8c4`, binary
`23737cd3...`, then repeated WAKEUP, observed `0x07`, wrote only DATA1 `00`
and CMD1 `SSPS`, and observed final state `0x00`. Ticket 095 is done. Its
transcript is `630fe61a...`. R1/R2 were never combined with USB/PHY.
The following VDM recovery failed and one DebugUSB reattach had no console.
Ticket 118 later completed the recovery control after a maintainer power cycle:
KIS attached, the proxy health check passed, and later reboot/re-entry cycles
were healthy. Do not infer that SSPS caused the original transient.
See `done/2026-07-24-t6040-hpm2-r0-attempt1.md` and
`done/2026-07-24-t6040-hpm2-r0-attempt2.md`, plus
`done/2026-07-24-t6040-hpm2-r0-attempt3.md` and
`done/2026-07-24-t6040-hpm2-r1-wake-read-result.md`, plus
`done/2026-07-24-t6040-hpm2-r2-ssps-s0-result.md`.

**Concrete right-stick ladder (new tickets 102–113):**

1. 102/103 are blocked by 096's R3 no-go; no post-S0 candidate may be built
   merely to gather ambiguous status.
2. 104 decides whether interrupt-mask ownership must change at all. It prefers
   no mask write and forbids W1C clear.
3. 105 builds the HPM-only forward+inverse host transition; proposed 106 runs
   that boundary without PHY or Linux.
4. 107 builds the exact eUSB2/ATC/DART/xHCI no-root candidate; proposed 108
   requires a stable child but performs no block read.
5. Proposed 109 identifies and reads fixed block sectors only.
6. 110 prepares exact M1 removable-disk identity and destructive guards;
   proposed 111 flashes image `1c493fad...` only under a separate erase
   confirmation and full readback.
7. Proposed 112 boots tethered from the right stick and performs one bounded,
   fsynced persistence write; proposed 113 performs the separate untethered
   external-root cold boot after B0 ticket 101.

Tickets 097 and 099 remain non-runnable historical umbrellas. Their old plan
approval does not approve these child artifacts or the destructive flash.

**Internal NVMe remains offline-only:** 114 refreshes public SPTM work, 115
builds a host-only service-6 contract harness, 116 audits guarded-domain
handoff, and 117 creates a live candidate only if primary evidence proves a
side-effect-free supported query. Otherwise it records NO-GO. Never retry the
known-failing raw BAR read or unchanged GENTER. Ticket 118 closed the
post-SSPS recovery control; ticket 119 completed the conditional dual-mode B0
object review.

Ticket 022's 2026-07-23 refresh also confirms that native DCP is not a B0
dependency. Its J614s DT topology is inventoried, but the macOS 26.x ABI, extra
display MMIO bank, paired ASC IRQ layout, DART SID/register-bank delta, and
display-domain ownership transition remain unresolved. Keep simpledrm/fbcon
for B0; exact evidence:
`done/2026-07-23-t6040-dcp-upstream-dt-prep.md`.

Ticket 037's per-driver RTKit compatibility audit is complete with an
intentional empty patch set. The shared RTKit core already accepts J614s's live
protocol; DCP 26.x, ISP H16, and GPU G16 are real ABI/hardware ports rather than
whitelist additions, while SMC and SIO have no OS-firmware whitelist to extend.
The DCP/ISP upstream test notes and forbidden speculative aliases are recorded
in `done/2026-07-23-t6040-rtkit-26x-draft-audit.md`.

Ticket 048's remote-loop host-tool preparation is complete. Signed mail drafts
now isolate generic m1n1 proxyclient PTY support and macvdmtool's ACE3
`actions`/`vdm`/`dven`/`localserial` commands; both reproduce their clean branch
trees through `git am`, and the PTY byte-preservation/build tests pass. kisd's
T6040 `0x548700000` auto-detection is already upstream, so there is no kisd
patch. CJ posts, if desired. Exact branches and hashes:
`done/2026-07-24-t6040-host-tools-upstream-prep.md`.

Ticket 039's G16 mule preparation is also complete, with no live candidate.
Current Linux ends at T6022/G14, Mesa has no explicit G16 path, m1n1 has no
T6040 GPU handoff, and the official T604x GPU state remains TBA. The exact
J614s ADT/25F84 firmware packet and a staged upstream-requested test/report
contract are ready; never substitute a G14 alias. Keep B0 on simpledrm/fbcon.
See `done/2026-07-24-t6040-gpu-upstream-test-prep.md` and
`docs/t6040-gpu-upstream-smoke.md`.

Ticket 027's suspend analysis is complete with no live proposal. SMC is a
wake-event source, not the s2idle entry mechanism; current residency depends
on `cpuidle-apple`, which excludes T6040 and uses locked CYC_OVRD plus WFI.
Keep `idle=nop`. A reviewed M4 retention contract and separate bounded cpuidle
and SMC-wake tests must pass before RAM-root s2idle. Details:
`done/2026-07-24-t6040-suspend-feasibility.md`.

Ticket 051's guarded-side NVMe argument decode is complete. All nine handlers
now have byte-proven input registers, including the formerly unverified
ASQ/ACQ op-4 contract and the corrected op-0–3 init/TCB/configure split. This
Ticket 052 then reproduced the map on the exact T6041 SPTM payload: argument
contracts are unchanged, numeric offsets moved, and T6041 adds segment-count
and NLB validation. This does not create a callable SPTM path: outer IOMMU
dispatch and domain provenance remain ticket 055 work. Exact results:
`done/2026-07-23-t6040-sptm-nvme-op-args.md` and
`done/2026-07-23-t6041-sptm-exact-blob.md`.
Ticket 054's three-SoC structural diff further confirms that dispatch ids,
op ordering, arguments, and SART/NVMe ownership are stable across T8132,
T8140, and T6041, while text/register offsets are strictly variant-specific:
`done/2026-07-23-sptm-three-soc-structural-diff.md`.
Ticket 055's XNU-shim feasibility checkpoint and draft escalation are complete.
The remaining blockers are no longer raw-m1n1 experiments: they are a
permissive-kernelcache signing path, SPTM caller-domain survival, and
CoastGuard/SART/SEP controller-state survival across the pivot. The live call
stub remains disabled:
`done/2026-07-23-t6040-sptm-xnushim-feasibility.md`.

Ticket 046's m1n1 series shaping is complete. Current upstream
`7c7716b6` already added initial T6041 identity and T6040's moved PCIe reset
bit, so the final RFC avoids those duplicates and reduces the 22-commit
bring-up history to nine review patches. The final PCIe patch adds only the
live-proven J614s clock/gate prefix and stops before unresolved operation 115.
The series applies with identical tree hashes and builds reproducibly twice;
it has not been posted or run. Audit and mail:
`done/2026-07-23-t6040-m1n1-upstream-series.md` and
`patches/m1n1-t6040-upstream-v1/`.

Ticket 047's Linux DT consolidation is also complete. The final J614s identity
and measured DCUART IRQ 816 edits are committed in `wallace/t6040-bringup`.
The four-patch RFC draft excludes experimental USB/ANS nodes, applies with an
identical tree, builds all three board DTBs, and passes strict checkpatch.
`dtbs_check` now isolates the remaining AIC/watchdog/ASC/DockChannel binding
prerequisites. Audit and mail:
`done/2026-07-23-t6040-linux-dt-series.md` and
`patches/linux-t6040-j614s-dt-v1/`.

Keep the first USB smoke at `maxcpus=1 idle=nop`. The DT's extra `cpu@10105` is
correctly disabled and 14 cores are available, but Linux secondary-core bring-up
is still a separate staged experiment. Ticket 005 reached kernel vectoring but
gave no Linux output. Offline 122 is now done: its exact storage-disabled,
non-blocking early-DockChannel replacement passed independent review. Ticket
123 still needs fresh maintainer approval because it was created after the
last approve-all; it must pass before 120 prepares or 121 proves all 14 cores.
Do not combine any of those with a USB-host test; cpufreq ticket 006 follows
121.

**Upstream correction, 2026-07-21:** a bounded m1n1 experiment on M4 Pro
measured DockChannel-UART on AIC input **816**; the ADT's 360 is wrong. The
standard USB-smoke DT uses `apple,poll-mode`, so this does not change its console
behavior, but all newly built DTBs must carry 816. Yuka's WIP `more-t6041`
branch also reached a shell on M4 Pro with all cores and PMGR, providing strong
family-level SMP evidence. It is not a J614s-ready artifact (its inherited CPU
topology and memory-channel domains do not match this 14-core board), so
completed 122 → freshly approved 123 → 120 → 121 is now the J614s proof
sequence and USB smokes stay single-core.
Full 11–21 July log
review: `done/2026-07-21-asahi-dev-log-review.md`.

## 0. Retire IRQ-360 diagnostics; evaluate the direct IRQ-816 driver offline

The 2026-07-14 diagnostics below are retained as experiment history. They used
the ADT-provided input 360, now known not to be the UART interrupt. Their direct
FIFO observations remain valid, but they cannot establish whether the real AIC
input 816 works or fails. Do not run ticket 059 or any other 360-based image.
The direct `apple,dockchannel-uart` driver from `more-t6041` was audited and
adapted to the measured J614s DT under completed ticket 062 (data register
first, `earlycon=dockchannel,mmio32,0x50882c000`, `ttyDC0`). Plan-approved
ticket 073 has now passed: the non-polling shell received and executed two
host command batches and reported 652 DockChannel mailbox interrupts with
zero errors. Poll mode remains the conservative fallback.

The storm-bounded UART TX/RX BIT(2)/BIT(1) diagnostic ran once on 2026-07-14.
Linux reached BusyBox and TX worked, but neither an LF-terminated nor a
CR-terminated host command was echoed or answered. The image was not retried;
DebugUSB recovery restored a fresh proxy. Full hashes and result:
`done/2026-07-14-t6040-dockchannel-irq-retest.md`.

This does not rehabilitate the old "dead IRQ across all 4096 AIC inputs"
claim: that scan still enabled the FIFO with MTP's wrong RX BIT(3), while the
corrected run could not use RX to retrieve `/proc/interrupts`. A TX-only,
self-reporting initramfs then ran once. It printed its instruction banner, took
the approved probe line during the TX-silent interval, and never emitted its
post-window report. The BusyBox timeout path works in an arm64 PTY test, so the
timing strongly suggests the RX event stalled the shared IRQ-driven TX
completion path or tripped the guard. Exact result:
`done/2026-07-14-t6040-dockchannel-irq-tx-report.md`.

The replacement diagnostic ran once on 2026-07-14 (rig ticket 001, reviewed
and approved; result:
`done/2026-07-14-t6040-dockchannel-rxirq-txpoll-result.md`). It left RX
interrupt-driven on BIT(1), never unmasked TX BIT(2), and relayed ten
per-second telemetry samples flawlessly over polled TX. The outcome is the
pre-registered matrix's third row exactly: after the single approved
`IRQ_BIT1_PROBE` injection, the handler never entered (`total=0`), the raw
local `IRQ_FLAG` stayed 0, `DATA_RX_COUNT` stayed 0 at every sample, the
joined `/proc/interrupts` row (`virq=42`, AIC2 hwirq `65896`) stayed at zero,
and userspace received nothing. **The injected bytes never entered the AP-side
FIFO, so AIC delivery was never exercised**; investigate mask-write or
pre-handoff perturbation, not AIC delivery. Neither storm cap triggered.

One pre-run claim is corrected: the AIC driver encodes IRQ hwirqs as
`((die + 1) << 16) | input`, so die-0 input 360 displays as hwirq 65896
(`0x10168`), not 360; the telemetry's explicit virq→hwirq join is what made
the zero count interpretable.

The sharpest open question is a build delta: the earlier TX-only reporter
received the probe once in an IRQ-mode build, while this build saw no byte
arrive at all. Offline ticket 049 (`rx-path-delta-analysis`) scopes that:
diff the probe/startup IRQ-block writes and RX_THRESH timing between the two
builds and analyze the dock-side KIS agent's flow-control interaction with
AP-side IRQ_MASK state.

The ACK/read-order audit is also pre-run evidence. Safe m1n1 commit `eed11760`
only accesses the UART data FIFO and never touches its IRQ mask/flag block, so
it cannot leave BIT(3) set before handoff. The older working DockChannel/HID
stack uses RX BIT(1), W1C-acks the child IRQ in its irqchip, masks RX in its
hard handler, and only afterward reaches its threaded/data-consumption path.
The current mailbox driver instead W1C-acks RX and wakes its thread while RX
remains unmasked. Thus the diagnostic preserves its existing W1C semantics and
tests whether reassertion stops when RX is masked; it does not assume that
drain-first is required.

Pre-registered interpretation matrix — **filled 2026-07-14: row 3 matched**
(the other rows are retained for reference; none of their conditions
occurred):

| Cap/flag | Post-mask result | FIFO movement | Pre-registered conclusion |
|---|---|---|---|
| no cap; `total=0`; current `rx_count>0`, raw `irq_flag&2` | no `/proc/interrupts` delta on the telemetry-mapped virq | bytes present | historical only: would have tested ADT input 360, now known not to be the UART route |
| no cap; small RX count | stabilizes below 1,000 | FIFO drains and probe is delivered | corrected RX IRQ works; old dead-IRQ claim is withdrawn |
| **no cap; no RX count/flag** ✅ | **no delta** ✅ | **FIFO remains zero after injection** ✅ | **bytes did not reach this build; investigate mask-write or pre-handoff perturbation, not AIC delivery** |
| cap at RX 1,000 with `cap_flag&2`; `hard=0` | `post_cap` stabilizes near zero and `cap_mask=0` | either | RX-data-triggered storm is real, but local masking stops it; repair completion/ACK handling |
| cap at RX 1,000; hard-disable at total 1,024 | `post_cap=24`, `hard=1`, flag remains asserted | `hard_fifo > cap_fifo` | bytes continued arriving during the masked storm; sticky source remains coupled to FIFO data flow |
| cap at RX 1,000; hard-disable at total 1,024 | `post_cap=24`, `hard=1`, flag remains asserted | `hard_fifo == cap_fifo` | storm is decoupled from new data after masking; reproduce sticky/reasserted BIT(1) and audit flag semantics |

Exact hashes, MMIO delta, audit, and both the artifact record and the run
result are in `done/2026-07-14-t6040-dockchannel-rxirq-txpoll.md` and
`done/2026-07-14-t6040-dockchannel-rxirq-txpoll-result.md`.

Keep the standard 5 ms full-poll mode for current boot artifacts. Do not retry
any completed BIT(1)/IRQ-360 image, and do not publish the old scan as a
hardware erratum: it targeted the wrong AIC input and, in the last run, no byte
reached the FIFO.

Ticket 049 is done (`done/2026-07-14-t6040-dockchannel-rx-path-delta.md`): the
static delta audit rules out direct software flow-control coupling and shows RX
setup itself did not change between the builds. Its proposed ticket-059 timing
follow-up is superseded by the measured IRQ-816 correction; ticket 059 is closed
and must not be revived unchanged.

The IRQ-816 correction comes from the #asahi-dev logs, not our rig: yuka's
measurement experiment and enverbalalic's reproduction on real T6041 hardware
both show the ADT's dockchannel-uart input 360 is an Apple copy-paste error and
the real AIC input is **816** on t6040/t6041 (full trawl:
`done/2026-07-21-asahi-dev-irc-review.md`). Our `total=0` RX result is consistent
with having listened on input 360. Ticket 062 completed the IRQ-816 path:
the DT uses input 816, the data reg (`0x50882c000`) comes first for earlycon,
and RX/TX bits are a DT property. Ticket 073 live-proved the path; exact result:
`done/2026-07-24-t6040-dockchannel-irq816-result.md`.

## 0.1 Extend the proven T6040 PCIe path through PHY setup

The former register-map blocker is solved. Static analysis of the paired macOS
kernelcache proves the two new T6040 groups target ADT reg[5] (CIO3 PLL at
`0x415046200`) and reg[6] (PCIe clkgen at `0x415044000`). m1n1 main
`eb23c423` / curated `da1791a0` apply them and then run the reused T6031/T8122
sequence. The separate `t6040-j614s-dcuart-pcie` kernel DT builds cleanly and
describes BCM4388 WiFi/BT on port 0 plus the GL9755 SD reader on port 1.

The initial approved diagnostics ran on 2026-07-14. The first completed all 77
AXI tunables and stopped after `pcie: No common tunables`. The traced retry on
main `81da3522` delivered the real failure earlier: AXI tunable `[70]`, manifest
operation 90 in that build, printed `done`; before `[71]` was announced, m1n1
took an asynchronous SError (`L2C_ERR_STS=0x82`) in the proxy `P_CALL`
trampoline and rebooted. Because the fault is asynchronous, `[70]` is only the
delivery boundary, not proof of the causal write. The sanctioned DebugUSB
recovery restored a stable proxy. Linux never handed off, no PHY/port/PERST
operation ran, and no storage was accessed. Exact trace:
`logs/t6040-console-20260714-pcie-axi-trace.log` (SHA-256
`41774ef8866e775de30ca2c98957d167085943163fe24d25c7aaca29eb177860`).

Offline disassembly then exposed a real ordering difference. J614s has eight
PCIe `clock-gates`; `ApplePCIEBaseT8132::_enableRootComplex()` enables gates
0–6, applies AXI then CIO3 and clkgen tunables, and only afterward enables gate
7 (`APCIE_PHY_SW`). m1n1 previously enabled all eight before AXI. Main
`6efe2d45` and curated `954fd4cf` reproduce Apple's staging and retain the
diagnostic return before the first PHY register access.

The separately approved staged run used main binary SHA-256
`c2a5b7e27bb8d56479f46d6b485a195d2eb1cd64a3b86fbe3c90db1f00424735`
and the exact 105-operation subset in
`done/2026-07-14-t6040-pcie-clock-diagnostic.tsv` (SHA-256
`ce86e51aa3d278da1d9ef9eb35fca3208859f4993480de5b6af3268dc03ef4e6`).
It produced the same result: AXI `[70]` at `0x4160013fc` printed `done`, then an
asynchronous SError arrived before `[71]`, with `L2C_ERR_STS=0x82`. It never
reached CIO3, clkgen, the late gate, PHY, ports, Linux, or storage. Therefore
early `APCIE_PHY_SW` enable was not the cause. Exact transcript:
`logs/t6040-console-20260714-pcie-staged-gate.log` (SHA-256
`c31275546280b9df2dbf9b014d2e6411cfb708f87f1c803e10b11e2cdb95ec2f`).
DebugUSB recovery restored a fresh, quiescent proxy.

The no-new-address follow-up ran at m1n1 main `00760c79`
(`v1.6.0-68-g88ce1ee3`), binary SHA-256
`2997b07647007f99df6ad094a2da55d66a9f7accd6758bb134d3fa92b76d0c72`.
It placed `dsb sy` and a read-only `L2C_ERR_STS` sample before the first and
after every existing traced RMW, aborting on a nonzero result without clearing
status. AXI `[70]` again printed `done`, proving its barrier completed and its
status sample was zero; the same SError then arrived before `[71]`. Thus the
status becomes visible only with the delayed exception and cannot attribute an
individual write this way. Transcript:
`logs/t6040-console-20260714-pcie-barrier.log` (SHA-256
`cebc058921b62b2f594855bb65db28b312570b6c707f5a29a29480c31c04667b`).
Recovery restored a fresh quiescent proxy. Full result:
`done/2026-07-14-t6040-pcie-barrier-diagnostic.md`.

The zero-PCIe-write trace-volume control ran at main `3e772779`
(`v1.6.0-72-g3e772779`), binary SHA-256
`c9296b8d1ca146a32c7a1ba1bf17b7091281588ab90d16a69f0718c5a8fa04ea`.
It enumerates the same ADT AXI entries and prints the identical 77 pre/`done`
pairs, but returns before enabling any PCIe clock or reading/writing controller
MMIO. It nevertheless produced the same SError after `[70] done`. This proves
that the traced SError is entirely a console/log artifact, not a PCIe access.
Transcript: `logs/t6040-console-20260714-pcie-trace-dry-run.log`, SHA-256
`52431e2a9a7d87642fde917419f3e8e666672434953cad23466c13b61968742d`.

The exact mechanism was bounded offline. The 16 KiB m1n1 log buffer was
`0x105ce7a4000..0x105ce7a8000`, ending exactly at the top of normal RAM; every
SError reports that exclusive end in `L2C_ERR_ADR`. When the log device becomes
writable, `iodev_console_write()` first flushes its retained 8 KiB console
backlog. The identical post-allocation stream contributes another 9,274 bytes:
the ring crosses its end during `[61] done`, then the asynchronous error is
delivered 1,082 bytes later after `[70] done`. The zero-PCIe-write upper-guard
control ran at main `eed11760` (`v1.6.0-75-ga61fd099`), binary SHA-256
`1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b`.
It keeps the active 16 KiB ring one unused 16 KiB page below top-of-RAM and
repeated the identical dry-run trace. All 77 entries and the completion marker
printed without SError, and the base kernel reached its BusyBox shell. This
live-proves the upper guard and fully exonerates the PCIe sequence from the
traced `[70]` failure. Exact m1n1 transcript:
`logs/t6040-console-20260714-logbuf-upper-guard.log` (SHA-256
`2e8624d795bc6bddab24b932a530bf7f992f35732402ed041bfc308857260d63`).
Full result: `done/2026-07-14-t6040-logbuf-upper-guard-control.md`.

The Apple-ordered 105-operation path was restored at main `f46d6e35`
(`v1.6.0-78-gf46d6e35`), binary SHA-256
`8fd7319047187f9ca05a6924462a4f24360fcc1d9e4279b089dc83a5acb05744`.
It retains the proven upper guard, per-RMW barriers/status samples, exact
manifest SHA-256
`ce86e51aa3d278da1d9ef9eb35fca3208859f4993480de5b6af3268dc03ef4e6`,
Apple clock-gate order, and hard return before operation 106, the first PHY
write. The approved run completed all 105 operations: all 77 AXI entries, the
RC write, all seven CIO3 PLL entries, the PCIe clkgen entry, and the late
`APCIE_PHY_SW` gate. It then took the intentional stop before PHY, handed off
the PCIe-free base DT, and reached BusyBox with no nonzero L2 status or SError.
Exact transcripts and hashes are in
`done/2026-07-14-t6040-pcie-guarded-clock-diagnostic.md`.

The exact shared-PHY continuation ran at m1n1
main `85b01036` (`v1.6.0-81-gb5ced9ba`), binary SHA-256
`add3cef43947dab1605bd95ad602b6dcbf8e89de0a3f1b43f278005cd52dd9da`.
It completed operations 1–114, including all five controller PHY tunables,
reference-clock availability, both clock acknowledgements, reset release, and
T8122 pre-tunable control. It then stopped after printing the pre-line for
operation 115, the first PHY-IP PLL RMW at `0x417040090`; no `done` or exception
followed. Linux did not hand off and no port or storage access ran. The
351-operation manifest SHA-256 is
`d4496968ee8fc1202bd4d47247fc6bbaa36f0a3f7cc872a81efabe72327c50fc`.
Exact result and transcript:
`done/2026-07-14-t6040-pcie-phy-diagnostic.md`.

The reviewed read-only isolation then ran once at main `dc7124fb`, binary
SHA-256
`5616b05fdd21a35990102ce8b711920ec8c442f75c89ce6cfe27da2f24adef67`.
Operations 1-114 again completed. The pre-read marker for the ADT-derived
32-bit access at `0x417040090` printed, but no value/completion, L2C status, or
exception followed. Thus operation 115 stalls on its read side; the earlier
combined RMW cannot implicate its write half. No operation-115 write, later PHY
entry, port, Linux PCIe, NVMe, or storage access ran. DebugUSB recovery restored
a quiescent proxy. Exact review, artifacts, result, and transcript:
`done/2026-07-14-t6040-pcie-op115-cross-review.md` and
`done/2026-07-14-t6040-pcie-op115-read-result.md`.

Do not try a write-only operation 115 or move the later PHY-clock poll ahead of
the tunables without new static evidence. Continue offline route-finding for
the missing PHY-IP aperture precondition/Apple transition, then require a new
manifest, cross-review, and explicit approval for any changed live sequence.

Ticket 068 then tested the exact paired-driver clkgen-PLL sequence. The PLL
locked, gate/PHY clock acknowledgements completed, but output stopped again on
the pre-read marker for `0x417040090`; no value returned. Thus clkgen lock is
necessary-looking but insufficient. Ticket 124 resumes static tracing; never
retry 068 unchanged. Exact result:
`done/2026-07-24-t6040-pcie-op115-clkgen-pll-result.md`.

## 1. Rebuild the J614s trackpad motion retest, then obtain fresh approval
`event0` is Apple DockChannel Multi-touch and `event1` is the keyboard. The
transport's missing firmware loader and stuck-start error path are fixed and
live-tested in kernel build #12: repeated opens now independently request
`apple/tpmtfw-j614s.bin` and return `-ENOENT`, with no invalid resets or stale
`-EINPROGRESS`. Ticket 016 reproducibly extracted the exact 25F84 J614s
payload and staged `tpmtfw-j614s.bin` at SHA-256 `a1f4131d...`; extraction and
integration evidence is
`done/2026-07-23-t6040-trackpad-firmware-provision.md`.

The exact ticket-004 candidate was built twice and pinned: Image
`86e031db...`, unchanged storage-disabled DTB `2782b922...`, paired-firmware
initramfs `3a47c95d...`, and PCIe-write-free m1n1 `1394c345...`. Its TX-only
init automatically inventories input and captures at most 12 seconds/32
records per event, so it does not depend on ttydc0 RX. Independent review
retired those bytes unrun: the Image omitted the already-proven `hid->type`
fix and left `HID_MULTITOUCH=m` while the initramfs carries no modules, so no
multi-touch event node could bind or invoke the runtime firmware path.

Offline ticket 125 is complete: `HID_TYPE_FIX=1`, `TRACKPAD_MOTION=1`, and
built-in multitouch produced two byte-identical Images at `446eeb2e...`; the
new independent exact-artifact review passed. Proposed live ticket 126 was
created after the approve-all and is not approved. Before it can run, the maintainer must
also record a narrow exception to the unqualified firmware-write rule for the
exact paired `a1f4131d...` non-persistent HIDF upload into volatile coherent
DMA. That exception does not permit flash/NVM, another blob, or GPIO/PMU reset.
Original preflight and review:
`done/2026-07-24-t6040-trackpad-motion-preflight.md` and
`done/2026-07-24-t6040-trackpad-motion-crossreview.md`. Corrected manifest and
review:
`done/2026-07-24-t6040-trackpad-motion-revised-preflight.md`.

If MTP requests its reset GPIO, stop:
the derived `gp1c` function resolves through the ADT's `smc-pmu` node, and PMU
writes are forbidden by the project rules.
No tactile click is expected yet (the haptic actuator is a separate interface).
Full finding:
`done/2026-07-12-t6040-trackpad-firmware.md`.

## 2. Review and upstream the proven T6041 PMGR quirk
The full 214-domain topology now boots to BusyBox **3/3** with the exact minimal
temporary policy: preserve firmware-active domains, disable only `disp_cpu`,
and skip auto-enable only on `dispext0_cpu` and `dispext1_cpu`. Both CPU skips
are individually necessary at bank granularity; the `sys`, `fe`, and five old
ANE exclusions are unnecessary. Legacy raw fails 3/3. Full matrix and hashes:
`done/2026-07-12-t6040-pmgr-matrix.md`.

The supported shape is now implemented and live-tested in build #14. The
two-patch draft starts with `patches/t6040-pmgr-t6041-bindings.patch`, then
`patches/t6040-pmgr-t6041-quirks.patch` selects preserve-active and the two CPU
auto-enable exceptions from `apple,t6041-pmgr-pwrstate`; Linux `37339d595765`
removes the experiment-only properties from the standard DT. The series passes
checkpatch and both binding schemas validate. No further policy bisection is
needed.

The 2026-07-24 active/inactive reconciliation also found no topology over-count
on the exact live J614s ADT. AMCC/DCS 16–31 carry flag `0x19` versus `0x09`
for 0–15, and every dispext2/3 record carries `0x10/0x12`; `0x10` is the
existing `no_ps` bit. The generated DT therefore already excludes all of them.
Do not invent another encoding bit or remove the preserve-active quirk: its
3/3 result concerns real domains and remains independently necessary. Exact
table and draft question for yuka:
`done/2026-07-24-t6040-pmgr-active-encoding.md`.

Next, in leverage order:
1. Ask flokli for the J773s PMGR policy (draft only here; maintainer sends).
2. If pre-userspace attribution becomes necessary, first add a bounded
   polled/atomic TX primitive to the DockChannel mailbox. Do not register the
   current `ttydc` kfifo/workqueue path as a printk console: it is not safe in
   atomic or panic context and can recurse through its own error printk.

Done this session: raw determinism, requested core-infra and PMGR1 isolations,
live ADT regeneration, `no_ps` parent filtering, and safe always-on generation
(no policy by default; explicit legacy flag only).

## 3. Solve protected T8140 NVMe queue ownership

The power and coprocessor side is now proven. Linux forces the three gated PCIe
parents actual-on, activates the CoastGuard SART, allocates RTKit buffers,
boots ANS, and reads `APPLE_ANS_BOOT_STATUS_OK`. The remaining failure is not a
DT, PMGR, SART, or RTKit problem.

T8140 protects both the legacy linear-queue/NVMMU setup and the standard NVMe
queue registers. Main-BAR reads/writes at `MAX_PEND`/AQA fault; the secure BAR
at CPU PA `0x44dcc0000` is readable and contains iBoot's disabled-controller
admin queue state. Static analysis of the paired macOS kernel and
IONVMeFamily resolved the real interface: Apple calls `_pmap_iommu_ioctl`,
whose NVMe backend enters SPTM with service 6 operations 0–8 for controller
initialization, TCB authorization, admin/I/O queue registration, and queue
activation.

The exact service-6 operation 0 + operation 4 sequence was implemented in
`patches/t6040-nvme-sptm-debug.patch` and tried once. Raw m1n1 reports
`SPRR_CONFIG_EL1=0` and `GXF_CONFIG_EL1=0`; Linux reached
`before protected admin queue setup`, then hung at Apple GENTER
(`.inst 0x00201420`). No SPTM call returned. The watchdog recovered to m1n1.
Do not repeat that call unchanged, and do not resume direct main- or secure-BAR
writes.

The preservation question now has a structural answer: iBoot's secure ASQ/ACQ
buffers (`0x101005db000` / `0x101005dc000`) live in ordinary RAM that m1n1 does
not reserve, and the macOS path performs service-6 TCB authorization for each
command. Preserving only those queues cannot provide a complete Linux NVMe
path. Keep further work static: determine whether raw boot can acquire the
required protected execution state through a documented loader transition or
whether storage must wait for upstream M4 SPTM support. No Identify command has
run; never mount, repair, format, flush, or write the namespace.

The service-6 ABI is now fully decoded from the paired M4 target kernelcache
(Darwin 25.5.0, RELEASE_ARM64_T6041; ticket 007,
`done/2026-07-14-t6040-sptm-service6-abi.md`). Selector `x16 = op | (service<<32)`,
read directly off the kernel's per-(service,op) GENTER veneer table; service 6 =
NVMe with exactly 9 veneers, ops 0..8 (0 = init, 1 = TCB auth, 4 = admin queue
setup with the ASQ/SQ-depth/ACQ/CQ-depth arg layout already reproduced; the
enable/query ops map to the named `AppleANS2CGv2Controller` methods). The decode
confirms the blocker is **not** ABI knowledge: each veneer's shared guard-enter
helper bumps a per-thread reentrancy counter and spins on `mrs s3_6_c15_c8_0`
before GENTER, requiring a live GXF gate. Raw m1n1 boots with `GXF_CONFIG_EL1=0`
and an unconfigured GENTER entry vector, so GENTER wedges (no dispatch, no
fault). The remaining question — whether raw boot can enter SPTM guarded state
at all, or storage waits for upstream — is ticket 008's go/no-go.

Ticket 008 go/no-go is now written (`done/2026-07-14-t6040-nvme-sptm-route-finding.md`):
**internal NVMe under raw boot is NO-GO near-term.** M4 HW advertises GXF
(`AIDR_EL1` bit 16), but m1n1 leaves it off (`features_m4` omits `mmu_sprr`), and
even enabling m1n1's M1/M2-style GXF only yields m1n1-owned guarded code, not
Apple's signed SPTM — which is what the controller's TCB/SART/queue mediation is
anchored to. There is no documented loader transition for a third-party boot
object to acquire genuine SPTM state; that becomes the #asahi-dev question
(ticket 010). Daily-driver storage goes through USB-attached root (tickets
009/031/032), which never touches the SPTM-gated internal controller. Do not
spend rig time forcing service-6 GENTER from raw boot.

Exact current transcript: `logs/t6040-console-20260714-nvme-sptm.log`.
Full cumulative analysis: `done/2026-07-13-t6040-nvme-map.md`;
SPTM/GENTER ABI: `done/2026-07-14-t6040-sptm-service6-abi.md`.

## Storage investigation history (superseded by #3 above)
The maintainer approved the exact CoastGuard writes. The retry established two
separate boundaries:

1. A handshake-only SART probe still reset, while a zero-MMIO SART probe booted.
   `patches/t8140-sart-defer-scan.patch` now defers the protected-entry scan
   until the first client has the complete ANS power context. With that fix,
   both the SART-only DT and the full DT with `nvme-apple` unloaded reached
   BusyBox.
2. Loading `nvme-core.ko` succeeded. Loading `nvme-apple.ko` reset the target.
   Yielding phase checkpoints made the exact last successful point
   `before ANS CPU control read`; the fatal operation is the first read of
   `0x209600044`, before any CoastGuard write, SART entry access, or namespace
   command.

Read-only ADT-derived PMGR inspection found that firmware leaves `ANS` at
`0x0f0000ff`: target and actual state `0xf`, with AUTO_ENABLE clear. Linux's
T6041 PMGR probe otherwise enables automatic gating before the NVMe module's
first access. `patches/t6040-pmgr-ans-no-auto.patch` adds an NVMe-only build
exception, and `dts/t6040-j614s-dcuart-nvme-ans-hold.dts` independently selects
the same existing bring-up policy. Both compile; the hypothesis is not yet
live-verified. The last diagnostic reached BusyBox, but its log relay replayed
historical PMGR output and the m1n1 proxy then remained unresponsive after the
documented kisd/re-entry recovery. Stop live work until DebugUSB is healthy.

The recovery helper now makes the fresh kisd PTY raw and attaches its own
reader before DebugUSB traffic. A later recovery confirmed the complete m1n1
startup packet, but proxyclient then timed out while 3.2 KiB of historical
Linux output remained queued. The next reboot stopped after iBoot Stage2, and
then fell through to Apple's "macOS on the selected disk needs to be
reinstalled" screen instead of launching m1n1. The following DebugUSB VDM
failed; live work stopped with kisd detached. This proves only that Apple's
boot chain identified the selected system volume, not that Linux NVMe ran.

Run the recovery helper; it now requires a healthy `Running proxy` and three
unchanged console-size samples before returning. Then boot only the prepared
trace set and relay new `trace:` lines, not the historical PMGR backlog:

- `Image-sart-trace`:
  `0c4880522c4793629f6e9a25ea164c911801e67754ae43cd3a6b5b274e20e8e6`;
- `t6040-j614s-dcuart-nvme-ans-hold.dtb`:
  `cc2c48e30a09080117222d5f4c9fb795dfd6bb338d2cf26b23085ad947ffbefb`;
- `initramfs-dcuart-nvme-ans-hold.cpio.gz`:
  `ae80f82033e5f0d683ac09a3fa61e67c3c63e8a7c1be7593a0fd7fe687732873`.

The exact set was finally booted as Linux #24. `nvme-core.ko` returned zero;
`nvme-apple.ko` watchdog-reset the target. That boot did not have a kmsg relay,
so the absence of trace messages on ttydc does **not** move the fatal boundary
earlier than the prior `before ANS CPU control read` result. For the next
single retry, use the newly built trace-relay initramfs below and add
`EXTRA_BOOTARGS=t6040.trace_relay=1`; it relays only current-boot `trace:` lines
before the shell command is run.

- `initramfs-dcuart-nvme-ans-hold-trace.cpio.gz`:
  `8942b1bd009cd9fe0adeadea3de60d6f068120ae2b8327e0ae1df2c852f40ea5`.

Use the same Image and DTB hashes above. For agent-driven helpers, set
`T6040_KEEPALIVE=1` so kisd and the tty reader survive the automation shell.

That corrected retry is now complete. Its current-boot trace was identical to
the original through `reset work entered`, then stopped at
`before ANS CPU control read`. Therefore preserving ANS firmware state and
skipping AUTO_ENABLE did **not** move the boundary; the ANS auto-gating
hypothesis is disproven. Do not repeat this NVMe module load unchanged.

Next, boot the same trace-relay set but do not load either NVMe module. Capture
the software genpd state first (DEBUG_FS is enabled):

```sh
mount -t debugfs debugfs /sys/kernel/debug
cat /sys/kernel/debug/pm_genpd/pm_genpd_summary \
  | grep -E 'ans|apcie|fab3'
for d in ans apcie_sys_st0 apcie_sys_st1 apcie_phy_sw; do
    echo "--- $d"
    cat "/sys/kernel/debug/pm_genpd/$d/current_state"
done
```

This is read-only software-state attribution. Use it to decide whether a
separately reviewed raw PMGR-state trace is warranted; do not perform another
ANS MMIO read merely to reproduce the same SError.

Captured: the summary and per-domain files report `on` for `ans`,
`apcie_sys_st0`, `apcie_sys_st1`, and `apcie_phy_sw`; the filtered summary also
shows `fab3_soc`, `apcie_st0`, `apcie_st1`, and `apcie_gp` on. Linux therefore
does not believe the storage power chain is off.

The bounded raw-state diagnostic is now built and host-verified.
`patches/t6040-nvme-pmgr-snapshot-debug.patch` is selected only by the boolean
`apple,pmgr-snapshot-stop` in
`dts/t6040-j614s-dcuart-nvme-pmgr-snapshot.dts`. After normal allocation has
attached the declared genpd chain, it follows only those existing DT
`power-domains` phandles, reads each provider's declared scalar `reg` through
its parent PMGR syscon, and returns before `nvme_add_ctrl()`. Reset work cannot
queue, so no ANS, CoastGuard, SART-entry, mailbox, NVMe register, or storage
command is reached. Its diagnostic exit intentionally retains the genpd links
until reboot instead of requesting a cleanup power transition. Do not unload
the diagnostic module; reboot after collecting the trace.

Prepared artifacts:

- `Image-nvme-pmgr-snapshot`:
  `1a056fd855f2d56508e90dc5b9a789d8dc6dcaaf8f7b2284b759756213056541`;
- `t6040-j614s-dcuart-nvme-pmgr-snapshot.dtb`:
  `396d6ad1318764658728b4eb0b67a3961965428031e0aa52b2b59515633a977a`;
- `initramfs-dcuart-nvme-pmgr-snapshot.cpio.gz`:
  `7d44ee376cca2ca0caf44a713b329319b39e502dd29efa41f0b37f1e856be94c`;
- `nvme-core-pmgr-snapshot.ko`:
  `5e61ba16697daa382c5bb614fdaf3d5948a3818c11a630d5766e3b88ead36af7`;
- `nvme-apple-pmgr-snapshot.ko`:
  `21f00d39ad4f8f86df03c403d8d683addc6e4a65c2a8b204e2f7a57adac611f4`.

The single snapshot attempt is complete. Linux #25 reached BusyBox,
`nvme-core.ko` returned zero, and the diagnostic Apple module printed its full
snapshot plus `stopping before ANS MMIO`. The shell then answered two liveness
markers. The four storage values exactly match the earlier m1n1 snapshot:

```text
ans            raw 0x0f0000ff  target f  actual f  auto 0
apcie_phy_sw   raw 0x1400024f  target f  actual 4  auto 1
apcie_sys_st0  raw 0x1000030f  target f  actual 0  auto 1
apcie_sys_st1  raw 0x1000030f  target f  actual 0  auto 1
```

The genpd summary's `on` result was logically correct but incomplete:
`apple_pmgr_ps_is_active()` treats target-active plus AUTO_ENABLE as on even
when the actual state is clock-gated (`4`) or power-gated (`0`). Thus ANS itself
is fully active, while NVMe's other direct domain, `apcie_phy_sw`, is
clock-gated and both of that domain's `apcie_sys_st*` parents are power-gated
immediately before the fatal read.
This is the first evidence-backed new hypothesis since ANS auto-gating was
disproved.

The second diagnostic is now built and host-verified. The runtime-PM put/get
idea cannot work here because the T6041 preservation quirk marks every
firmware-active domain `GENPD_FLAG_ALWAYS_ON`; genpd therefore neither powers
the logical domain off nor re-enters its power-on callback.

`patches/t6040-pmgr-force-active-debug.patch` instead exports a diagnostic-only
helper from the existing PMGR driver. Under the provider's existing IRQ-safe
lock, it reads ACTUAL, skips providers already at `f`, and otherwise calls the
normal `apple_pmgr_ps_set(..., ACTIVE, false)` sequence. This clears automatic
gating, writes the existing PMGR state register, and polls ACTUAL. The Apple
diagnostic recursively follows only its declared DT parents, parents first,
then snapshots before/after and returns before `nvme_add_ctrl()`. On the known
snapshot it will write only `apcie_sys_st0`, `apcie_sys_st1`, and
`apcie_phy_sw`. It cannot queue reset work or access ANS MMIO. As before, do
not unload it; reboot after the trace.

Prepared artifacts:

- `Image-nvme-pmgr-force-active`:
  `3dc2e875b3834750b0211442a411ea96563f0308895cbdee10fddf0fa19bd6e2`;
- `t6040-j614s-dcuart-nvme-pmgr-force-active.dtb`:
  `f0165590215b14062e5082d7cc0d4a5f53723f2500a1f26d49f112a9f8465ce9`;
- `initramfs-dcuart-nvme-pmgr-force-active.cpio.gz`:
  `d5930ba513364acd17ca044fdf320163015c01a17bb8f00d474b0a342e14ce19`;
- `nvme-core-pmgr-force-active.ko`:
  `5e61ba16697daa382c5bb614fdaf3d5948a3818c11a630d5766e3b88ead36af7`;
- `nvme-apple-pmgr-force-active.ko`:
  `d18f2a2a25116d8ba4aaa054431217bd6123cd36b6eae1afbf8a78e0dbc5858d`.

The single force-active attempt is complete. Linux #26 reached BusyBox and all
three expected callbacks succeeded. The verified changes were:

```text
apcie_phy_sw   0x1400024f -> 0x0f0002ff  actual 4 -> f  auto 1 -> 0
apcie_sys_st0  0x1000030f -> 0x0f0003ff  actual 0 -> f  auto 1 -> 0
apcie_sys_st1  0x1000030f -> 0x0f0003ff  actual 0 -> f  auto 1 -> 0
```

ANS and every already-active provider remained unchanged. The diagnostic
printed `PMGR force-active verified; stopping before ANS MMIO`, and the shell
answered both liveness markers. The target was then rebooted rather than
unloading the module and returned to a quiescent m1n1 proxy.

This is the first successful physical-state correction at the fatal boundary.
The third diagnostic is now built. After the same before/after verification,
`patches/t6040-nvme-ans-read-debug.patch` performs exactly one `readl()` of
ANS CPU_CONTROL `0x209600044`, logs its returned value, and immediately exits
through the no-detach path. It does not queue reset work or write CPU_CONTROL.
The DT contains only `apple,pmgr-force-active-read-stop`; neither earlier stop
property is present. Strict checkpatch, full kernel/module link, patch reversal,
DT inspection, marker inspection, and initramfs module comparison all pass.

Prepared artifacts:

- `Image-nvme-ans-read`:
  `47514760a0ca729e7f46c5c71d8cbd403d205a55ee0bdbff59f7f8cdce47cbcc`;
- `t6040-j614s-dcuart-nvme-ans-read.dtb`:
  `01c7511d71d6072e23a72ddac0cbd10795587e830e99f77df988f9d998a2761d`;
- `initramfs-dcuart-nvme-ans-read.cpio.gz`:
  `3c1cfe3dddcbd02b8a4c0ee5eaaecf147627ee5fde17b8ae4250749de65b9c44`;
- `nvme-core-ans-read.ko`:
  `5e61ba16697daa382c5bb614fdaf3d5948a3818c11a630d5766e3b88ead36af7`;
- `nvme-apple-ans-read.ko`:
  `0562b9e66424f2727efd9a4eac9502b7c8c9dd82606e081214d70ffc92b5ac8a`.

Run this once with the current-boot relay. A successful read justifies a later
force-active controller-boot attempt; another reset disproves the
parent-gating hypothesis. Never mount, repair, format, flush, or write the
namespace. Prior exact output:
`logs/t6040-console-20260713-nvme-pmgr-force-active.log`.

## Parked (revisit after pmgr)
- USB gadget console → gadget-Ethernet + SSH (EP0 dies post-enumeration;
  `done/2026-07-11-t6040-usb-gadget-plan.md`).
- cpufreq throttle parity (non-blocking): paired T6041 PMGR analysis recovered
  no safe direct offsets and found target-specific no-op enum slots plus
  RegMap-mediated generic paths. Keep the proven PSTATE/APSC-only table; do not
  probe neighboring offsets. See
  `done/2026-07-23-t6040-cpufreq-throttle-analysis.md`.
- ATC PHY tunables (USB3/TB) — the paired 25F84 kext now proves the T6040
  44-bank order, tunable encoding, banks-0/1 direct eUSB2 init sequence, and
  exact XHCI host branch. HPM reaches S0, but the remaining rollback, host
  transition, and enumeration path is staged through 096 and 102–108; USB2
  root hubs alone are not a functioning fallback.
