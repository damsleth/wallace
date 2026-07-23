# T6040 ATC PHY/HPM upstream checkpoint (ticket 023)

Date checked: 2026-07-23

Offline only. No rig, MMIO, SPMI, PMU, charger, or target-memory access was
performed.

## Upstream correction

The old watch pointer is not an active T6040 implementation:

- AsahiLinux/m1n1
  [`atcphy-new-tunables`](https://github.com/AsahiLinux/m1n1/tree/atcphy-new-tunables)
  remains at `9657a52e9183d09563fb57396fb36342d7b263d1`, dated 2025-01-16.
  Against current main it is 353 commits behind and seven ahead. Its ATC-only
  change reorders older tunables; it contains no `t6040`, `t6041`, `CIO4`, or
  T6040 `USB2PHY` mapping.
- Current m1n1 main has since grown a separate T8122 table and the
  `apple,tunable-common-b` transition, but still routes every non-T8122 PHY to
  the older table. Its fuse table has no `atc-phy,t6040` entry. A T6040 node
  therefore fails required-property lookup and takes the deliberate USB2-only
  cleanup path.
- Published AsahiLinux/Linux ATC branches checked through
  [`sven/atcphy`](https://github.com/AsahiLinux/linux/tree/sven/atcphy)
  (`bb58cc6399a58218b8b5204a9fadf26f07c7f0f3`, 2025-05-17) match T6000,
  T6020, T8103, and T8112—not T6040. The Wallace `asahi-wip` base is narrower
  still: its `drivers/phy/apple/atc.c` match table contains only
  `apple,t8103-atcphy`.
- Linux PR
  [515](https://github.com/AsahiLinux/linux/pull/515) is a useful USB2 fallback
  fix when an already-supported PHY is in DP/DUMMY mode. It neither supplies a
  T6040 compatible nor solves HPM wake/orientation or T6040 register mapping.

The July M3 result remains architectural evidence only: waking its SPMI HPM,
waiting, and fixing long regmap transfers led to real enumeration. None of
those results publish the J614s register/programming contract.

## Exact J614s right-port contract

Source:

```text
/Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.adt
SHA-256 7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84
```

The physical right connector is `usb-drd2`. Its path is:

```text
nub-spmi-a1/hpm2 (SN201202x)
            │ acio-parent
            ▼
          acio2 ◄──────── atc-phy-parent ──────── atc-phy2
            │                                      │
            └──────── parent fabric ───────── usb-drd2
```

The captured properties are:

- `hpm2`: compatible `usbc,sn201202x,spmi`, `acio-parent = 196`,
  child IRQs 11/17/19, behind `/arm-io/nub-spmi-a1`.
- `nub-spmi-a1`: compatible `aapl,spmi`, three 16 KiB register banks at
  `0x309198000`, `0x309194000`, and `0x309190000`.
- `acio2`: compatible `acio,v2`, phandle 196, `atc-phy-parent = 325`.
- `atc-phy2`: compatible **only** `atc-phy,t6040`, phandle 325, 44 ADT
  register entries, plus generation-specific `tunable-host`,
  `tunable-device`, `tunable_USB2PHY_{HOST,DEV,DFLT}`, `CIO4PLL_CORE`,
  `AUS40CMN_SHM`, and new lane/UC records.

The four T6040 PHY instances share the same 44-bank layout with per-instance
base shifts. This proves that borrowing the old monolithic resource map or
substituting a T8122 compatible is invalid. The tunable record offsets are
offsets *within* logical buckets; they do not identify which of the 44 register
banks is the matching Linux resource. That missing name→bank/bucket contract is
still the central static blocker.

## What is already known to work

Ticket 063 proved that the right-port USB DARTs, DWC3 wrapper/core, interrupt,
and xHCI setup are sufficient to create stable USB2 and USB3 root hubs. The
attached bus-powered USB-C flash drive never appeared. The candidate DT has no
HPM, connector graph, PHY provider, `phys`, or `phy-names`, so no component
establishes CC/orientation, eUSB2 repeater state, VBUS/host signaling, or
T6040 PHY mode.

Current m1n1 detects the M3/M4 SPMI topology and calls its legacy
`usb_phy_bringup()` path, but its own comment describes this only as “get USB
going for now by just bringing up the phys.” It does not turn the target ADT
records into a Linux-owned, reproducible HPM/PHY handoff.

## Minimal future implementation boundary

A reviewable T6040 host-mode series needs all of these, not just a compatible
string:

1. Apple SPMI controller support for the target `aapl,spmi` register/IRQ
   layout.
2. An SN201202x HPM/Type-C path that reports cable attach, role, and
   orientation, including the proven wake-delay/long-transfer lessons.
3. A T6040 ATC PHY resource map naming the 44 ADT banks and mapping every
   required tunable source to a proven bucket base/size.
4. Connector/mux/switch graph plus DWC3 `phys`/`phy-names`.
5. A safe ownership/initialization sequence: HPM/repeater and USB2 host state,
   DWC3, then USB3/pipehandler, with explicit rollback.

The project must not synthesize steps 1–3 from addresses alone. HPM access is
SPMI state mutation and remains forbidden until an upstream-derived exact
sequence has been separately reviewed and approved.

## Decision

Keep ticket 023 open as a broad upstream watch, but retire
`atcphy-new-tunables` as the sole “active” pointer. Watch m1n1 main, Linux ATC
branches/PRs, and #asahi-dev for an explicit T6040 compatible, 44-bank resource
map, SN201202x path, or published bucket bases.

No further unpowered USB-host rerun is useful. A powered/self-powered fixture
would still be a valid no-code discriminator when available; it is not
available now. The autonomous bootable-build path therefore remains the
storage-free B0 Alpine RAM image.

