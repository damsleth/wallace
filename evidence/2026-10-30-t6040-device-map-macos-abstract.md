# Device map, macOS side: public-safe abstract (2026-10-30)

Source: wallace-rex Pipelines D–H (private, commit `ad782cf`, `findings/2026-10-30-device-map.md`).
This is its public-safe abstract: no Apple strings, symbols or class names. Everything here is a
hypothesis until the rig confirms it. The live and Wallace side is in
[device-map-live](2026-10-30-t6040-device-map-live.md).

**Common blocker: the J614s ADT.** Almost every next step below is an ADT question (bus, slave,
GPIO, domain parentage, calibration). Sources: 5027 (`MTD_PHRAM`, live ADT as `/dev/mtdN`) or the
full dump on the Mac (`j614s-full-20260728.adt`).

## Keyboard backlight (works)

macOS uses the same register sequence as `pwm-apple`: ON count at `0x1c`, OFF count at `0x18`, then
CONTROL `0x00 = 0x4021`, under a lock, after power and clock are enabled. Stop writes CONTROL = 0,
then drops power and clock. One channel, no inversion. **Power and clock are on demand**, not
always-on (relevant to 5028).

## Panel brightness (164)

- Display firmware owns the policy and asks an AP-side backlight driver to apply a level.
- The level is an 11-bit LED-current DAC code (0..0x7FF).
- Variants: **SPMI** (one 2-byte Extended Register Write Long at `0x1E00`: `L[7:0]`, `L[10:8]`; never
  writes 0, no enable), **PWM**, **DWI** and **I2C**.
- The ADT decides which variant J614s uses and on which bus/slave. Look for the backlight node's
  update/enable "function" properties and its calibration properties.
- A PWM variant exists, so the `pms_fpwm*` domains that won't power on (5028) may matter here.
- **Executor (correction, `eeaebdf`):** in a backlight function property (`[u32 phandle][u32 tag][args]`)
  the phandle selects the executor device; the tag only separates update from enable. A boolean on
  the backlight node can short-circuit to the SPMI executor.
- **Calibration:** nits → mA → DAC through two piecewise u16 tables in the ADT, plus segment-end
  currents in 16.16 mA. The upper current is a hard clamp (default 25.0 mA) and bounds any test level.

## Display / DCP (022)

- Same coprocessor model as Asahi's DCP.
- The AP↔DCP link protocol version for this firmware is 195 (`0xc3`), checked against the upper 16
  bits of a word the DCP sends. There is also a firmware-hash check.
- There are about 136 DCP→AP callback IDs, in ranges D000–D008, D100–D134, D200–D209, D300,
  D400–D424, D450–D453, D550–D574, D581–D599 and D700 (the table can be rebuilt privately).
- Panel TCON access is not needed for basic operation.
- New compared with M1/M2: external DP links raise an SoC voltage performance state around link
  changes.

## HDMI

- The path is dcpext → DP PHY → DP-to-HDMI converter.
- The converter is identified by its DP branch OUI, so it is one of several families. It is
  controlled through I2C-over-AUX.
- Detection (`eeaebdf`): DPCD branch OUI at `0x500`: `00 1C F8` = Parade PS186, `00 60 AD` =
  MegaChips MCDP2900, after a 12-byte write/readback check at `0x300`/`0x310`. The ADT does not name
  the chip, and no ADT property binds an HDMI port to a specific dcpext (the crossbar picks at run time).
- Converter power, HPD, CEC enable and reset come from GPIOs, which earlier Wallace ADT evidence maps
  to SMC keys.
- The crossbar is a small delta from the M2-generation crossbar.

## USB-C (023, 305)

- The USB3 controller is still dwc3.
- The T6040 Type-C PHY is a new generation: 80G-class CIO lanes, a mailbox to a PHY microcontroller
  whose firmware is resident or preloaded (the AP only kicks and polls it), eUSB2, and DP 2.1
  UHBR10/20 training tables.
- The retimers only report version and crash logs.

## GPU (4004)

- iBoot preloads the GPU firmware; the OS ships no firmware blob. There are per-variant tables for two
  G16 SKUs × two steppings. The ABI gate is probably a firmware UUID block, not a version string.
- Same coprocessor transport and GPU page-table ownership in the OS as G13/G14.
- New: a different kick/queue model, dynamic-caching memory pools, new power management.
  Upstream-scale work.

## ANE (no ticket)

- Firmware runs on an internal core, preloaded by iBoot into a **CTRR-protected region**. That's
  relevant to the reservation discipline in 5015.
- The OS-side hardware layer only applies addr/mask/value tunables; no task-queue registers are
  named, so Asahi-style direct MMIO is unproven on this generation.
- Up to 4 instances. All `ane_*` power domains are off on the live boot.

## Touch ID: not feasible

The OS talks to the sensor over SPI, but all capture data and commands are encrypted under a
sensor↔SEP session key, and matching runs in the SEP. No Linux path without the SEP.
