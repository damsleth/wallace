# Ticket 170: exact right-port USB3 data-path DT, staged fail-closed

Author: `sol`
Scope: offline DT authoring and paired-kext/ADT inspection only
Hardware touched: **none**

## Result

The right-port data path now has a compile-checked staging description in both
the Linux tree and Wallace:

- `linux/arch/arm64/boot/dts/apple/t6040-usb3-right-data-path.dtsi`
- `linux/arch/arm64/boot/dts/apple/t6040-j614s-dcuart-usb3-right-data-path-staging.dts`
- mirrored byte-for-byte under `wallace/dts/`

This is deliberately **not a runnable DTB** and is not included by a release
board DTS. It records the exact T6040 resources while leaving the ATC PHY,
I2C6 retimer bus, all three retimer children, and the existing DWC3 node
disabled.

The fragment adds:

- all 44 `/arm-io/atc-phy2` register banks, in captured ADT order, translated
  through `/arm-io/ranges` by `+0x200000000`;
- the native-only `apple,t6040-atcphy` compatible, with **no**
  `apple,t8103-atcphy` fallback;
- `#phy-cells`, `#reset-cells`, orientation/mode-switch declarations, and the
  ATC2 USB power domain;
- the missing DWC3 `resets`, USB2/USB3 `phys`, `phy-names`,
  `usb-role-switch`, and host default-role relationship;
- I2C6 at CPU-physical `0x429028000`, IRQ 1581, and the exact ADT `atcrt`
  inventory at `0x18`, `0x19`, and `0x1a`.

The live-proven DWC3 and DART definitions remain untouched:

- DWC3 `0x392280000`;
- DARTs `0x392f00000` and `0x392f80000`;
- IRQs, stream IDs, and `ps_atc2_usb` from the successful root-hub smoke.

## Correction: the T602x five-window fallback is unsafe on T6040

Do **not** use:

```dts
compatible = "apple,t6040-atcphy", "apple,t8103-atcphy";
```

The current Linux driver matches only `apple,t8103-atcphy`. Its probe
immediately resets/powers down the PHY and accesses the old five-resource
layout. J614s instead has a native 44-bank layout, T6040-specific encoded
bank tunables, and holes/overlaps that are not represented by the T8103
monolithic `core` mapping. Adding the fallback would turn an unproved layout
assumption into real PHY MMIO writes during probe.

The paired `AppleT6040TypeCPhy` kext independently proves that its 44-entry
`_sRegisters` table matches ADT `reg[0]..reg[43]` exactly and that T6040
tunable records encode a bank index. The staging DT therefore preserves all
44 banks by stable numeric name instead of pretending that the old five
windows are an established ABI.

This means ticket 170 is **not DT-only to functionality**: a native T6040
ATC PHY driver/binding, or an independently reviewed m1n1 handoff, remains a
runtime prerequisite.

## Retimer decision (corrected 2026-07-29)

The ADT says only `atcrt`; it does not identify a Parade PS8830/PS8833 or any
other supported part, so binding a guessed upstream driver would be wrong.
The ADT also provides no graph phandle from `usb-drd2` to an `atcrt` child.

A complete follow-up decode of both paired drivers refutes the earlier claim
that `AppleHPMInterface::enableOptions()` calls the `atcrt%u` service for a
retimer-mode transition:

- AppleHPM's cached `atcrt%u` pointer is used only to publish/increment a panic
  counter and deliver notification `0xe0000130`;
- `enableOptions()` never accesses that pointer and performs no I2C transfer;
- the paired `AppleTypeCRetimer` normal start/message/state/power paths monitor
  health and crash state rather than program USB lane mode.

Exact functions, cross-references, hashes, and the bounded conclusion are in
`evidence/2026-07-29-t6040-atcrt-owner-correction.md`.

The three exact children remain disabled inventory because their physical
power, clock, reset, and firmware ownership is still unknown. However, lack
of an `AppleTypeCRetimer` Linux clone is not a demonstrated prerequisite for
an independently reviewed USB2 data-path attempt.

## Validation

The compile-only board was preprocessed and compiled with the kernel headers
and host `dtc`, then round-tripped:

- DTB SHA-256:
  `ac2492de06ff0848eee1e74b8c84725d7ed1297268f18471860404c65fcaaa17`
- ATC `reg` tuple count: 44;
- every compiled tuple compares byte-for-byte with the captured ADT after the
  `+0x200000000` translation;
- retimer addresses compile as `0x18`, `0x19`, `0x1a`;
- compiled status is `disabled` for ATC PHY, I2C6, and DWC3;
- only warning is the pre-existing `/soc/serial` simple-bus warning from the
  dcuart staging board.

Source hashes:

- fragment:
  `1961d96570fea3a29050768f0cc1afab167bcf86b9cbded55892b29c8ca6ff03`
- compile-only board:
  `372eec8782d45cab9e57fbd6d9894699ea39a840b0ac5aa58e1ac18ebf535054`

Both Linux/Wallace mirror pairs compare byte-for-byte. `git diff --check`
passes in both repositories.

## Remaining gate

Do not build this into the daily-driver object and do not schedule rig time
for it. The next functional step is one of:

1. implement and independently review a native 44-bank T6040 ATC PHY driver,
   starting with the decoded bank-0/bank-1 eUSB2 host sequence, while leaving
   the unidentified `atcrt` children disabled; or
2. have an attended, separately reviewed m1n1 transition establish HPM role,
   VBUS, and ATC host state before Linux, with rollback.

The R3/R4 artifacts reviewed today do not satisfy option 2: `SWDF` changes
data role, not source/VBUS role.
