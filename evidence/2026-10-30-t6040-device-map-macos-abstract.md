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
- **AP interface (`782a58c`):** unlike M1, the AP has no task-queue/DMA register block. Jobs go to
  the ANE firmware through shared-memory rings, a doorbell register and an IRQ pending/ack pair. The
  AP side is PMGR power, a short coprocessor handshake (~50 ms poll), tunables, and a
  scratch-register boot handshake. Asahi's M1 ANE driver does not carry over; Linux would need an
  RTKit-style coprocessor boot plus the ring/command formats. Long road, parked.
- **Preloaded firmware:** iBoot puts it in two physical ranges (TEXT, DATA) listed in the ANE node's
  `segment-ranges` (32-byte entries: u64 phys, u64 fw-virt, u64 remap, u32 size), flagged
  pre-loaded and firmware-protected (CTRR class). m1n1 must reserve them no-map, or Linux can
  allocate them. Check against `/proc/iomem` once the ADT is available.

## Audio (roadmap, no ticket; wallace-rex `d6289bd`, 2026-10-31)

Feasible, nothing blocked, but a different model from M1/M2.

- **MCA (I2S/clock) is programmed by the AOP firmware, not the AP.** There is no AP-visible MCA node.
  The AP sends the AOP a 109-byte MCA config as a property on a per-stream node, then moves the stream
  idle → active → running (and back) through another property. Stream nodes are addressed by ADT
  FourCCs (`spkr`, `cout`, `cin`, `hpai`). Transport is the AOP SPU app interface `AOPAudioService`:
  packets have a `0x24`-byte header (`0xffffffff`, command ID, an XOR checksum of the payload words at
  `+0x18`, total length at `+0x1c`); command IDs `0xC3000004` get property, `0xC3000005` set property,
  `0xC3000008` events. Asahi's M2 AOP microphone driver is the closest precedent.
- **ADMAC is AP-driven**: `admac,t604x` at `0x313800000` (IRQ 754) and `0x313300000` (IRQ 757), behind the
  AOP's DART (SIDs 8 and 10). Global start/stop/IRQ registers match the classic ADMAC. New: separate TX and
  RX channel banks (TX n at `0x8000 + n*0x200`, RX n at `0xC000 + n*0x200`; the classic layout
  interleaves them) and a third per-channel FIFO (TD `0x10000`/`0x14000`, CS `+0x100`, new PCT `+0x200`).
  The descriptor format is not decoded, so `apple-admac` needs a T604x variant.
- **Amps and jack:** six SN012776 speaker amps on AP I2C (left i2c1 `0x38`-`0x3a`, right i2c3
  `0x3b`-`0x3d`, GPIO reset); macOS's init has the same test-page quirk as Linux `tas2764`'s SN012776
  support. I/V sense returns on an ADMAC RX channel. Jack codec CS42L84 on i2c2 `0x4b` (Linux `cs42l84`
  exists), needing MCLK/BCLK from the MCA.
- Exclaves are off on J614s (ADT `exclaves-enabled = 0`), so mic and speaker paths are not isolated.
- First safe rig step when wanted: a read-only AOP property get (state) on node `spkr`. Prerequisite:
  an AOP RTKit/SPU client in Linux. Not urgent against 205/305/5006.

### Audio part 2: formats decoded (wallace-rex `findings/2026-10-31-audio-formats.md`)

- **ADT audio-data `reg` (36 bytes) is the I2S config** for each stream: master/clock flags, slots, slot
  width, data delay, MCLK Hz, frame length, fsync width, rate as a/b kHz, TX/RX slot masks, channel
  counts, sample bits and per-direction slot widths. Speaker: 12 MHz MCLK, 250-BCLK frame, 48 kHz, TX 6
  slots x 32-bit (24-bit samples), RX 12 x 16-bit (I/V sense).
- **The 109-byte MCA config is a merge.** The AP fills timing (MCLK Hz, BCLK divider, fsync
  edge/polarity/high/low, per-direction delay/edge/LSB/slot masks/slot and sample bits). The
  clock/sync/serializer names and pin-route masks come from the AOP's own template. A Linux driver does:
  GET template, overlay timing, SET, GET.
- **Stream state:** GET current state; idle to "active" (state FourCC read from the AOP at init) to
  "running" with a TX/RX direction mask; reverse on stop. There are also a reset property and an
  MCLK-enable property.
- **ADMAC T604x:** the descriptor is the classic four words (addr lo/hi, length, misc with an 8-bit
  non-zero tag and an attr byte); completion FIFO reports are four words (54-bit timestamp, status,
  tag). New: a two-word PCT report FIFO (timestamp and tag) that TX uses by default, and TX buffers are
  split into (len-16, 16) descriptor pairs. Channel reset/arm/start sequences are decoded. ADMAC power
  goes through a per-controller power switch (resume/suspend refcount) before start.
- **Correction to part 1:** the TD and completion FIFO addresses are the classic ones; only the split
  channel banks, the PCT FIFO and a few extra block registers are new.
- **Bottom line:** speakers are a buildable driver stack (AOP client, ADMAC T604x variant, and
  `tas2764`/SN012776). The only unknowns that need hardware are the AOP template values, one read-only
  GET.

## Touch ID: not feasible

The OS talks to the sensor over SPI, but all capture data and commands are encrypted under a
sensor↔SEP session key, and matching runs in the SEP. No Linux path without the SEP.
