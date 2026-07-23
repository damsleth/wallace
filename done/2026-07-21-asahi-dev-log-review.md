# #asahi-dev review, 2026-07-11 through 2026-07-21

Scope: every daily OFTC `#asahi-dev` log from 2026-07-11 through 2026-07-21,
inclusive, reviewed for consequences to the T6040/J614s bring-up. This is a
local engineering record only; nothing was posted externally.

## Findings that change current work

### 1. DockChannel-UART uses AIC input 816, not ADT input 360

Yuka measured the interrupt on an M4 Pro with m1n1's new bounded
`dockchannel_irq.py` experiment. The live ADT reports 360, but the real UART
interrupt is 816 ([17 July log](https://oftc.catirclogs.org/asahi-dev/2026-07-17#35517028)).
m1n1 PR 628 contains the measurement helper; reviewed head at the time of this
audit was `c357c3ad00286f14b835950d2073bb9de26880ee`.
Enverbalalic independently reproduced 360-versus-816 on real T6041 hardware
([18 July log](https://oftc.catirclogs.org/asahi-dev/2026-07-18#35520617)).

Consequences:

- Correct the J614s DockChannel DT and diagnostic overlays to input 816.
- Retire every present-tense attempt to diagnose input 360. Historical runs
  remain valid for what they directly observed (in particular, injected bytes
  never entered the AP FIFO in ticket 001), but they did not test the real UART
  AIC route.
- The standard mailbox/TTY DT uses `apple,poll-mode`, so correcting the
  interrupt does not alter the first USB smoke test's runtime path.
- UART RX is BIT(1), independently confirmed in the
  [11 July log](https://oftc.catirclogs.org/asahi-dev/2026-07-11#35490175);
  MTP's BIT(3) mask must not be copied to UART.

Do not run the m1n1 interrupt-finder on this rig without a separately reviewed
ticket: it deliberately manipulates known AIC and DockChannel registers.

### 2. A direct DockChannel UART path has booted an M4 Pro

Yuka's WIP `more-t6041` Linux branch (reviewed tip
`079f685b08637a7e82b0c19bb21f6db28830d580`) adds a direct
`apple,dockchannel-uart` driver and puts the data register first so earlycon's
single 4 KiB mapping reaches the FIFO. Its T6040 node uses data
`0x50882c000`, config `0x508828000`, IRQ block `0x50880c000`, and interrupt
816. The branch and boot were discussed on
[18 July](https://oftc.catirclogs.org/asahi-dev/2026-07-18#35520830); it reached
a shell on an M4 Pro with all cores and PMGR
([boot result](https://oftc.catirclogs.org/asahi-dev/2026-07-18#35520933)).
The direct driver's console name is `ttyDC0`, not the current mailbox driver's
`ttydc0` ([21 July](https://oftc.catirclogs.org/asahi-dev/2026-07-21#35526898)).

This is strong evidence that Linux SMP, PMGR, IRQ 816, and a true early
DockChannel console can work on the family. It is not safe to transplant the
branch wholesale: its T6040 description inherits T6041 topology, appears to
retain 16 CPU nodes rather than J614s's measured 14, and logged attempts to
enable memory-channel domains absent on M4 Pro. Audit the driver and board DT
as inputs to tickets 034/044; keep the first USB-host smoke isolated at
`maxcpus=1 idle=nop`.

The same branch explicitly marks `ps_aic` always-on. That agrees with our
broader live-proven T6041-compatible PMGR quirk and is useful evidence for
eventual DT/driver cleanup.

### 3. T6040/T6041 Apple interrupt-controller sysregs remain firmware-locked

Testing on current firmware still classified T6040 and T6041 as locked, while
t8132/t8140/t6050 were unlocked
([21 July](https://oftc.catirclogs.org/asahi-dev/2026-07-21#35526586)). Keep the
local AIC patch that skips `SYS_IMP_APL_VM_TMR_FIQ_ENA_EL2` and
`SYS_ICH_HCR_EL2`; neither macOS 26.6 RC nor 27 beta 4 makes it removable.
Cluster power-off sysregs are also unresolved, so `idle=nop` and the staged
secondary-core plan remain appropriate.

### 4. M3 ATC PHY work reached real USB enumeration

The M3 ATC PHY work needed a delay after SPMI wake and a fix for SPMI regmap
reads longer than 16 bytes
([20 July](https://oftc.catirclogs.org/asahi-dev/2026-07-20#35523759)), then
enumerated an iPhone as `05ac:12a8`
([result](https://oftc.catirclogs.org/asahi-dev/2026-07-20#35524734)). This
validates the upstream direction but does not provide T6040 PHY buckets or
authorize SPMI writes here. Our fixed, one-port USB2 host smoke remains the
right first storage test; USB3/TB tunables remain deferred.

For tether troubleshooting, the 21 July discussion also notes that direct
C-to-C gadget connections can fail role negotiation, while a hub/A-to-C path
or a known Apple charging cable can be more reliable. Treat this as a recovery
hint, not as a replacement for the J614s physical-port map.

## Upstream developments to track

### DCP 14.8.3

DCP booted after a callback fix on 17 July. Chadmed published a rough
`dcp/14.8.3` Linux branch on
[19 July](https://oftc.catirclogs.org/asahi-dev/2026-07-19#35521980); by 21 July
HPD, brightness, and much of the service stack worked, with surface clearing,
EDID/audio details, and GPU dependency still open. m1n1 PR 630's reviewed head
was `7e391ffde033bf2fa0e22cc5bda575f83d2d584b`.

This is useful DCP protocol/versioning groundwork, not proof of T6040 support:
J614s is pinned to a macOS 26.x DCP ABI and still lacks a matching supported
firmware generation. Continue ticket 022 as track-and-test only.

### EFI PSCI CPU power-down

Sven's `efi-psci` work survived CPU power-down without lockdep failures on
[11 July](https://oftc.catirclogs.org/asahi-dev/2026-07-11#35490211), and a v2
with a revised table format was considered usable on
[12 July](https://oftc.catirclogs.org/asahi-dev/2026-07-12#35492892). This may
eventually improve standard boot, hotplug, and cpuidle. It does not replace the
raw-kboot J614s secondary-release/WFE audit. A t6030 report that starting
secondaries changed package power by only about 100 mW is context, not a
T6040 measurement.

### MacSMC DT subdevices

The v2 DT series for MacSMC hwmon/RTC subdevices was picked up for review on
[16 July](https://oftc.catirclogs.org/asahi-dev/2026-07-16#35512290). It is
relevant to later battery, sensor, and RTC integration, but the discussion did
not establish T6040 compatibility. Track it under the existing SMC work; do
not enable unverified PMU/SPMI operations.

### SPMI generation-4 support

m1n1 PR 626 (reviewed head
`cd333da11dceb9906aeca34f5fe7f3c3c4b4f605`) let a t6050 reset its panic
counter and enter DebugUSB itself. There was no evidence that J614s shares the
same SPMI generation or safe register contract. This is watch-only under the
project's absolute no-unreviewed-PMU/SPMI-write rule.

### M4-cohort PCIe work

Yuka published an untested t8142 `pcie_init()` branch for another developer to
try ([21 July](https://oftc.catirclogs.org/asahi-dev/2026-07-21#35526796)).
T8142 is not T6040, so it is not a live-test recipe. Diff its clock/power/
aperture ordering offline under ticket 058; only ADT- or disassembly-backed
T6040 evidence may change the op-115 plan.

## Findings that do not remove a J614s blocker

- Internal storage remains the wrong near-term boot path. Discussion on 20
  July described APFS system-volume access as asking SEP to load keys into the
  NVMe controller; it provided no raw-boot route around the already measured
  SPTM/CoastGuard command boundary. External USB root remains the practical
  path.
- Keyboard/trackpad progress on t6050 and M5 Pro did not supply J614s's paired
  `tpmtfw-j614s.bin` or authorize the PMU-backed reset. Ticket 004 remains
  blocked on the board firmware artifact and safety gate.
- A Broadcom OWE crash and iwd's `OweDisable=brcmfmac` fallback were reported
  on 16 July. Record this for eventual wireless validation; it does not affect
  PCIe link-up or BCM4388 firmware extraction.
- Power telemetry discussion clarified that `PxxC` values are derived while
  `PxxR` values are measured. Use that distinction in later power validation;
  it does not change current bring-up.

## Immediate decision

Rebuild both one-port USB-host DTBs with DockChannel interrupt 816, re-hash and
cross-review them. Then select only the physical controller carrying the
external drive (`usb-drd1` left-front or `usb-drd2` right) for the no-`root=`
enumeration smoke. Keep `usb-drd0`/left-back disabled because it carries KIS,
and keep `maxcpus=1 idle=nop` so USB host is the only new variable.
