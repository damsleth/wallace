# T6040 USB: Yuka branch review and the five-window fallback no-go

Date: 2026-07-29
Author: `sol`
Scope: host-only Git and source comparison; no rig or hardware access

## Result

Yuka has already tried the obvious shortcut: describe T604x with the same
five logical ATC resources as T8122 and bind it through
`apple,t8122-atcphy`. The exact commit is deliberately retained on a branch
named `feature/t604x-usb-broken`, and its commit message says the attempt does
not work because T604x introduced Thunderbolt 5/CIO4 and has substantially
fewer tunables.

The active development branch `feature/m4-usb` contains T8132 and T8140 USB
descriptions but does **not** contain the T604x commit. Therefore:

- do not add `apple,t8122-atcphy` or `apple,t8103-atcphy` as a T6040 fallback;
- do not turn ticket 170's five-window resemblance into a compatibility claim;
- retain the exact 44-bank T6040 inventory disabled;
- treat USB2 and USB3 separately: the paired T6040 USB2 sequence is small and
  exact, while USB3 still needs native CIO4-generation support.

## Exact upstream-development state

Fetched directly from Yuka's configured Linux remote:

```text
feature/m4-usb:
82e183da77d9df414086867237b1d167641744ae

feature/t604x-usb-broken:
2849873b1db0b59ca38e2f831a8052dcfed81309

common parent:
5f7d6dfb3a26c8534e4491c9e7f76aa69528907e
```

Only `yuka/feature/t604x-usb-broken` contains `2849873b`. The active branch
diverges at the common parent and proceeds with:

```text
76d3c59acc65  dts: apple: t8132: Add usb/atcphy nodes
82e183da77d9  dts: apple: t8140: Add usb/atcphy nodes (single-port, usb2-only)
```

The abandoned T604x commit is:

```text
2849873b1db0  BROKEN: dts: apple: t604x: Add usb/atcphy nodes
```

Its own message says:

```text
Does not work yet, t604x introduced Thunderbolt 5 support, uses CIO4 instead of
CIO3 and has way less tunables, so maybe it even needs a new atcphy compatible.
```

## What the broken T604x attempt did

For right-port `atcphy2`, Yuka used:

```text
compatible = "apple,t6041-atcphy", "apple,t8122-atcphy";

core        0x393000000 / 0x4c000
lpdptx      0x393050000 / 0x8000
axi2af      0x390000000 / 0x8000
usb2phy     0x392a90000 / 0x4000
pipehandler 0x392a84000 / 0x4000
```

The CPU-physical bases agree with Wallace's ADT-derived translation and show
that the earlier five-window mapping was not numerically wrong. The failure is
the generation/interface assumption: those windows were paired with the T8122
driver behavior despite the T6040 CIO4 and tunable differences.

The attempt also described the SPMI SN201202x controller and Type-C connector
graph. That is useful upstream direction, but it does not bypass Wallace's
endpoint-scoped SPMI safety policy or prove the T6040 source/VBUS transition.

## Direct USB2 mismatch

The T8122 driver support comes from:

```text
84356ad7382e  phy: apple: atc: Add initial M3 series support
```

Its USB2 path is close to, but not identical with, the paired T6040
`AppleT6040TypeCPhy::eusb2phy_init(false, false)` sequence decoded in
`evidence/2026-07-24-t6040-eusb2-init-sequence.md`.

The decisive mismatch is the event bank:

- paired T6040 writes and reads bank 1 at CPU-physical `0x392800000`
  (`B1+0x0 |= 0x9`, then read `B1+0x20`);
- the T8122 path performs its event control through `core_set32()` at offset
  zero, which the broken T604x DT maps at `0x393000000`.

The paired path also has an exact 10 ms wait after its five host-signal RMWs,
a 30 us wait before the bank-1 status read, and a 5 ms wait before selecting
USB mode 2. The fallback does not reproduce those boundaries. Conversely, the
fallback's ordinary power-on path forces USB2 signal bits 2 and 3 in addition
to the paired host path's exact bits 14, 13, 12, 0, and 1.

This is enough to reject the fallback even before considering CIO4/USB3.

## Probe-time write hazard

Binding the current driver is not a read-only discriminator.
`atcphy_probe_finalize()` immediately:

1. asserts the DWC3 reset through the pipehandler;
2. executes the USB2 power-off sequence;
3. powers off the ATC core;
4. configures the pipehandler.

Therefore a guessed compatible cannot be enabled merely to observe probe
output. It would issue generation-assumed MMIO writes before any USB device
test.

## Safe next implementation boundary

A native T6040 implementation should have a distinct hardware type and must
not inherit T8122 high-speed behavior. The smallest evidence-backed first
slice is USB2-only:

- map the paired bank 0 and bank 1 resources separately;
- reproduce the exact paired host sequence, ordering, waits, and status read;
- leave CIO4/USB3, retimers, and unidentified tunables disabled;
- keep the DT and driver unbound until the HPM source/VBUS precondition has an
  independently reviewed, attended plan.

This report does not authorize an ATC write or a rig run.
