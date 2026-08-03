# T6040 graphical WiFi + PPP network candidate

Date: 2026-07-29
Author: sol
Rig use: none; the enrolled rollback proxy was left untouched

## Outcome

One byte-reproducible, strict-verified **chainload candidate** now combines:

- the exact m1n1 PCIe loader and WiFi DTB that produced live `wlan0`/`hci0`;
- Alpine + dwm + the working Norwegian keyboard setup;
- `iw`, `wpa_supplicant`, and a RAM-only association helper;
- the live-proven BCM4388 rev-6 firmware alias;
- dual-ACM PPP over the DFU/tether port as an independent network fallback;
- the feature kernel's USB storage/UAS/usbnet stack.

The object is:

```text
/Users/damsleth/Code/linux-build-out/m1n1-dwm-wifi-ppp-network.bin
size   33,439,744 bytes = 2,041 * 16 KiB
sha256 32a4afe183e5a6f50518bda1fc698c29b2f01ff7db8ce26e0936652c4f55f837
```

Two complete compositions from independently reproduced kernel and initramfs
members are byte-identical. `t6040-raw-object-verify.py --strict` passes.

This is deliberately **not an enrollment candidate**. Its m1n1 member is the
live-proven PCIe V1 diagnostic loader, not a reviewed daily-driver build with
the required 10-second proxy door. Use it only for a separately reviewed,
attended tethered chainload. The final enrolled object still needs the proven
PCIe delta folded into the dual-mode source shape.

## Exact members

```text
28a4e0cf812d48ab40337be9578381d66c61b5ac91730bb0b950930f77a93299  m1n1-t6040-pcie-V1-upstream-04e8829c.bin
21a8651a16f65c9e65db9ee888703ce8621bdb28508c5c19c506e8bc1ea52e0e  Image-macsmc-hid-type-fix-nbcon-ppp-wifi-fw.xz
0afb98ae31760309f1d28f0b84f313991f8460856685905bd52a0a6919d2fc7e  t6040-j614s-dcuart-wifi.dtb
9326edba565ae712bcf6187e619942b3243d35011f6f2a5274a513a8f57a4422  initramfs-alpine-dwm-wifi-ppp-network.cpio.xz
7ce05abd2da1a13e6c89209a9c5dba1279d0860b3951d7995c838ef30ded0ca0  chosen.bootargs record
```

