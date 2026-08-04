# USB host on T6040: the gap is VBUS, and the pieces needed are now enumerated

Date: 2026-08-04. Offline analysis only — the rig is serialized for ticket 230.

## The blocker, restated precisely

Ticket 170 already established it: the 2026-07-21 right-port smoke **reached the
xHCI root hubs but saw no child device, because a bus-powered stick has no VBUS.**
So the controller, DART and xHCI path work; nothing is powering the port.

`apple,force-host-mode` was added because "the current T6040 bring-up DT has no
supported SPMI-HPM/Type-C connector path" — i.e. it deliberately bypasses the
CD321x USB-PD controller, which is the component that owns CC detection, data
and power role, and **VBUS sourcing**. We routed around the one thing we need.

This also answers a question CJ raised: **a self-powered device does not avoid
the problem.** USB requires a device to see VBUS before it may apply its D+
pull-up, so an iPhone or a self-powered SSD still will not attach without us
sourcing VBUS. Self-powering only reduces the current we must supply.

## What is present, and what is missing

| piece | state |
|---|---|
| dwc3 controller | `CONFIG_USB_DWC3=y`, `USB_DWC3_DUAL_ROLE=y` |
| xHCI | `CONFIG_USB_XHCI_HCD=y`, `USB_XHCI_PLATFORM=y` |
| USB role switch | `CONFIG_USB_ROLE_SWITCH=y` |
| CD321x PD driver | source present (`drivers/usb/typec/tipd/core.c`, `struct cd321x`), but `CONFIG_TYPEC_TPS6598X=m` and `CONFIG_TYPEC=m` — **modules** |
| Apple I2C (the PD controller's bus) | `CONFIG_I2C_APPLE=m` — **module** |
| **Apple Type-C PHY** | `CONFIG_PHY_APPLE_ATC` **not set at all**, and `drivers/phy/apple/atc.c` matches **only `apple,t8103-atcphy`** — zero occurrences of t602x/t6020/t8112 |

## Consequences for the plan

1. **`atcphy` does not support this SoC yet.** The driver is M1-only by
   compatible. Either T6040 is close enough to add a compatible (needs
   verification against the ADT tunables, not assumption), or the native
   eUSB2-only path from ticket 188 stays the route for USB2 storage — which is
   entirely adequate for a flash drive.
2. **Everything needed is a module, on a system with no module-loading in the
   initramfs.** `TYPEC`, `TYPEC_TPS6598X` and `I2C_APPLE` must become `=y` for a
   PD-controller path to work in our boot images. `PHY_APPLE_ATC` additionally
   `depends on TYPEC`, so TYPEC must be built in before the PHY can be.
3. **USB2-only is the cheapest credible route to a flash drive.** Ticket 188's
   candidate already builds byte-reproducibly with the right-port DWC3 in
   host/high-speed mode and the native eUSB2 banks, no USB3 PHY and no role
   switch. It still needs VBUS, so it is not sufficient alone.

## Recommended next steps, cheapest first

1. **Config-only change**: `TYPEC=y`, `TYPEC_TPS6598X=y`, `I2C_APPLE=y`. No new
   code, no DT change; makes the PD controller bindable at all.
2. **Find the CD321x on T6040 from the ADT** — which I2C controller, address and
   interrupt. Upstream M1/M2 DT describes the connector fully; the T6040
   equivalent must be ADT-derived, never copied from another SoC.
3. **Compose a right-port connector node** (i2c + `apple,cd321x` + `connector`
   with `power-role`/`data-role`) and check whether the PD driver can source
   VBUS without any HPM 4CC poking — that is the whole point of ticket 170's
   redirect, and it keeps us out of the deny-by-default SPMI path.
4. Only then re-run ticket 108 (enumeration) and 109 (read-only block).

## What NOT to do again

Do not test with an iPhone expecting a block device: it exposes Apple's
vendor-specific usbmux plus PTP/MTP, never USB Mass Storage, so `usb-storage`
cannot bind. It is a valid *enumeration* probe and nothing more.
