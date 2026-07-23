# T6040 J614s USB2-host DT audit + access manifest (2026-07-14)

Ticket 031 (offline, P1, storage track). Audit of the saved J614s ADT facts and
the current DT for a **USB2 host-only** path to carry an external root disk
(ticket 009 design; internal NVMe SPTM-blocked, ticket 008). Produces the exact
per-port access manifest and a buildable host DT candidate. Excludes the parked
gadget console and the unknown ATC PHY tunable buckets. Static only; no rig, no
MMIO — the rig was held by another agent this session and no live ADT re-dump was
needed.

## Sources

ADT facts from the offline `j614s.adt` audit already captured in
`done/2026-07-11-t6040-usb-gadget-plan.md` and
`done/2026-07-10-t6040-atc-usb-dart-plan.md`; DT reg/IRQ/power/iommu values from
`arch/arm64/boot/dts/apple/t6040.dtsi` (nodes authored from that ADT). No new
live dump; where a value needs the rig to confirm it is flagged below.

## Access manifest (per usb-drd port)

`/arm-io` bus base adds `0x3_00000000` to the ADT offsets. All three ports share
the same shape: one dwc3 (core + Apple wrapper) + two `dart,t8110` instances
(stream IDs 0 and 1) + one `ps_atcN_usb` power domain.

| Port | dwc3 node (core / apple-wrap) | dwc3 IRQ (AIC) | DART0 | DART1 | DART IRQ | iommus | power domain |
|---|---|---|---|---|---|---|---|
| 0 (ATC0) | `usb@382280000` (+0..0xcd00 / +0xcd00..0x3200) | 1619 | `iommu@382f00000` | `iommu@382f80000` | 1623 | `<&usb0_dart0 0>, <&usb0_dart1 1>` | `ps_atc0_usb` |
| 1 (ATC1) | `usb@38a280000` | 1651 | `iommu@38af00000` | `iommu@38af80000` | 1655 | `<&usb1_dart0 0>, <&usb1_dart1 1>` | `ps_atc1_usb` |
| 2 (ATC2) | `usb@392280000` | 1683 | `iommu@392f00000` | `iommu@392f80000` | 1687 | `<&usb2_dart0 0>, <&usb2_dart1 1>` | `ps_atc2_usb` |

Notes from the ADT:
- `usb-drd0..2` compatible `usb-drd,t6040` + `usb-drd,t8132`; the kernel matches
  the `t8132` fallback. DT uses `apple,t8103-dwc3` (Apple dwc3 glue,
  `drivers/usb/dwc3/dwc3-apple.c`).
- Full ADT IRQ arrays: drd0 `[1619..1622]`, drd1 `[1651..1654, 943]`,
  drd2 `[1683..1686, 953]`. The DT uses only the first entry per port — an
  **untested assumption** flagged in `t6040.dtsi`; try the next entry if the
  controller stays silent.
- DARTs are `dart,t8110` (fully supported in `dart.c`); two per port (SID 0+1),
  as in the t8103 template. Bypass-forcible like MTP if needed.
- Clock-gate: PMGR device 299 for drd0 (`clock-gates` present per port); the DT
  models port power via `ps_atcN_usb`.
- `atc-phy0..3` = `atc-phy,t6040`: **no kernel driver**, per-bucket PHY
  `reg_offset`s unknown → USB3/Thunderbolt out of scope; USB2 only.

## Host-mode conversion — DT delta **plus a driver patch** (corrected)

The current DT pins every port to the parked gadget config
(`apple,force-device-mode`, `dr_mode = "peripheral"`). Inverting the DT is
necessary but **not sufficient**: `dwc3-apple` is role-switch driven. On probe it
stays in `DWC3_APPLE_PROBE_PENDING` and only enters `DWC3_APPLE_HOST` /
`DWC3_APPLE_DEVICE` when a Type-C role-switch/cable event calls
`dwc3_apple_init()`. The current Linux DT has no supported HPM/Type-C path to
deliver that event, so `dr_mode = "host"` alone leaves the core down forever —
the same wall the gadget hit. The in-tree fix for gadgets is the
`apple,force-device-mode` property, which
forces `DWC3_APPLE_DEVICE` at probe; there is **no** symmetric host property
upstream.

So host mode needs both:

1. **Driver patch** `patches/t6040-dwc3-apple-force-host.patch` — adds
   `apple,force-host-mode`, forcing `dwc3_apple_init(HOST)` at probe (an exact
   structural mirror of the in-tree `apple,force-device-mode` block). Applies
   clean against the current tree.
2. **DT delta** per port:

