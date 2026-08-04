# 108: dwc3 -EINVAL root cause — the v1 PHY slice can never be powered on through dwc3's probe path

**Date:** 2026-08-04. **Author:** fable (offline analysis, no rig).
**Input:** the 2026-08-04 right-port run (ticket 108) that failed before the VBUS
question with `dwc3-apple 392280000.usb: error -EINVAL: failed to initialize
core` / `Failed to probe DWC3 Core, err=-22` / `error -EINVAL: Failed forced
host-mode init`.

## Verdict

Not hardware, not a stale kernel, not an image/DTB pairing mistake. The
failure is **intrinsic to v1 of
`patches/0001-phy-apple-add-experimental-T6040-USB2-only-slice.patch`
(`bc7ba641`)**: its fail-closed mode gate in `power_on` can never be satisfied
when the phy is consumed through dwc3's core-probe path, on **any** image —
including the exact artifact set ticket 188 reviewed. The 188 review was
offline-only ("do not run"), so the 2026-08-04 boot was the first live
exercise of this code path, and it failed deterministically.

## The mechanism, with code references

All references are to the committed state of `~/Code/linux`
(`wallace/t6040-bringup`) plus the two wallace patches kbuild applies.

1. The DT (`t6040-j614s-dcuart-wifi-usb2-native-right.dts`) sets
   `apple,force-host-mode` on `usb_drd2`, so `dwc3_apple_probe()` calls
   `dwc3_apple_init(appledwc, DWC3_APPLE_HOST)` while
   `appledwc->state == DWC3_APPLE_PROBE_PENDING` — i.e. **before
   `dwc3_core_probe()` has ever run** (force-host patch hunk; probe sets
   PROBE_PENDING at `dwc3-apple.c:477`).
2. `dwc3_apple_init()` starts with
   `phy_set_mode(appledwc->dwc.usb2_generic_phy[0], PHY_MODE_USB_HOST)`
   (`dwc3-apple.c:236`). But `dwc.usb2_generic_phy[]` is populated only by
   `dwc3_core_get_phy()`, which runs inside `dwc3_core_init()`
   (`core.c:1381`) — which hasn't happened yet. The struct is kzalloc'd, the
   phy pointer is NULL, and `phy_set_mode()` on a NULL phy **returns 0
   silently** (phy-core). The mode request is lost.
3. `dwc3_apple_init()` proceeds to `dwc3_apple_core_init()` →
   `dwc3_apple_core_probe()` → `dwc3_core_probe()` → `dwc3_core_init()`,
   which fetches the phys (`core.c:1381`), runs `phy_init()` (no-op for the
   slice, it has no `.init`), soft-resets the core, then calls
   `dwc3_phy_power_on()` (`core.c:1417`).
4. `t6040_usb2_power_on()` in the v1 slice checks
   `if (tphy->mode != PHY_MODE_USB_HOST) return -EINVAL;` — and `tphy->mode`
   is still the probe-time default `PHY_MODE_INVALID`, because the only
   `set_mode` call happened on the NULL phy in step 2. **-EINVAL.**
5. The error propagates exactly as observed: `dwc3_core_probe()` prints
   `failed to initialize core` with -EINVAL (`core.c:2342`),
   `dwc3_apple_core_init()` prints `Failed to probe DWC3 Core, err=-22`
   (`dwc3-apple.c:204`), the force-host hunk prints
   `Failed forced host-mode init`, and the device probe fails with -22.

There is no ordering in which a consumer's `phy_set_mode()` can precede
`phy_power_on()` here: dwc3 powers its phys on **inside** core probe, and no
dwc3 code path delivers `set_mode` to the usb2 phy before that point (the
`skip_core_init_mode` flag skips `dwc3_core_init_mode()`, and even that runs
after core init).

## Why the 2026-07-21 smoke reached root hubs and this run did not

The Jul-21 DTB (`t6040-j614s-dcuart-usb-host-right.dtb`) had **no `phys=`
property at all**, so `dwc3_core_get_phy()` got -ENODEV, treated it as
"no phy", and every phy call was a NULL no-op — the core came up on whatever
eUSB2 state iBoot/macOS left warm. The Jul-29 native DT introduced the
`phys = <&atcphy2_t6040_usb2 PHY_TYPE_USB2>` reference for the first time,
which is what armed the v1 gate.

## Checks that eliminated the competing hypotheses

- `Image-macsmc-hid-type-fix-nbcon-ppp-usb2-native-right` (the booted image,
  sha256 `3caa0f78…`) **does** contain the PHY slice: `strings` finds both
  `phy-apple-t6040-usb2` and `apple,t6040-atcphy`, and its saved config has
  `CONFIG_PHY_APPLE_T6040_USB2=y`. The "Jul-29 image lacks the eUSB2 patch"
  hypothesis from the ticket is refuted.
- The booted DTB (`…wifi-usb2-native-right.dtb`, `934dd7b2…`) is the PCIE=1
  sibling of the 188-reviewed DTB (`0c39cf06…`); both carry the identical USB
  delta (same phy node, same `phys=`/`apple,force-host-mode` on `usb_drd2`),
  so the DTB difference is not the failure either — but note the run did NOT
  use the 188-pinned artifacts (Image `40670d81`/XZ `50d23449`), so 108's
  "exact hashes" gate had already drifted. Immaterial to this failure, worth
  keeping honest in the record.
- SD (`mmcblk0`) came up in the same boot: machine healthy, kernel
  driver-complete.

## Fix (v2 of the same patch, same filename, kbuild unchanged)

`patches/0001-phy-apple-add-experimental-T6040-USB2-only-slice.patch` is now
**v2, sha256 `b7f02c3cb06b0ed6e490d473a2efd99f61b8cd1ab089a0a09f72ecdec7b60a30`**:
the probe-time default becomes `tphy->mode = PHY_MODE_USB_HOST` (one line plus
a comment explaining the dwc3 ordering). Rationale:

- The provider is host-only by construction; host is the only mode it can
  ever legally be in. `set_mode` still rejects every non-host request
  (-EOPNOTSUPP), and the **enabling DT node remains the review boundary** —
  only the right-port host DTs reference this phy.
- The alternative (teaching the force-host dwc3-apple patch to `phy_get` +
  `set_mode` before core probe) adds more divergence from upstream dwc3-apple
  for the same effect and still relies on this driver's single-mode nature.

The v1 hashes pinned by tickets 170/188 (patch `bc7ba641`, object `dfba7f79`,
Image `40670d81`, XZ `50d23449`, DTB `0c39cf06`) are **superseded**; any rig
re-run of 108 needs a fresh build from v2 and a fresh exact-artifact review by
another agent per COORDINATION.md.

## Expectation for the re-run, stated honestly

Fixing -EINVAL restores the path to xHCI root hubs, now with the decoded
eUSB2 host sequence actually executing (v1 never reached it). It does **not**
create VBUS: that still belongs to the SPMI PD controller
(`usbc,sn201202x,spmi`, ticket 231), whose driver is being written as the
tipd SPMI transport. Child enumeration of the bus-powered S128 stick in the
re-run would mean VBUS survived warm reboot; absence of a child with healthy
root hubs remains the expected outcome until the PD driver lands.
