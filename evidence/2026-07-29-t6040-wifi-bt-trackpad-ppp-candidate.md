# T6040 graphical WiFi + Bluetooth + trackpad + PPP candidate

Date: 2026-07-29

Ticket: 185

Rig use: none. The enrolled rollback object remains at its indefinite
`Running proxy`.

## Outcome

One strict-verified chainload candidate now combines the live-proven PCIe/WiFi
path with the missing desktop-facing pieces:

- Alpine, dwm, the working Norwegian keyboard, `iw`, and `wpa_supplicant`;
- BlueZ (`bluetoothctl` and `bluetoothd`) plus a RAM-only startup helper;
- built-in DockChannel multitouch and the exact paired J614s HIDF;
- built-in SDHCI PCI, USB storage/UAS/usbnet, and asynchronous PPP; and
- the dual-ACM PPP fallback on the device-mode tether port.

The object is:

```text
/Users/damsleth/Code/linux-build-out/m1n1-dwm-wifi-bt-trackpad-ppp.bin
size   35,405,824 bytes = 2,161 * 16 KiB
sha256 19690506050552ea73e67a4932a91e05773b64b86a40df753e68e3d6aa3f8fb4
```

This is not an enrollment candidate. Its m1n1 member is the live-proven PCIe
diagnostic loader and does not contain the daily driver's 10-second dual-mode
proxy door.

## Exact members

```text
28a4e0cf812d48ab40337be9578381d66c61b5ac91730bb0b950930f77a93299  m1n1-t6040-pcie-V1-upstream-04e8829c.bin
2584e37a8ed1cf560b7332d73e0469ffebed8e3d4f44a4f44ba16f95c4ac5997  Image-macsmc-hid-type-fix-trackpad-nbcon-ppp.xz
0afb98ae31760309f1d28f0b84f313991f8460856685905bd52a0a6919d2fc7e  t6040-j614s-dcuart-wifi.dtb
d11e5c416e95262ea48347def8f9be08f1c5a08b4bcf3f6a48f1803e194e7547  initramfs-alpine-dwm-wifi-bt-trackpad.cpio.xz
7ce05abd2da1a13e6c89209a9c5dba1279d0860b3951d7995c838ef30ded0ca0  chosen.bootargs record
```

Bootargs:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 console=ttydc0 ignore_loglevel rdinit=/sbin/init
```

## Kernel reproduction

Two fresh case-sensitive build trees produced byte-identical outputs:

```text
5d913da6e47a925deef577e3e3ed75d39bd9d85c5f59d78c606d987b4f128a93  Image
4fed3e328a652a7dbb7734f05ad93f08208187aba5ae16be84109516ba4c3add  System.map
7460c7b0fa8e6f95174913265dbcca4bc8539a8ba6850444bf15d31e566684e6  config
```

The build used:

```text
DOCKCHANNEL=1
DOCKCHANNEL_NBCON=1
HID_TYPE_FIX=1
TRACKPAD_FW=1
T6040_PPP=1
MACSMC=1
WIFI=1
PCIE=1
```

Post-config and post-link assertions prove the 16 KiB page ABI and built-in
PCIe, WiFi, Bluetooth, SDHCI, USB storage/UAS, DockChannel nbcon,
`HID_MULTITOUCH`, PPP, and PPP async paths. The bounded HIDF loader source
marker is also checked.

The container filled during the first reproduction attempt. Only this task's
two temporary build trees were removed, recovering 5.8 GiB; the clean retry
then completed and matched the first build byte-for-byte.

## Initramfs reproduction and decoder gate

Build flags:

```text
FAT=0
T6040_PPP=1
T6040_WIFI_FW=1
T6040_WIFI_USERLAND=1
T6040_BT_USERLAND=1
T6040_TRACKPAD_FW=1
T6040_USB_GADGET_SCRIPT=scripts/t6040-usb-m1n1-acm-ppp.sh
```

Two full builds produced the same 22,015,216-byte XZ member. The expanded
newc archive is 91,798,000 bytes, below the approximate 128 MiB m1n1 limit,
and passes `t6040-minilzlib-harness`.

The second-build gate caught one real issue: Alpine's D-Bus post-install
generated a random `/etc/machine-id`. The builder now empties that file;
`t6040-bluetooth-start` creates the volatile runtime ID before starting
`dbus-daemon` and `bluetoothd`. After that fix, both initramfs builds are
byte-identical.

The staged trackpad file is exactly:

```text
a1f4131d0cb7caf6fa15b19f47725458a6d7b0e3a34f15169339d5541663d9e2  apple/tpmtfw-j614s.bin
```

The live-proven BCM4388 rev-6 c2-content-under-c0-`WLMT-u` aliases remain
hash-pinned by the builder.

## Safety and live gates

No rig action occurred. Ticket 185 is proposed and not runnable.

A future live boot repeats the already-proven PCIe PHY initialization and
Linux SMC endpoint-power writes `gP13`/`gP19`. Because X/libinput opens input
devices automatically, it may also cause the DockChannel driver to upload the
exact paired HIDF into volatile coherent DMA and issue the known interface
reset.

Before boot, all of these remain mandatory:

1. independent exact-artifact review by the other agent;
2. CJ plan approval and attendance;
3. explicit authorization for only the exact `a1f4131d...` non-persistent
   runtime HIDF upload and known interface reset; and
4. a fresh `Running proxy` recovery after the chainload.

That exception would not authorize flash/NVM, another board's firmware,
arbitrary firmware, PMU/GPIO reset, SPMI, or any persistent write.

Pass criteria are: `wlan0` associates and obtains DHCP, BlueZ reports `hci0`,
the trackpad registers and produces motion, and the PPP fallback can enumerate.
USB host read/write still separately requires right-port VBUS and the data-path
DT.