Bootargs:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 console=ttydc0 ignore_loglevel rdinit=/sbin/init
```

The m1n1 member is source commit
`04e8829cbc47ff6a05e872dd329cdabb83554ce0`, previously double-built and
live-proven. The DTB is the exact 55,681-byte artifact used for the
2026-07-29 WiFi milestone.

## Kernel reproduction and feature proof

Linux source:

```text
ea5c9c1f7c934d2a84b9bf0a25e80c5a72254954
```

The isolated build used a frozen copy of the committed kbuild script plus one
local-only configuration delta:

```text
a28a4b5a20de120aea8df1875bf7c522ccca955235305121f93b22dee68cc8f9  t6040-kbuild.sh
```

That delta adds and asserts only:

```text
CONFIG_PPP=y
CONFIG_PPP_ASYNC=y
```

Both clean builds produced:

```text
04becbcea047a0fc41fd0e887eb9bce00b011cf7b9aabe30ccc0336062f1ffef  Image (59,132,416 bytes)
021f226be4dc9e404dc28d4432567a7e35575ced5100c5f11da4a19fc8081255  System.map
140b30516c4e926bb13d5dc273a943dcb9fc372b9e5833099caa0b3e3fdbe2a6  config
21a8651a16f65c9e65db9ee888703ce8621bdb28508c5c19c506e8bc1ea52e0e  Image.xz (13,088,560 bytes)
```

The config and linked map prove built-in PPP/async PPP plus the existing
feature stack:

```text
CONFIG_PPP=y
CONFIG_PPP_ASYNC=y
CONFIG_TUN=y
CONFIG_USB_CONFIGFS_ACM=y
CONFIG_USB_STORAGE=y
CONFIG_USB_UAS=y
CONFIG_CFG80211=y
CONFIG_BRCMFMAC=y
```

`ppp_input` and `ppp_register_channel` are linked into `System.map`. The
existing kbuild checks also passed for the 16 KiB page ABI, DockChannel nbcon,
USB networking/storage, and all 12 built-in paired-firmware symbols.

## Initramfs reproduction and decoder gate

Build flags:

```text
FAT=0
T6040_PPP=1
T6040_WIFI_FW=1
T6040_WIFI_USERLAND=1
T6040_USB_GADGET_SCRIPT=scripts/t6040-usb-m1n1-acm-ppp.sh
```

Both clean network builds are byte-identical:

```text
9326edba565ae712bcf6187e619942b3243d35011f6f2a5274a513a8f57a4422
compressed 19,196,408 bytes
expanded   79,633,200 bytes
```

The image contains Alpine `ppp-daemon 2.5.3-r0`, `iw 6.17-r0`,
`wpa_supplicant 2.11-r4`, `/etc/ppp/options`, the target WiFi helper, and the
dual-ACM PPP gadget. It passes `scripts/t6040-minilzlib-harness.sh`.
The verifier's 128 MiB guard applies to the 79,633,200-byte expanded
initramfs, not to its informational 139,949,233-byte sum of all expanded
payload members.

The live-proven firmware naming is now fail-closed in the image builder:

```text
7cfae862...  c2 .bin content    -> c0 apple,mriya-WLMT-u.bin
af8df65b...  c2 .clm_blob       -> c0 apple,mriya-WLMT-u.clm_blob
9abb8c1a...  c2 .sig            -> c0 apple,mriya-WLMT-u.sig
2ee489bb...  c2 .txcap_blob     -> c0 apple,mriya-WLMT-u.txcap_blob
20325192...  c2 WLMT-u NVRAM    -> c0 apple,mriya-WLMT-u.txt
```

This preserves the exact mapping that initialized BCM4388 rev 6. Copying the
corpus without these aliases would silently regress WiFi.

## Target and host behavior

For WiFi, open an `st` terminal and run:

```text
t6040-wifi-connect "SSID"
```

The helper prompts with terminal echo disabled, removes `wpa_passphrase`'s
plaintext comment, stores the generated config only under RAM-backed `/run`
with mode 0600, waits up to 30 seconds for association, then runs BusyBox
`udhcpc`. Open networks use:

```text
t6040-wifi-connect --open "SSID"
```

For the tether fallback, Linux exposes the m1n1-shaped `1209:316d` device with
two ACM functions. Target `pppd` runs on `ttyGS0` as:

```text
10.42.0.2 <-> 10.42.0.1
```

On macOS:

```text
scripts/t6040-usb-ppp-host.sh /dev/cu.usbmodem...
```

or, if macOS does not attach a native tty:

```text
scripts/t6040-usb-ppp-host.sh --libusb
```

The libusb helper is exact-product-gated and refuses m1n1's own proxy gadget
despite the shared VID/PID. Apple's `pppd` 2.4.2 refuses to start unless
`/etc/ppp/options` exists. The host script intentionally does not create that
root-owned file; CJ must make an explicit one-time empty file before the
attended test.

Relevant source hashes:

```text
d9bc182f73c3a48b06af34872f5a8f7715a8a2067a5e88a68580c763ddc4a41f  t6040-build-alpine-dwm.sh
8faa1678625560efce70e2cc78ba0c2fc2d1a4b6d3d458392753bce27b3cc0f0  t6040-usb-m1n1-acm-ppp.sh
c579ea51cdd4794143452ba0ee1fc6effc69d45ea36e0edcc94dc0ea11827c07  t6040-usb-ppp-host.sh
e4131b13b8bfa460b08e23638874b2d1f1c797ada255b8c5596a0a795f01beda  t6040-usb-bulk-pty.c
```

All three shell files pass their relevant syntax checks; the host bridge
compiles cleanly with `-O2 -Wall -Wextra`.

## Two fail-closed catches

1. The first PPP root had the Alpine daemon but no `/etc/ppp/options`; Alpine
   installs only `options.example`, and both Alpine and Apple `pppd` reject
   startup before command-line options can help. That root was rejected and
   the builder now creates an explicit empty target file only when
   `T6040_PPP=1`.
2. The then-current feature kernel had `# CONFIG_PPP is not set`. The first
   raw object assembled with it was rejected and is not a candidate. PPP is
   not a userspace-only feature; the replacement kernel enables and verifies
   both core and async PPP.

## Safety and review gates

This candidate performs no HPM/SPMI transaction and makes no persistent
write. A power cycle clears its volatile state. It does, however, contain the
same live-proven PCIe initialization and `smc_gpio` endpoint-power path used
for the WiFi milestone:

- m1n1 performs PCIe PHY writes;
- Linux asserts SMC GPIO keys `gP13` and `gP19`.

Therefore the live run remains **attended-only**, needs exact-artifact review
and CJ approval, and must follow the one-PCIe-init-per-power-cycle rule. Do
not run it autonomously merely because all new PPP/WiFi-userspace work was
offline.

Suggested bounded pass criteria:

1. boot reaches dwm with Norwegian keyboard and DockChannel diagnostics;
2. `t6040-wifi-connect` associates and obtains an address, then a known LAN
   peer answers ping;
3. if useful, in the same boot the native tty or exact-product libusb bridge
   forms PPP and `10.42.0.1`/`10.42.0.2` ping in both directions.

PPP failure does not invalidate the already proven WiFi hardware result; it
only decides whether the tether fallback is usable. USB host read/write is
still separately blocked on the right-port Type-C/VBUS path.
