# T6040 right-port USB root-hubs-only analysis (2026-07-21)

Ticket 064, offline follow-up to the approved ticket-063 right-port smoke.
No rig, target MMIO, SPMI/PMU access, storage mount, or external write was used.

## Conclusion

The kernel-side DART, DWC3, xHCI, interrupt, and mass-storage configuration is
good far enough to create responsive USB2 and USB3 root hubs. The unresolved
boundary is before USB device detection: Linux has neither the J614s Type-C/HPM
cable event nor ownership of the T6040 ATC/USB2 PHY. The force-host patch starts
xHCI, but it cannot establish the right port's cable orientation, eUSB2 repeater
state, or USB2 host PHY state.

This is not evidence for changing the DWC3 IRQ or DART mapping. It is also not
authorization to invent ATC register buckets or write the SPMI HPM.

## Authoritative right-port wiring

The saved raw ADT
`/Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.adt`
(SHA-256
`7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84`)
resolves the complete port-3 relationship:

- `/arm-io/usb-drd2` is physical `right`, DWC3 at `0x192280000`. It has
  `atc-phy-parent = 325` and `acio-parent = 196`.
- phandle 325 is `/arm-io/atc-phy2`, compatible `atc-phy,t6040`, port 3. It
  contains generation-specific `tunable_USB2PHY_HOST`, `_DEV`, and `_DFLT`
  data and points at the running `acio-phy-cpu2` RTKit endpoint.
- phandle 196 is `/arm-io/acio2`, compatible `acio,v2`, port 3. The same ACIO
  fabric is the parent of both DWC3 and the right HPM.
- `/arm-io/nub-spmi-a1/hpm2` is the right-side Type-C manager, compatible
  `usbc,sn201202x,spmi`, port 3. It is behind the SPMI controller, not an AP
  I2C bus.

This corrects the older shorthand that M4 has "no AP-visible HPM." The HPM is
described in the ADT, but the current Linux DT/driver set does not expose a
supported HPM-to-Type-C/ATC path, and direct SPMI writes are forbidden by the
project safety rules.

## Why ticket 063 produced only root hubs

The one-port DT deliberately describes only DWC3 and the two USB DARTs. It has
no `phys`/`phy-names`, ATC PHY node, Type-C mux/switch, HPM node, or connector
graph. Consequently, DWC3 core discovery leaves its generic USB2 and USB3 PHY
handles absent. `dwc3_apple_init(HOST)` still creates xHCI, but its
`phy_set_mode(..., PHY_MODE_USB_HOST)` calls have no Linux PHY provider to act
on. That exactly explains a healthy host controller with root hubs and no
physical device event.

m1n1 does leave some inherited state. On M3/M4 its SPMI branch calls the legacy
`usb_phy_bringup()` for each port, and all three m1n1 USB gadgets shut down
before Linux handoff. However, that helper uses a fixed legacy register
sequence and dummy PIPE selection; it does not consume the T6040 ADT's named
USB2 host/device tunable records or deliver HPM cable orientation to Linux.
Inherited state therefore cannot be treated as a reproducible host
configuration.

The in-tree `dwc3-apple` comments make the missing contract explicit: the PHY
must first be brought up with cable mode and orientation, the USB2 PHY must be
set to host while off, DWC3 then initializes, and the USB3 PHY is finalized
before xHCI. The eUSB2 repeater is stateful and reset out of band by the HPM.
`apple,force-host-mode` supplies only the DWC3 state transition.

## What a powered-device test can and cannot prove

A powered hub with a simple, known-good USB2 flash drive (or a genuinely
self-powered USB2 device) is the narrowest safe follow-up because it reuses the
exact ticket-063 artifacts and adds no target writes or new MMIO. Prefer an
A-to-C/hub topology over a direct C-to-C storage cable, connect it before the
power cycle, and do not hotplug during the bounded smoke.

- If a child enumerates and `sd*` persists for at least ten seconds, missing
  downstream VBUS/direct C-to-C role negotiation was the practical blocker;
  proceed to the external-root image.
- If it again shows root hubs only, external power was not sufficient. That
  result still cannot distinguish HPM CC/orientation, eUSB2 repeater state, and
  T6040 PHY programming, but it closes the only safe no-code discriminator.

If the ticket-063 drive was already self-powered or behind a powered hub, do
not repeat the same topology. The project is then blocked on a reviewed
T6040-capable HPM/SPMI + ATC PHY path. The 20 July M3 work, which required an
SPMI wake delay and a regmap fix before real enumeration, validates that
architecture but does not supply T6040 register data or authorize its writes.

**Fixture confirmation after this audit:** ticket 063 used a simple, directly
attached, bus-powered USB-C memory stick. The powered-device discriminator is
therefore still informative and is proposed as ticket 065. Its exact fixture
and unchanged hashes are in
`done/2026-07-21-t6040-usb-right-powered-smoke-preflight.md`.

## Next gate

Do not populate or mount a rootfs until a USB child and `sd*` persist for at
least ten seconds. Once the drive's power topology is confirmed, create a fresh
reviewed rig ticket for exactly one powered, no-`root=` retry using the six
ticket-063 hashes. If that fails—or if ticket 063 was already powered—stop live
retries and track the upstream T6040 HPM/ATC implementation.
