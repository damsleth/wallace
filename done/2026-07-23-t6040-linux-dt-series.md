# T6040/J614s Linux DT consolidation (2026-07-23)

Ticket 047 is complete.  The remaining J614s board edits are committed in the
Linux bring-up branch, and a four-patch RFC draft isolates the core T6040 DT
from the experimental USB and ANS/storage work.  Nothing was posted or run on
the M4.

## Consolidated Linux state

Branch `wallace/t6040-bringup` now contains:

- `92c3d1a62a6f` — document `apple,j614s`, `apple,t6040` as the 14-inch
  M4 Pro MacBook Pro (Mac16,8);
- `246843ff67a8` — correct the board model, build the DCUART variant, and
  replace the unusable ADT IRQ 360 with measured AIC input 816.

This removes the uncommitted-DT loss risk from the kbuild workflow.  The
tracked DCUART source is byte-identical to Wallace's preserved copy before
consolidation.

## Upstream-shaped draft

- Linux branch: `codex/t6040-j614s-dt-series`
- base: `cf47872d10c9`
- tip: `f12292c2dc4b`
- tree: `ddcbf648474b24ce5749d954cbcfa97353c09ed4`
- mail: `patches/linux-t6040-j614s-dt-v1/`
- mail manifest: `SHA256SUMS`

The RFC is split into machine binding, core SoC/board DT, keyboard/trackpad
variant, and bring-up-only DebugUSB serial variant.  It includes the reduced
PMGR policy state and J614s trackpad firmware name.  It deliberately excludes
the local experimental DWC3 USB and internal ANS/storage nodes.

The serial variant records the measured contract: DockChannel UART is AIC
input 816, UART RX is BIT(1), and MTP RX is BIT(3).  Poll mode remains enabled
as the known-good fallback.

## Comparison with yuka

The refreshed `yuka/feature/m4-m5-minimal-device-trees` tip is
`f22f38b82716`.  Its T6040 work targets J773s and describes a different
4E+6P+6P CPU layout.  It does not provide the J614s board, its measured
14-active-core topology with disabled positional slot, the 214-domain PMGR
corpus, or the DockChannel IRQ/mask observations.  It is useful family
evidence but is not a substitute J614s DT.

## Validation

- All three DTBs compile in a clean, case-sensitive container:
  `t6040-j614s.dtb`, `t6040-j614s-kbd.dtb`, and
  `t6040-j614s-dcuart.dtb`.
- `git am` of the four mailed patches onto the recorded base produces the
  exact draft tree.
- strict `checkpatch.pl` reports zero errors, warnings, or checks when the
  generic new-file/MAINTAINERS reminder is ignored.
- `CHECK_DTBS=y` completes successfully.  Applying the existing
  `t6040-pmgr-t6041-bindings.patch` reduces output to known prerequisite
  schemas: T6040 AIC, T6040 watchdog, T8140 ASC mailbox, and the not-yet-
  upstream DockChannel mailbox/HID/serial bindings.  The DCUART-only generic
  `serial` child also needs a dedicated binding.  These are schema/RFC
  dependencies, not DTC failures.

No rig lease, chainload, MMIO access, enrollment, external post, or push
occurred.
