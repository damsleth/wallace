# T6040 m1n1-shaped Linux ACM network candidate

Offline build and packaging only. No rig, SPMI, PCIe PHY, PMU, SMC, NVRAM,
firmware, APFS, Boot Policy, or enrollment action was performed.

## Why one more gadget shape is justified

Ticket 173 proved that Linux's T6040 DWC3 gadget reaches UDC state
`configured`, but this macOS host attached no class driver to Linux's generic
RNDIS, ECM, NCM, or ACM descriptors. The same host consistently binds m1n1's
gadget as two `/dev/cu.usbmodem*` devices.

The paired facts leave one bounded discriminator before closing the tether
path: reproduce the parts of m1n1's descriptor shape that ConfigFS controls.
`m1n1/src/usb_dwc3.c` declares:

```text
VID:PID            1209:316d
bDeviceClass       0x02 (CDC)
bDeviceSubClass    0
bDeviceProtocol    0
bcdUSB/bcdDevice   0x0200 / 0x0100
configuration      self-powered, bMaxPower=250 (500 mA at USB2)
topology           two ACM control/data interface pairs
```

The earlier Linux ACM smoke used Linux Foundation `1d6b:0104` and only one ACM
function. The new diagnostic changes identity, top-level class, power flags,
and topology together because that is the smallest ConfigFS representation of
the already-proven m1n1 device. It is not claimed byte-identical: Linux emits
the standard ACM header/call-management/ACM functional descriptors that
m1n1's minimal descriptor omits.

### Host-driver premise correction

The earlier ticket-173 verdict said generic host-side CDC support appeared
absent on Apple Silicon macOS. That is false. Direct inspection on the tether
host (macOS 15.3.2, Darwin 24.3.0) found these loaded:

```text
com.apple.driver.usb.cdc       5.0.0
com.apple.driver.usb.cdc.acm   5.0.0
com.apple.driver.usb.cdc.ecm   5.0.0
com.apple.driver.usb.cdc.ncm   5.0.0
```

Their installed Info.plists match generic CDC interface class/subclass
tuples—ACM `02/02/{00,01}`, data `0a/00`, ECM `02/06`, and NCM `02/0d`—with
no VID/PID whitelist. `AppleUSBCDC` also matches top-level device class
`0x02`. The failure is therefore specific to how macOS's composite parser
attached (or failed to attach) the tested Linux descriptors; it is not
evidence that the host lacks CDC drivers. The borrowed `1209:316d` identity
alone is not expected to fix it. The meaningful remaining delta is m1n1's
device-class/two-ACM topology.

If macOS publishes one or two modem nodes, a tty shell proves the data path and
PPP or SLIP can provide networking without PCIe, VBUS, or a USB host port. If
the UDC reaches `configured` but macOS still publishes no tty, a host libusb
bridge can claim the same bulk endpoints without relying on a class driver.
Only if both native attachment and the libusb bridge fail should this gadget
path close.

## Implementation

`scripts/t6040-usb-m1n1-acm-console.sh`:

- creates only one ConfigFS gadget;
- uses `1209:316d`, CDC device class, self-powered/500 mA configuration;
- links exactly `acm.GS0` and `acm.GS1`;
- binds only the already-proven `382280000.usb` UDC (with the existing
  single-UDC fallback);
- starts a shell on `ttyGS0` and leaves `ttyGS1` idle; and
- records UDC state/function and tty nodes in
  `/var/log/m1n1-acm-gadget.log`.

Its SHA-256 is:

```text
f4dc1fe66fb30a86528e5571c552ad17a6692a34da0e745bf714a3be8d7eb07b
```

## Host libusb fallback

`scripts/t6040-usb-bulk-pty.c` is a compile-checked host bridge for the exact
diagnostic product. It:

- enumerates `1209:316d` but requires product string
  `m1n1-shaped Linux ACM diagnostic` before claiming anything;
- therefore refuses m1n1's own proxy gadget despite the shared VID/PID;
- discovers the requested CDC data interface and its bulk endpoints from the
  active descriptor rather than hardcoding endpoint numbers;
- claims the paired control/data interfaces, sends standard 115200 8N1 line
  coding and DTR/RTS, and bridges USB bulk traffic to a new host PTY; and
- clears DTR and releases both interfaces on exit.

The source compiles on this host with `-Wall -Wextra -Werror`, and `--help`
plus the no-device refusal path run successfully:

```text
e4131b13b8bfa460b08e23638874b2d1f1c797ada255b8c5596a0a795f01beda
  scripts/t6040-usb-bulk-pty.c
```

