# Independent review: USB2 slice patch v2 (dwc3 -EINVAL fix) — every claim verified

Date: 2026-08-04. Reviewer: fable (offline, no rig). Reviewed work: the
sibling agent's `evidence/2026-08-04-t6040-dwc3-einval-phy-mode-ordering.md`
and `patches/0001-phy-apple-add-experimental-T6040-USB2-only-slice.patch` v2,
sha256 `b7f02c3cb06b0ed6e490d473a2efd99f61b8cd1ab089a0a09f72ecdec7b60a30`
(same hash at `patches/` and the staged `$OUT` copy).

## Verdict

**The root-cause analysis is correct and the v2 fix is correct, minimal, and
safe to build.** Every mechanism claim was re-derived from source
independently; none failed. The safety envelope is unchanged from the
188-reviewed v1 — the diff is one probe-time default plus a comment, no new
register access, no new addresses, no widened mode acceptance.

## Claim-by-claim verification

| Claim | How verified | Result |
|---|---|---|
| dwc3-apple calls `phy_set_mode()` on `dwc.usb2_generic_phy[0]` before core probe | `drivers/usb/dwc3/dwc3-apple.c:236`; probe sets `DWC3_APPLE_PROBE_PENDING` at `:477` | ✓ |
| The phy array is populated only inside `dwc3_core_init()` | `dwc3_core_get_phy()` under `!dwc->phys_ready` in `core.c` (committed tree), followed in the same function by `dwc3_phy_power_on()` | ✓ — no consumer `set_mode` can precede `power_on` |
| `phy_set_mode()` on a NULL phy silently returns 0 | `drivers/phy/phy-core.c:379` `phy_set_mode_ext()`: `if (!phy) return 0;` | ✓ — the v1 mode request was provably lost |
| v1 gate: `power_on` returns -EINVAL when mode ≠ HOST | patch body, `t6040_usb2_power_on()` | ✓ |
| v2 keeps `set_mode` rejecting non-host | patch body, `t6040_usb2_set_mode()` returns -EOPNOTSUPP | ✓ |
| Jul-21 DTB had no `phys=` (why the old smoke reached root hubs) | `dtc` on `t6040-j614s-dcuart-usb-host-right.dtb`: **zero** `phys =` properties | ✓ |
| Jul-29 DTB arms the gate | `dtc` on `…wifi-usb2-native-right.dtb`: `usb@392280000` has `phys = <… PHY_TYPE_USB2>` + `apple,force-host-mode` | ✓ |
| The failed image really contained the v1 slice (stale-image hypothesis refuted) | `Image-macsmc-hid-type-fix-nbcon-ppp-usb2-native-right` (sha `3caa0f78…`, matching the doc) contains `phy-apple-t6040-usb2`, `apple,t6040-atcphy`, and `Failed forced host-mode init` exactly once each | ✓ |

## Review notes (non-blocking)

1. **The honest new-risk statement for the re-run:** v1 never reached the
   eUSB2 register sequence, so the first v2 boot is the first *live*
   execution of the 188-reviewed MMIO writes in `power_on`. Those writes were
   reviewed as ADT-derived and the enabling DT node remains the review
   boundary; nothing new to approve, but the re-run's expectation section
   should say the sequence is now actually exercised.
2. `dwc3-apple.c:239` can still request `PHY_MODE_USB_DEVICE` on other DTs;
   the slice answers -EOPNOTSUPP and dwc3-apple ignores `phy_set_mode()`
   returns. Immaterial under `apple,force-host-mode`, worth remembering if
   the slice is ever referenced from a dual-role DT.
3. The sibling's doc correctly flags that the 2026-08-04 run had drifted from
   ticket 108's pinned artifacts (PCIE-sibling DTB, different Image). The
   drift did not cause the failure, but the re-run must pin fresh hashes.
4. Provenance note for the record: the root-cause doc is headed
   "Author: fable", while the rig log and ticket 108's entries attribute the
   run and analysis to `claude`. One of the two labels is a slip; the
   analysis quality is unaffected.

## What the re-run still needs (COORDINATION gates)

1. Two clean, byte-identical builds from independent trees with v2 applied
   (same profile as `Image-macsmc-hid-type-fix-nbcon-ppp-usb2-native-right`
   plus the v2 slice), new pins for Image/System.map/config/DTB.
2. Exact-artifact review of the built binaries by an agent other than the
   builder — this document is the *code* review; binaries reviewable on
   request (strings markers: the v2 comment does not appear in the binary, so
   pin by hash, and the presence markers above still apply).
3. `queue ready` with the fresh pins, then the lease.

Expectation stays as the sibling stated it: v2 restores the path to xHCI root
hubs; VBUS still belongs to the SPMI `sn201202x` PD controller and its
in-progress tipd-SPMI transport driver. A child device on the bus-powered
S128 stick would mean VBUS survived the warm reboot — a bonus, not the
expectation.
