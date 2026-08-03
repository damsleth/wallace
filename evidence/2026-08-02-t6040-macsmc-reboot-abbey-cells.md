# T6040 macsmc-reboot node: J614s abbey PMU cells

Date: 2026-08-02

Scope: offline ADT decode and DT update only. No SPMI/PMU/SMC transaction and
no rig lease.

## Result

`dts/t6040.dtsi` now has the missing `apple,smc-reboot` child and the five
J614s abbey PMU nvmem cells needed by the upstream layout:

| Cell | J614s offset | Width/bits | ADT basis |
|---|---:|---|---|
| `pm_setting` | `0x2001` | 1 byte | `info-pm_setting = 0x2001` |
| `boot_stage` | `0xf801` | 1 byte | `info-leg_scrpad + 1` |
| `boot_error_count` | `0xf802` | low nibble | `info-leg_scrpad + 2` |
| `panic_count` | `0xf802` | high nibble | `info-leg_scrpad + 2` |
| `shutdown_flag` | `0xf80f` | bit 3 | `info-leg_scrpad + 0xf` |

The already present RTC cell remains at `0x2100`, six bytes.

This directly fixes the current probe failure: `macsmc-reboot` is an MFD child
even without an OF node, but its driver intentionally returns `-ENODEV` when
`pdev->dev.of_node` is absent. The new child supplies that node and its four
reboot-consumer cells. `pm_setting` is part of the measured PMU layout, as on
the upstream T6030/T6031 abbey-family shape, but the current reboot binding
references only `shutdown_flag`, `boot_stage`, `boot_error_count`, and
`panic_count`.

## Primary evidence

Captured ADT:

```text
/Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.adt
size 606208 bytes
SHA-256 7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84
```

Exact node:

```text
/arm-io/nub-spmi0/spmi-abbeyL1
compatible = "pmu,spmi", "pmu,abbey"
SID = 0x0e
info-pm_setting = 01 20 00 00 = 0x2001
info-rtc_scrpad  = 00 21 00 00 = 0x2100
info-clock_offset = 00 21 00 00 06 00 00 00 = <0x2100 0x6>
info-leg_scrpad  = 00 f8 00 00 = 0xf800
```

The ADT blob parses to 596,432 bytes of nodes followed by 9,776 zero padding
bytes. No value was inferred from the padding.

## Derivation, not copying

The Apple legacy boot record has stable field positions relative to the
ADT-provided legacy scratchpad base:

```text
boot stage       = base + 0x01
error/panic byte = base + 0x02 (low/high nibbles)
shutdown flag    = base + 0x0f, bit 3
```

For this machine `base = info-leg_scrpad = 0xf800`, producing
`0xf801/0xf802/0xf80f`.

This is independently consistent with upstream T6030/T6031, which use the
same `info-pm_setting = 0x2001`, `info-rtc_scrpad = 0x2100`, and legacy base
`0xf800`. It is materially different from the old T600x/T602x maverick layout
(`pm_setting 0x1405`, RTC `0x1411`, legacy base `0x6000`) and from the older
stowe-style `0xf701/0xf702/0xf70f/0xf801/0xf900` values. Those offsets were not
copied.

## DT shape

The `apple,smc-reboot` child now references:

```text
nvmem-cells = shutdown_flag, boot_stage, boot_error_count, panic_count
nvmem-cell-names = "shutdown_flag", "boot_stage",
                   "boot_error_count", "panic_count"
```

This matches the local binding and `macsmc-reboot.c`. The driver writes
`boot_stage = 0x30` at probe, writes clean-shutdown state during reboot/poweroff
prepare, clears nonzero error/panic counters, and finally issues the existing
SMC `MBSE` restart/poweroff operations. These are within CJ's standing
`smc_reboot` exception; no charger or voltage-rail cell is described.

## Static verification

The full daily-driver board DTS preprocesses and compiles with `dtc`. The only
warning is the pre-existing `/soc/serial` simple-bus warning. Decompiled output
contains:

```text
pm-setting@2001               reg = <0x2001 0x1>
rtc-offset@2100               reg = <0x2100 0x6>
boot-stage@f801               reg = <0xf801 0x1>
boot-error-count@f802,0       reg = <0xf802 0x1>; bits = <0 4>
panic-count@f802,4            reg = <0xf802 0x1>; bits = <4 4>
shutdown-flag@f80f,3          reg = <0xf80f 0x1>; bits = <3 1>
apple,smc-reboot              four phandle references in binding order
```

Verification DTB SHA-256:

```text
bed2c7ae5b397dedd12d553bdd4ecb8c5d1165eb809b09adda74cbeca1a5afcf
```

It is a temporary compile artifact, not a rig image.

## Adversarial note

`dts/t6040-j614s-dcuart-smc.dts` is an older standalone diagnostic DTS and
still documents/copied stowe offsets (`0xf701`, `0xf702`, `0xf70f`, `0xf801`,
`0xf900`). It should not be used as J614s PMU ground truth. The daily-driver
board includes `dts/t6040.dtsi`, whose newly measured abbey layout is the one
validated above.
