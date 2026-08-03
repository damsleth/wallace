# T6040 native USB2-only PHY slice: compile-only, DT-disabled

Date: 2026-07-29
Author: `sol`
Scope: offline code authoring and compile validation only
Hardware touched: **none**

## Result

An experimental Linux PHY provider now captures the smallest native T6040
USB data-path slice justified by paired evidence:

```text
patches/0001-phy-apple-add-experimental-T6040-USB2-only-slice.patch
```

It is deliberately **not runnable** and is not applied by
`scripts/t6040-kbuild.sh`. No DT node was enabled and no boot object was made.
The patch:

- maps only ADT-derived `bank0` and `bank1` resources;
- performs no ATC-register writes from probe;
- exposes only `PHY_TYPE_USB2`;
- refuses every mode except `PHY_MODE_USB_HOST`;
- reproduces the paired T6040 host sequence in exact RMW/delay/read order;
- performs the sequence at most once per driver instance;
- has no retries, escalation, SPMI, HPM, retimer, USB3/CIO4, DWC3-reset, PMU,
  charger, NVRAM, or persistent operation.

This is code scaffolding for independent review, not permission to apply its
MMIO writes to the rig.

## Why this is separate from the existing ATC driver

Yuka's exact T604x attempt using the new T8122-generation driver is retained
only as `feature/t604x-usb-broken` (`2849873b`). The paired T6040 USB2 event
bank also directly disagrees with that fallback: T6040 uses separate bank 1 at
`0x392800000`, while the fallback performs the event access relative to its
`core` window at `0x393000000`.

The new provider therefore matches only:

```text
apple,t6040-atcphy
```

and interprets the existing ticket-170 resource names `bank0` and `bank1`
without inheriting T8103/T8122 high-speed behavior.

## Exact implemented sequence

The source mirrors
`AppleT6040TypeCPhy::eusb2phy_init(false, false)` from
`done/2026-07-24-t6040-eusb2-init-sequence.md`:

1. five separate bank-0 signal RMWs set bits 14, 13, 12, 0, and 1;
2. sleep 10 ms;
3. clear bank-0 control bit 3;
4. delay 10 us;
5. clear control bits 0 and 1, separately;
6. set bank-1 event-control bits 3 and 0;
7. set bank-0 control bit 2;
8. clear bank-0 misc bits 29 and 30, separately;
9. delay 30 us;
10. read bank-1 status at `+0x20` and log it without retry/failure branching;
11. sleep 5 ms;
12. replace bank-0 USB mode bits 2:0 with host value 2.

Every hardware address comes from the bound DT resource. There is no fixed
CPU-physical address in the driver.

The Apple DWC3 glue calls `phy_set_mode(..., PHY_MODE_USB_HOST)` before its
core initialization powers on the generic PHY, so the callback ordering is
compatible with the host-only guard.

## Important non-features and gates

### No inverse

The paired evidence decodes the forward host sequence but not an exact inverse.
The provider therefore has no `power_off` callback rather than inventing one.
State is volatile and a full power cycle is the recovery boundary.

That is acceptable for offline scaffolding, but it prevents a ready/live claim.
Any future run is an ATC-PHY write experiment: exact review, fresh CJ approval,
attendance, passive bus-powered fixture, and power-cycle recovery are required.

### No VBUS

This code does not operate HPM2 and cannot source VBUS. Ticket 178's
independently reviewed status capture and a separately proved source-role path
remain prerequisites for a bus-powered stick.

### Current staging DT must remain disabled

Ticket 170's full-path staging fragment wires:

- USB2 and USB3 PHY consumers; and
- the ATC provider as DWC3 reset controller.

This minimal slice exposes neither USB3 nor a reset controller. A future
functional USB2-only test DT must explicitly remove the USB3 PHY and reset
relationships and retain only:

```text
phys = <&atcphy2_t6040 PHY_TYPE_USB2>;
phy-names = "usb2-phy";
```

That DT must be a separate reviewed candidate. Do not enable the current
full-path fragment unchanged.

Even with no driver ATC-register writes at probe, enabling the node can attach
its power domain; that platform action is another reason the disabled DT is
the correct current state.

## Validation

Linux base:

```text
c826f368c3e7  arm64: dts: apple: correct T6040 retimer ownership note
```

The generated patch applies cleanly to that base and carries CJ's author and
`Signed-off-by` identity.

Patch:

```text
bc7ba6419abd6915493db9c72bee731f39be363cc6ba2bb2c4284f2ff73411e3
```

It was applied to a fresh case-sensitive container clone, configured with
arm64 defconfig plus:

```text
CONFIG_PHY_APPLE_T6040_USB2=y
```

and compiled with:

```text
make -j8 ARCH=arm64 drivers/phy/apple/
```

The build completed without compiler warnings or errors. Exact object:

```text
dfba7f79e1938aa3d3096af38ae949ebc86bc0db5045457e2fa43cd516c6257c
drivers/phy/apple/t6040-usb2.o
```

No kernel Image, DTB, initramfs, m1n1 object, rig ticket, or enrollment object
was produced.
