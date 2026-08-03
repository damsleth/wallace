# T6040 U-Boot as USB stage 2 — the pivotal question answered: NO (2026-07-25)

Ticket 128 asked, before any build work: **does upstream AsahiLinux/u-boot include a
Type-C / ATC-PHY driver able to bring a USB-C port up in HOST mode by itself?**

## Answer: no. U-Boot inherits the same blocker.

Source: `AsahiLinux/u-boot`, branch `asahi`, HEAD `8aa706b2daa49b64102e44067d8514de8a26dc42`
(the exact commit pinned in `done/2026-07-23-t6040-uboot-noio-prep.md`).

`drivers/phy/phy-apple-atc.c` exists and the filename is encouraging, but it is **55 lines
and does nothing**:

```c
static const struct phy_ops apple_atcphy_ops = {
};                                    /* <- empty: no init, no power_on, nothing */

static int apple_atcphy_reset_of_xlate(struct reset_ctl *reset_ctl,
                                       struct ofnode_phandle_args *args)
{
        if (args->args_count != 0)
                return -EINVAL;
        return 0;                     /* <- accepts a reset request, does nothing */
}
```

It binds a no-op `UCLASS_PHY` child purely so phandle references resolve, and registers a
reset controller whose `of_xlate` succeeds without touching hardware. Its compatibles are
`apple,t6000-atcphy` and `apple,t8103-atcphy` — **not** `atc-phy,t6040`.

Further checks:

- **No Type-C/PD support at all**: there is no `drivers/usb/typec` directory, and no
  `tps6598x`/`tipd` driver anywhere in the tree (the only `typec`/`usb-c` hits are unrelated
  upstream DT bindings for other SoCs).
- `configs/apple_m1_defconfig` does enable `USB_XHCI_HCD`, `USB_XHCI_DWC3`, `USB_DWC3`,
  `USB_KEYBOARD` and `NVME_APPLE` — i.e. the **host-controller and storage stack** is
  there, but nothing that establishes cable orientation, VBUS, the eUSB2 repeater state or
  the ATC PHY lanes.

## Consequence

U-Boot contributes only what we already knew m1n1 lacks — a USB mass-storage + filesystem
stack. That is worthless until a port actually enumerates, and U-Boot cannot make it
enumerate. **The U-Boot route does not bypass the HPM/ATC host-link work.**

Therefore USB read/write (ticket 138) reduces to exactly two routes:

1. **a reviewed HPM/ATC host transition** (tickets 096 → 097), currently NO-GO pending new
   primary evidence for the rollback path — now the sole realistic route, and the
   maintainer has authorised work in that lane;
2. **upstream `atc-phy` + tipd/HPM Linux drivers** (ticket 023), which do not exist for
   T6040 and are not build-here.

## Aside, not a claim

Why does `USB_KEYBOARD` work on M1 under U-Boot if nothing programs the PHY? Most likely
because iBoot leaves the relevant port's PHY in a usable state for the boot/DFU path, so
DWC3 inherits a warm PHY. That is a hypothesis, not something verified here, and it does
not help us: on T6040 Linux already brings up DWC3/xHCI and sees only root hubs
(tickets 063/064), which is exactly the "no PHY provider" symptom.

## Status

Ticket 128's question is answered; the build half (a T6040 stage-2 U-Boot config with
xHCI/DWC3 + USB_STORAGE + FAT) is **deliberately not started**, because it would produce a
loader that still cannot see a disk. Revisit only if 096/097 or 023 make a port enumerate.