Build command:

```sh
clang -std=c11 -D_DARWIN_C_SOURCE -Wall -Wextra -Werror \
  $(pkg-config --cflags libusb-1.0) \
  scripts/t6040-usb-bulk-pty.c -o /private/tmp/t6040-usb-bulk-pty \
  $(pkg-config --libs libusb-1.0) -lpthread
```

This bridge does not itself create a network interface. Its first proof is the
existing `ttyGS0` shell. A positive byte-stream result permits a separate
artifact adding target `pppd`; macOS already ships `/usr/sbin/pppd`, so PPP
over the bridge is then a concrete tether-network route.

`scripts/t6040-build-alpine-dwm.sh` now accepts an explicit
`T6040_USB_GADGET_SCRIPT` input while retaining the old script as the default.
It also drops fontconfig's build-root-specific caches. Those caches are
optional and regenerated on target; removing them made two full network-root
builds byte-identical:

```text
bd47a366271af60077acb2938d5c6aed73a33338803cbf0bcf80433bc74da788
  initramfs-alpine-dwm-m1n1-acm-wifi.cpio.xz
17,576,672 bytes compressed
69,996,240 bytes expanded
```

The initramfs is one XZ stream/block with CRC32, contains the exact script
hash above and all twelve paired BCM4388 C0/C2 `apple,mriya` files, and passes
`scripts/t6040-minilzlib-harness.sh`.

## Exact object

```text
/Users/damsleth/Code/linux-build-out/m1n1-b0-dwm-m1n1-acm-wifi-usb-diag.bin
sha256  8ef1da54546334f82783f1522c41a3eb51e1eedfe9ff50f8b7610bc73a049c56
size    31,817,728 bytes = 1942 * 16 KiB
```

Pinned members:

```text
ecd264a51f83673a2d0ff00bd7dd882a0c582f982c7a940f4a63b564f55b4796  m1n1-t6040-fbonly-v7.bin
217b4bd745e013400e29874f4ed4129b7f09650bc0387dbdb158536ec8389723  feature kernel XZ
11abca72b212362e1651a24f5dd07143b3b89956f8c00aaccec83d32b15df787  fixed MACSMC DTB
bd47a366271af60077acb2938d5c6aed73a33338803cbf0bcf80433bc74da788  initramfs XZ
3659a0da253c70590f30fb39a3455e2aa78213dda634acfa9e9d8eff916ebc27  bootargs record
```

The kernel is the already-staged 16 KiB observable feature kernel with
DockChannel support, SMC/HID, USB storage/UAS/usbnet, BRCMFMAC/CFG80211, and
the paired firmware built in. This gadget test uses `console=tty0`, not
`console=ttydc0`, because DebugUSB/KIS and the Linux gadget are mutually
exclusive on the DFU port.

The strict raw-object verifier passes. Its 130,243,183-byte runtime-payload
reserve is an informational sum of the expanded kernel, expanded initramfs,
DTB, and DT growth reserve; it is **not** the field constrained by the 128 MiB
policy. The guarded component is the initramfs alone: 69,996,240 expanded
bytes, below `MAX_INITRAMFS_EXPANDED=134,217,728`, and it independently passes
the minilzlib harness.

## Shared-path rejection caught during packaging

The common build output
`/Users/damsleth/Code/linux-build-out/t6040-j614s-dcuart-macsmc.dtb` had been
overwritten by Claude's concurrent build and no longer had the pinned
`11abca72…` hash. The first packaged object was therefore rejected without
being proposed. The immutable 52,127-byte DTB was extracted from the prior
strict-verified ticket-181 object, re-hashed to `11abca72…`, saved as
`t6040-j614s-dcuart-macsmc-11abca72.dtb`, and used for the final object.

## Gate

Ticket 183 pins the final object and is proposed only. Claude must independently
review the ConfigFS-vs-m1n1 comparison, exact initramfs, immutable member
hashes, and strict verifier result. CJ must approve before any chainload.

One run is decisive for the native-driver shape and the bulk fallback:

- PASS: macOS creates one or two new `/dev/cu.usbmodem*` nodes and opening the
  first reaches the target shell;
- FALLBACK PASS: if no modem node appears, the product-gated libusb bridge
  reaches the same `ttyGS0` shell through its host PTY;
- NEGATIVE: the Linux UDC is configured but neither native tty nor libusb
  bulk traffic reaches `ttyGS0`;
- stop/recover on upload failure, reset, lost panel, or missing gadget; and
- restore a quiescent `Running proxy` before releasing the rig.
