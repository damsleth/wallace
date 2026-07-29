# T6040 native USB2 right-port candidate: reproducible build

Date: 2026-07-29  
Agent: sol  
Ticket: 188 (offline independent review only)

## Result

The first native T6040 USB2-only kernel/DT candidate now builds cleanly and
reproducibly. Two builds from separate empty container build directories
produced byte-identical `Image`, `System.map`, `.config`, and DTB.

This is not a runnable rig ticket. The PHY `power_on` callback performs
volatile ATC/eUSB2 MMIO writes and has no inverse sequence, so exact independent
review and CJ attendance are required before any live use. A power cycle is the
recovery path. Right-port HPM status, power role, and VBUS sourcing remain a
separate prerequisite; this candidate does not touch HPM or source VBUS.

## Exact artifacts

Build output directory: `/Users/damsleth/Code/linux-build-out`

| Artifact | SHA-256 |
|---|---|
| `Image-usb2-native-right-nbcon` | `40670d81183c00b5bdd709446bd5f6ef169e5969e3b759ae845a4ea72797cf6c` |
| `System.map-usb2-native-right-nbcon` | `f4ffb3ee802e7d750aeb7a6e0b4cfe9fad6215da28efe856eb80e67705e7487b` |
| `config-usb2-native-right-nbcon` | `3d337e18df72cccf18f32963dbea3d1c715e88c3dd1b367ca3e6c401ff3af432` |
| `t6040-j614s-dcuart-usb2-native-right.dtb` | `0c39cf06139dcc3828e5cd730d4e1871544e20d9a87a9bc67f8f569e7edd9ceb` |
| `Image-usb2-native-right-nbcon.xz` | `50d234497cec0a9f69708182bfa1aea92cdc83977903d090cca01ac2a6c05df8` |

The XZ member is 11,412,828 bytes, expands to 53,303,808 bytes, and is a
single-stream, single-block CRC32 member with no BCJ filter. m1n1's own
`minilzlib` harness decoded it successfully:

```text
Uncompressing... 11412828 bytes uncompressed to 53303808 bytes
```

## Build selection and fail-closed gates

`T6040_USB2_NATIVE=1` is accepted only together with `USB_HOST=1` and the
right-port selection. It selects
`t6040-j614s-dcuart-usb2-native-right.dts`, applies the experimental
`PHY_APPLE_T6040_USB2` patch, forces the native PHY and DWC3/xHCI/storage/UAS
consumers built-in, and asserts those settings before compiling.

The two clean builds used:

```text
DOCKCHANNEL=1
DOCKCHANNEL_NBCON=1
USB_HOST=1
USB_HOST_PORT=right
T6040_USB2_NATIVE=1
NPROC=8
```

Only the build directory differed. Exact comparisons passed for all four raw
outputs.

`System.map` contains the expected linked paths:

```text
t6040_usb2_power_on
dwc3_probe
xhci_plat_probe
uas_probe
usb_stor_probe1
apple_dockchannel_send_atomic
```

## Compiled-DT audit

The decompiled DTB has exactly the intended right-port CPU-physical resources:

- DARTs `0x392f00000` and `0x392f80000`, enabled.
- DWC3 `0x392280000`, enabled with `dr_mode = "host"`,
  `maximum-speed = "high-speed"`, and only `usb2-phy`.
- Native PHY compatible `apple,t6040-atcphy`.
- Bank 0 `0x392a90000`, size `0x4000`.
- Bank 1 `0x392800000`, size `0x4000`.
- Power domain `ps_atc2_usb`.

The board overlay introduces no USB3 PHY relationship, ATC reset-controller
relationship, retimer/I2C6 node, role switch, or left-port enablement.
References to disabled peripheral-mode DWC3 instances inherited for other
ports remain disabled.

The addresses are CPU-physical `0x3xx` values, not untranslated ADT `0x1xx`
bus addresses.

## Safety boundary

The driver performs no ATC write during probe. Its only write path is the
generic PHY `power_on` callback, which requires USB host mode and is invoked by
the enabled right-port DWC3 consumer. It implements the separately decoded
T6040 eUSB2 host sequence against only bank 0 and bank 1.

This artifact does not contain any HPM/SPMI transaction, PMU/charger/NVRAM
write, firmware upload, USB3/ATC retimer path, generic offset scan, or
persistent operation. It nevertheless performs reviewed-offset PHY MMIO
writes when booted. Therefore ticket 188 asks another agent to re-derive the
offsets/order, address translation, DT scope, and exact artifacts before a
separate attended rig manifest can be proposed.

## Next gate

1. Independent exact review of ticket 188.
2. Independently review and run ticket 178 to capture the right HPM status.
3. Decode and separately review a paired-evidence power-role/VBUS action if the
   status shows one is needed.
4. Only then compose a bounded attended USB2 enumeration/storage experiment.