```dts
&usb_drdN {
    /delete-property/ apple,force-device-mode;
    dr_mode = "host";
    apple,force-host-mode;
    status = "okay";
};
&usbN_dart0 { status = "okay"; };
&usbN_dart1 { status = "okay"; };
```

Buildable candidate: `dts/t6040-j614s-dcuart-usb-host.dts` (proven DockChannel
console base; all three ports forced host so whichever carries the disk
enumerates; no gadget, no ATC PHY nodes). `maximum-speed = "high-speed"` (USB2,
~480 Mbps) is retained. dtc-clean.

### Shared risk with the parked gadget

Forcing host is necessary but the deeper unknown from the gadget effort applies
here too. With `apple,force-device-mode` the gadget port *enumerated once* but
went **deaf right after enumeration** (EP0 timeouts), suspected to be the missing
`atc-phy,t6040` USB2 PHY driver and/or wrong t6040 dwc3-apple wrapper (CIO)
offsets (`done/2026-07-11-t6040-usb-gadget-plan.md`). A forced-host port may hit
the same wall. Therefore a **rig smoke test that an external disk actually
enumerates and stays alive** must precede building a full external rootfs
(ticket 032) — do not invest in the rootfs on the assumption host works.

## The two hard constraints (why this can't be fully closed statically)

1. **No supported Linux Type-C HPM path.** The authoritative 2026-07-21 ADT
   capture corrects this audit's earlier I2C-only inference: the right-side
   HPM is `/arm-io/nub-spmi-a1/hpm2`, compatible `usbc,sn201202x,spmi`, and it
   shares `acio2` with `usb-drd2`. The current Linux DT/driver set does not
   describe that SPMI HPM, connector, or Type-C mux/switch, so nothing tells
   Linux cable orientation/role or legitimately controls **VBUS**. Direct SPMI,
   PMU, or SMC writes remain forbidden. A self-powered enclosure or powered
   hub can test whether VBUS is the practical blocker, but cannot replace HPM
   CC/orientation and eUSB2-repeater setup.
2. **No `atc-phy,t6040` driver.** The USB2 PHY is only whatever iBoot/m1n1 left
   configured. The gadget investigation proved a port can enumerate once on that
   leftover state but could not survive suspend/resume without the PHY driver
   (`done/2026-07-11-t6040-usb-gadget-plan.md`). For a **host** with a wired disk
   the controller keeps the bus active (no host-initiated selective suspend by
   default), so the leftover-PHY path is more likely to hold than in the gadget
   case — but this is a hypothesis to test, not a proven fact.

## Port selection

This was unresolved in the older partial audit. The authoritative 2026-07-21
capture now maps `usb-drd0 = left-back`, `usb-drd1 = left-front`, and
`usb-drd2 = right`. The left-back port carries the DebugUSB/KIS tether and must
remain disabled; the current external-drive candidate is right/`usb-drd2` only.
The old all-three-port candidate is retired.

- DebugUSB is a debug transport distinct from Linux DWC3, so the tether can
  coexist with a plain cable on the right port.
- The right port's inherited PHY state is still not a supported host contract;
  ticket 063 proved only its DART+xHCI root hubs.

## Open questions handed to ticket 032 / gated rig run

1. Which physical port maps to drd0/1/2, and which has a usable USB2 PHY at Linux
   handoff?
2. Does `dr_mode = "host"` bring a port up without atcphy/PD, and is **VBUS**
   actually present for a bus-powered device (or must the device be self-powered)?
3. Can host storage and the DebugUSB tether coexist on different ports, or does
   the only PHY-live port double as the DFU/tether port?
4. Confirm the per-port dwc3 IRQ (first-ADT-entry assumption) and the two-SID
   DART stream mapping under host-mode DMA.

## Deliverables

- `dts/t6040-j614s-dcuart-usb-host.dts` — buildable USB2 host candidate.
- This manifest.

Excluded as scoped: the gadget/peripheral console (parked) and all ATC PHY
tunable buckets (`atc-phy,t6040` unsupported). Next: ticket 032 builds the
external-root artifact set (kernel config, initramfs with USB host + usb-storage/
uas + root-discovery/switch_root, bootargs, hashes, read-only first-boot
procedure) on this candidate, and stops before proposing a rig run.

## Post-smoke correction (2026-07-21)

Ticket 063 validated the prediction that force-host was necessary but not
sufficient: DART and xHCI reached healthy root hubs, with no child device. The
raw ADT also resolves `usb-drd2.atc-phy-parent` to `/arm-io/atc-phy2` and
contains T6040-specific USB2 host/device tunables. The Linux DT has no PHY
provider, so `dwc3-apple`'s host-mode `phy_set_mode()` calls act on absent
generic PHY handles. Full analysis:
`done/2026-07-21-t6040-usb-right-no-connect-analysis.md`.
