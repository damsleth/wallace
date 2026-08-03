# T6040 dual-mode WiFi + Bluetooth + PPP candidate without HIDF

Date: 2026-07-29

Ticket: 187 (offline independent review)

Rig use: none. The enrolled rollback loader remains at quiescent
`Running proxy`.

## Outcome

A policy-minimal alternative to the full ticket-186 trackpad image now exists:

```text
/Users/damsleth/Code/linux-build-out/m1n1-dwm-wifi-bt-ppp-dualmode-no-hidf.bin
size   35,356,672 bytes = 2,158 * 16 KiB
sha256 969ba852c0d8095796e4df02d7d60a64398410ad6cf49d4790592fb5118bfd36
```

It retains:

- the 10-second DTR-gated proxy door and the live-proven T6040 PCIe source;
- Alpine, dwm, the working Norwegian keyboard, and live SMC telemetry;
- the live-proven BCM4388 firmware aliases and WiFi association helper;
- BlueZ userspace for the already-live `hci0`;
- built-in SDHCI, USB storage/UAS/usbnet, and asynchronous PPP; and
- the dual-ACM PPP tether fallback.

It deliberately does **not** contain
`/lib/firmware/apple/tpmtfw-j614s.bin`. Therefore this object does not need the
ticket-126 exception for uploading the paired HIDF into volatile trackpad DMA.
The complete trackpad-capable object `db8ab4e4...` remains unchanged behind
that explicit policy gate.

This is an offline candidate, not a reviewed or enrolled object. Enrollment
remains CJ-executed and 1TR-only.

## Exact members

```text
ee58fa400298ad605993e0aa07289354af06da27ff7668345f2527b9b08b767c  m1n1-t6040-pcie-dualmode-window10-04e8829c.bin
2584e37a8ed1cf560b7332d73e0469ffebed8e3d4f44a4f44ba16f95c4ac5997  Image-macsmc-hid-type-fix-trackpad-nbcon-ppp.xz
0afb98ae31760309f1d28f0b84f313991f8460856685905bd52a0a6919d2fc7e  t6040-j614s-dcuart-wifi.dtb
0ff9415f931d30587852044112f31e5e65d69c32de928a950706269412e3ca7a  initramfs-alpine-dwm-wifi-bt-ppp.cpio.xz
7ce05abd2da1a13e6c89209a9c5dba1279d0860b3951d7995c838ef30ded0ca0  chosen.bootargs record
```

The prefix is the two-build-reproducible ticket-186 prefix: exact source
`04e8829c...`, plus only the existing 14-line dual-mode window patch and
`EARLY_PROXY_TIMEOUT=10`, `EARLY_PROXY_UNCONDITIONAL=1`, and
`FB_CONSOLE_ALWAYS=1`. It carries the upstream T6040 `BIT(4)` PCIe PHY reset
path that produced working WiFi and Bluetooth.

## Root reproduction and decoder gate

The RAM root was built twice with:

```text
FAT=0
T6040_PPP=1
T6040_WIFI_FW=1
T6040_WIFI_USERLAND=1
T6040_BT_USERLAND=1
T6040_TRACKPAD_FW unset
T6040_USB_GADGET_SCRIPT=scripts/t6040-usb-m1n1-acm-ppp.sh
```

Both builds are byte-identical:

```text
size expanded 91,717,760 bytes
size XZ       21,963,540 bytes
sha256        0ff9415f931d30587852044112f31e5e65d69c32de928a950706269412e3ca7a
```

The expanded archive remains below the approximate 128 MiB m1n1 limit.
Its file list contains the exact live WiFi aliases, `t6040-wifi-connect`,
`t6040-bluetooth-start`, `pppd`, and no `tpmtfw` path. The kernel configuration
has `CONFIG_EXTRA_FIRMWARE=""`, so the missing HIDF is not built into the
kernel either.

Both the kernel and initramfs pass m1n1's own host `XzDecode` harness:

```text
kernel:    12,233,656 -> 56,134,144 bytes
initramfs: 21,963,540 -> 91,717,760 bytes
```

The strict raw-object verifier passes with the exact members above, 16 KiB
kernel pages, and a 2,158-page total object.

## Safety and next gate

The fall-through path still performs the already-live-proven PCIe PHY
initialization and Linux SMC endpoint power writes `gP13`/`gP19`. It adds no
SPMI, PMU/charger, NVRAM, flash, or persistent firmware operation.

Ticket 187 asks the other agent to rederive the source delta, 10-second/DTR
behavior, exact hashes, XZ/layout checks, and absence of the trackpad payload.
Only after that review should an exact allowlist change and CJ-only enrollment
preflight be prepared. The current enrollment allowlist is intentionally
unchanged.
