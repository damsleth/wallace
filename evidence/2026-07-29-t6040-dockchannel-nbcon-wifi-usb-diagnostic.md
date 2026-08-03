# T6040 DockChannel nbcon WiFi/USB diagnostic

Offline build and packaging only. The rig, enrolled object, SPMI, PCIe PHY, and
Boot Policy were not touched.

## Outcome

A real `console=ttydc0` diagnostic object is staged for ticket 181:

```text
8baf5f65035bf7a026c41f9c35b7d47060fa33f8c75e13d168dfa955f4162fe3
  /Users/damsleth/Code/linux-build-out/m1n1-b0-dwm-nbcon-wifi-usb-diag.bin
30146560 bytes = 1840 * 16384
```

This supersedes the inert ticket-153 object. That older object merely added
`console=ttydc0`; its kernel registered no DockChannel console, and its
initramfs also exceeded the known-safe m1n1 decode budget.

The new object is diagnostic-only. It retains the graphical Alpine/dwm and
Norwegian-keyboard payload, SMC telemetry, USB storage/UAS and usbnet consumers,
and paired BCM4388 firmware. It does not enable the staged right-port ATC data
path, source VBUS, or train the WiFi PCIe link.

## Build integration

`scripts/t6040-kbuild.sh` now has an explicit `DOCKCHANNEL_NBCON=1` profile.
The profile:

1. requires `DOCKCHANNEL=1` and conflicts with the separate earlycon profile;
2. applies the established DockChannel poll fallback first;
3. applies `t6040-dockchannel-atomic-tx.patch`;
4. applies `t6040-dockchannel-nbcon.patch`;
5. gives Image, System.map, and config unique `-nbcon` names; and
6. refuses publication unless both `apple_dockchannel_send_atomic` and
   `apple_dctty_console_write` are linked.

Patch identities:

```text
627d0805f103f56ad20cc24785d4e747740e774c1660604611298adf6bcd0e63  t6040-dockchannel-poll.patch
a217182c4abb85d7c77c10083c617cb36677b16c454cd2d9fe7ab69339cef51a  t6040-dockchannel-atomic-tx.patch
b245c837793e16ed3241c893393f7c0e1b9a9fefd1391c4ba04842da0b969d6d  t6040-dockchannel-nbcon.patch
```

The first build caught a missing explicit dependency: the nbcon patch called
`apple_dockchannel_send_atomic()` but the build profile had not applied its
provider. After that was fixed, a fresh-checkout rebuild caught an ordering
dependency: the atomic patch is based on the poll-fallback driver. The final
profile applies and removes the pair in the dependency-safe order. These were
host build failures; neither invalid result was proposed for the rig.

Build source:

```text
linux wallace/t6040-bringup
ea5c9c1f7c934d2a84b9bf0a25e80c5a72254954
```

Build command:

```sh
podman exec \
  -e DOCKCHANNEL=1 \
  -e DOCKCHANNEL_NBCON=1 \
  -e HID_TYPE_FIX=1 \
  -e MACSMC=1 \
  -e T6040_WIFI_FW_BUILTIN=1 \
  -e BUILD_DIR=/build/linux-nbcon-wifi-usb \
  kbuild bash /out/t6040-kbuild.sh image
```

One reused-but-explicit build tree and one fresh checkout produced
byte-identical Image and System.map files. Recompressing both with
`xz -9e --check=crc32 -T1` also produced byte-identical XZ members.

## Kernel evidence

```text
079205acb574f98dd1b560f83c801df43a06b15d3d2f25989da87f55970bf049  Image-macsmc-hid-type-fix-nbcon-wifi-fw
217b4bd745e013400e29874f4ed4129b7f09650bc0387dbdb158536ec8389723  Image-macsmc-hid-type-fix-nbcon-wifi-fw.xz
99b61a92694c9ba266ba0773033b8f92d093cf7f7406d94fe588fdcef6b62a78  System.map-macsmc-hid-type-fix-nbcon-wifi-fw
b49a459e3e45135b9545771977cc371b2950cd21c68b5d76babcddc6eca6ce44  config-macsmc-hid-type-fix-nbcon-wifi-fw
11abca72b212362e1651a24f5dd07143b3b89956f8c00aaccec83d32b15df787  t6040-j614s-dcuart-macsmc.dtb
```

The raw Image is 59,066,880 bytes and its arm64 header reports 16 KiB pages.
The XZ member is one stream, one block, CRC32, no BCJ, with a 64 MiB
dictionary. It passes `scripts/t6040-minilzlib-harness.sh`.

Post-link checks found:

```text
ffffc000809aa170 t apple_dctty_console_write
ffffc000810476cc T apple_dockchannel_send_atomic
```

All twelve pinned C0/C2 `apple,mriya` firmware symbols are present. The final
config also has these consumers built in:

```text
CONFIG_CFG80211=y
CONFIG_BRCMFMAC=y
CONFIG_USB_STORAGE=y
CONFIG_USB_UAS=y
CONFIG_USB_NET_DRIVERS=y
CONFIG_USB_USBNET=y
CONFIG_USB_RTL8152=y
CONFIG_USB_NET_CDC_NCM=y
CONFIG_APPLE_DOCKCHANNEL_TTY=y
CONFIG_APPLE_DOCKCHANNEL=y
```

## Object manifest

```text
ecd264a51f83673a2d0ff00bd7dd882a0c582f982c7a940f4a63b564f55b4796  m1n1-t6040-fbonly-v7.bin
217b4bd745e013400e29874f4ed4129b7f09650bc0387dbdb158536ec8389723  kernel xz
11abca72b212362e1651a24f5dd07143b3b89956f8c00aaccec83d32b15df787  fixed MACSMC DTB
47d1e8ce938774eb570edd8e4151e2340a3f46e1fa29f7686b208721c5eb1058  proven dwm/keyboard initramfs
6819833284e010f9916a10684e60e14c1cedb87a5a7e13b805d06fbe06ef768c  diagnostic bootargs record
```

Boot arguments:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 console=ttydc0 fbcon=font:TER16x32 ignore_loglevel rdinit=/sbin/init
```

The initramfs independently passes m1n1's host XZ decoder. Strict object
verification reports:

```text
PASS object=8baf5f65035bf7a026c41f9c35b7d47060fa33f8c75e13d168dfa955f4162fe3
size=30146560 entry=0x800 pages=16K
runtime payload reserve=125554319 bytes
```

## Live gate

Ticket 181 is proposed, not approved or ready. Claude must independently review
the exact script/patch order, binary manifest, bounded atomic TX behavior, and
console registration; CJ must approve the exact live plan. Only then may an
agent acquire the rig and chainload it.

Pass means kernel dmesg reaches KIS and the same boot reaches dwm with the
keyboard and SMC health report. Capture PCIe, brcmfmac, DWC3/USB, UDC, and
network-device probe state. This boot contains no SPMI or PCIe-PHY write
experiment and must not be described as proving WiFi link-up or right-port USB.

The enrolled rollback loader's indefinite `Running proxy` removes the 10-second
catch race, but a successful chainload still consumes that proxy. A fresh
DebugUSB reboot or newly caught proxy is required before every later chainload.
