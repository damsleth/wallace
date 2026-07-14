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

## Host-mode conversion (the DT delta)

The current DT pins every port to the parked gadget config
(`apple,force-device-mode`, `dr_mode = "peripheral"`). The host candidate
inverts exactly that, keeping DART/power/`high-speed`:

```dts
&usb_drdN {
    /delete-property/ apple,force-device-mode;
    dr_mode = "host";
    status = "okay";
};
&usbN_dart0 { status = "okay"; };
&usbN_dart1 { status = "okay"; };
```

Buildable candidate: `dts/t6040-j614s-dcuart-usb-host.dts` (includes the proven
DockChannel-console + keyboard base; enables all three ports in host mode so
whichever carries the disk enumerates; no gadget, no ATC PHY nodes).
`maximum-speed = "high-speed"` (USB2, ~480 Mbps) is retained from the base nodes.

## The two hard constraints (why this can't be fully closed statically)

1. **No AP-visible Type-C PD/HPM controller on M4.** The offline ADT shows no
   HPM/CD321x on any AP i2c bus — only audio codecs, `uatcrt0-2` retimers (i2c6),
   `pcon0` (i2c8). So nothing tells the SoC cable orientation/role, and nothing
   the AP may legitimately touch controls **VBUS**. `dr_mode = "host"` removes the
   need for role *detection*, but whether downstream VBUS is supplied to a device
   is unknown from the DT. PMU/SMC writes are forbidden, so if port power is
   PMU-gated we cannot enable it — a **self-powered enclosure or powered hub** is
   the mitigation.
2. **No `atc-phy,t6040` driver.** The USB2 PHY is only whatever iBoot/m1n1 left
   configured. The gadget investigation proved a port can enumerate once on that
   leftover state but could not survive suspend/resume without the PHY driver
   (`done/2026-07-11-t6040-usb-gadget-plan.md`). For a **host** with a wired disk
   the controller keeps the bus active (no host-initiated selective suspend by
   default), so the leftover-PHY path is more likely to hold than in the gadget
   case — but this is a hypothesis to test, not a proven fact.

## Port selection

Physical Type-C port ↔ `usb-drd` index is not derivable from the captured ADT
facts (no port-topology node captured) and needs either the raw ADT `usb-hosts`
mapping or an empirical check. The DebugUSB tether uses **KIS on the DFU port**
(a debug transport, not dwc3); a plain cable in another port coexists. So:

- Enabling host on all three ports (as the candidate does) is the low-risk way to
  find the viable one without guessing.
- The port whose USB2 PHY iBoot/m1n1 initialized is the best host bet; identifying
  it (and whether it is the DFU port, which would trade against the tether) is a
  live-test question for ticket 032 / a gated rig run.

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
