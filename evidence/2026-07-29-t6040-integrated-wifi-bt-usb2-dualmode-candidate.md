# Integrated dual-mode WiFi/Bluetooth + native USB2 candidate

Date: 2026-07-29  
Agent: sol  
Ticket: 189 (offline independent review only)

## Outcome

The proven WiFi/Bluetooth desktop path and the new native T6040 right-port
USB2-only path now coexist in one strict-verified dual-mode object:

```text
/Users/damsleth/Code/linux-build-out/m1n1-dwm-wifi-bt-ppp-usb2-native-dualmode-no-hidf.bin
size   35,356,672 bytes = 2,158 * 16 KiB
sha256 d867bcda50279c4671361c87080537de0970cd5035503c4afd88e02d2c56707b
```

This is the closest current offline candidate to the near-term combined
artifact. It is not runnable or enrollable yet. Its USB2 PHY callback performs
volatile ATC/eUSB2 writes, and the separate HPM status/VBUS path is still
unresolved. Ticket 189 is an exact-review request, not live authorization.

The corrected kernel retains the already-proven DockChannel HID type fix, so
the internal keyboard path is not regressed. The object deliberately uses the
no-HIDF RAM root. The generic bounded DockChannel firmware-request code is
compiled, but neither the RAM root nor the kernel contains
`apple/tpmtfw-j614s.bin`; therefore the request fails before any upload and a
successful trackpad HIDF write is impossible. Combining the unreviewed USB2
PHY transition with ticket 126's separately gated HIDF payload would put two
new write boundaries in one first boot; the build harness refuses that
composition.

## Exact object members

```text
ee58fa400298ad605993e0aa07289354af06da27ff7668345f2527b9b08b767c  m1n1-t6040-pcie-dualmode-window10-04e8829c.bin
c89aa203a245db52e0d19b2b4410817ca3ea2b56048cf7219508eec1b91ab93b  Image-macsmc-hid-type-fix-nbcon-ppp-usb2-native-right.xz
934dd7b2cdced35650ef3afa0545ee4b5ad34c2e6707629c2e8ad9eca88e3cfb  t6040-j614s-dcuart-wifi-usb2-native-right.dtb
0ff9415f931d30587852044112f31e5e65d69c32de928a950706269412e3ca7a  initramfs-alpine-dwm-wifi-bt-ppp.cpio.xz
7ce05abd2da1a13e6c89209a9c5dba1279d0860b3951d7995c838ef30ded0ca0  chosen.bootargs record
```

The prefix is the reproducible 10-second DTR-gated m1n1 shape with the
live-proven upstream T6040 PCIe `BIT(4)` path. The RAM root retains Alpine,
dwm, the Norwegian keyboard, WiFi association, BlueZ, and dual-ACM PPP, and
contains no `apple/tpmtfw-j614s.bin`.

Boot arguments:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 console=ttydc0 ignore_loglevel rdinit=/sbin/init
```

The strict verifier reports a 16 KiB-page kernel, exact member hashes, and
zero remainder after 16 KiB object alignment.

## Reproducible integrated kernel

Two builds from distinct empty container build directories produced identical
raw outputs:

```text
3caa0f781c646e4161b3f3b8f805072fff7663c8dcf7cfab576daf9f46e28e9e  Image-macsmc-hid-type-fix-nbcon-ppp-usb2-native-right
1ea47f23c397c8219b42f741fe6e4122c9b79d7b070ab74ce68c9e41b43413cf  System.map-macsmc-hid-type-fix-nbcon-ppp-usb2-native-right
221666c6d31eefe44c7d15e83400e04f37567a32d617b0b795ccb5eed809e543  config-macsmc-hid-type-fix-nbcon-ppp-usb2-native-right
934dd7b2cdced35650ef3afa0545ee4b5ad34c2e6707629c2e8ad9eca88e3cfb  t6040-j614s-dcuart-wifi-usb2-native-right.dtb
```

Build flags:

```text
DOCKCHANNEL=1
DOCKCHANNEL_NBCON=1
HID_TYPE_FIX=1
T6040_INTEGRATED=1
T6040_PPP=1
MACSMC=1
WIFI=1
PCIE=1
USB_HOST=1
USB_HOST_PORT=right
T6040_USB2_NATIVE=1
```

`System.map` confirms the linked paths for the native USB2 power callback,
Apple PCIe, brcmfmac PCIe, BCM4377 Bluetooth, xHCI, USB storage, UAS,
DockChannel atomic TX, and PPP async.

The kernel XZ member is a single-stream, single-block CRC32 member:

```text
compressed    12,227,380 bytes
uncompressed  56,068,608 bytes
dictionary    64 MiB
```

m1n1's own `minilzlib` decoded it successfully. The unchanged no-HIDF RAM root
also retains its prior XzDecode PASS and expands to 91,717,760 bytes, below the
approximate 128 MiB limit.

## Compiled-DT scope

The integration DT includes the live-proven WiFi board and adds only:

- DARTs `0x392f00000` and `0x392f80000`;
- DWC3 `0x392280000` in host/high-speed mode;
- native PHY bank 0 `0x392a90000`;
- native event bank 1 `0x392800000`; and
- a single `PHY_TYPE_USB2` consumer relationship.

The decompiled DTB also retains the proven WiFi antenna SKU `X3` and SMC
endpoint-power lines `gP13`/`gP19`.

It does not add a USB3 PHY, ATC reset relationship, I2C6/retimer node, Type-C
role switch, another port, or HPM controller. All addresses use the translated
CPU-physical `0x3xx` form.

## Safety and remaining gates

The fall-through path performs the already-proven PCIe PHY initialization and
Linux SMC endpoint-power writes. It additionally causes the native USB2 PHY
`power_on` callback to perform the reviewed-offset forward eUSB2 sequence.
That sequence has no byte-preserving inverse; a power cycle is the recovery
boundary.

There is no HPM/SPMI transaction, USB3/retimer path, PMU/charger/NVRAM/flash
write, persistent firmware operation, blind offset scan, or trackpad HIDF
payload in the object. Although the generic bounded request code is present,
the exact board firmware file is absent, so it cannot reach its upload.

Before any live use:

1. another agent must independently review ticket 189's exact sources,
   translated addresses, DT composition, hashes, XZ members, and dual-mode
   prefix;
2. ticket 178 must independently pass review and capture the right HPM status;
3. VBUS/source-role handling must be proved separately if the status requires
   it; and
4. a new exact attended rig manifest must receive CJ approval.

Only after USB2 enumeration succeeds should the separately reviewed trackpad
HIDF path be folded into the final daily-driver artifact.
