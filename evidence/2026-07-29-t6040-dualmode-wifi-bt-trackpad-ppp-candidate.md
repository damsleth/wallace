# T6040 dual-mode WiFi + Bluetooth + trackpad + PPP candidate

Date: 2026-07-29

Tickets: 185 (chainload candidate), 186 (offline enrollment review)

Rig use: none. The rollback loader remains at quiescent `Running proxy`.

## Outcome

The near-term target now exists as an offline candidate:

```text
/Users/damsleth/Code/linux-build-out/m1n1-dwm-wifi-bt-trackpad-ppp-dualmode.bin
size   35,405,824 bytes = 2,161 * 16 KiB
sha256 db8ab4e44119a0ace019359823d438c75b0773b4a628c84b4cfa8d2f6c933e48
```

It combines:

- the 10-second unconditional m1n1 proxy window, entered only when a program
  opens the USB gadget and asserts DTR;
- the exact T6040 PCIe source that produced the live WiFi/BT milestone;
- Alpine + dwm + Norwegian keyboard;
- WiFi association userspace and the live-proven BCM4388 firmware aliases;
- BlueZ userspace for the already-live `hci0`;
- built-in multitouch plus the exact paired J614s HIDF;
- SDHCI, USB storage/UAS/usbnet; and
- dual-ACM asynchronous PPP as a tethered-network fallback.

It is not yet ready to enroll. Ticket 186 requires an independent exact review,
and the exact hash is deliberately not in `t6040-enroll-guard.sh` yet.
Enrollment remains CJ-executed and 1TR-only.

## Reproducible dual-mode prefix

Two isolated detached worktrees at:

```text
04e8829cbc47ff6a05e872dd329cdabb83554ce0
```

applied only the already-live-proven:

```text
patches/m1n1-dualmode-window.patch
```

and built with:

```text
RUSTUP_TOOLCHAIN=nightly
EXTRA_CFLAGS=-Wstack-usage=2048 \
             -DEARLY_PROXY_TIMEOUT=10 \
             -DEARLY_PROXY_UNCONDITIONAL=1 \
             -DFB_CONSOLE_ALWAYS=1
```

Both produced the same 1,097,728-byte (`0x10c000`) prefix:

```text
ee58fa400298ad605993e0aa07289354af06da27ff7668345f2527b9b08b767c
```

Static strings prove the intended paths are linked:

```text
pcie: Initializing t6040 PCIe controller
Bringing up USB for early debug...
Waiting for proxy connection...
Checking for payloads...
```

The source commit is the exact source of the live-proven diagnostic m1n1
`28a4e0cf...`; the only source delta is the existing 14-line dual-mode
framebuffer/window patch. The T6040 PCIe code in that commit uses the upstream
BIT(4) PHY reset path that eliminated the op-115 hang.

## Exact payload identity

The prefix has the same `0x10c000` length as ticket 185's diagnostic m1n1.
The two complete objects differ only before that offset:

```text
SHA-256 [0x10c000,end):
184d1e2f1d85d60b5a8148ab312f6f3e5736306caa36447b2d6a174f7b92dfa9

POST_PREFIX_BYTE_IDENTICAL
```

Therefore the variable record, kernel, DTB, initramfs, terminator, and final
16 KiB padding are exactly the already-strict-verified ticket 185 payload:

```text
2584e37a8ed1cf560b7332d73e0469ffebed8e3d4f44a4f44ba16f95c4ac5997  kernel XZ
0afb98ae31760309f1d28f0b84f313991f8460856685905bd52a0a6919d2fc7e  WiFi DTB
d11e5c416e95262ea48347def8f9be08f1c5a08b4bcf3f6a48f1803e194e7547  initramfs XZ
```

Both XZ members pass m1n1's host decoder harness. The raw object strict
verifier passes with entry `0x800`, 16 KiB kernel pages, 2,161 object pages,
and a 91,798,000-byte expanded initramfs.

## Review and policy gates

Ticket 186 asks the other agent to independently rederive:

1. the exact 04e8829c → windowed-prefix source delta;
2. the 10-second window and DTR/open-device behavior;
3. the live-proven T6040 PCIe BIT(4) provenance;
4. every member hash, XZ decode, strict layout, and 16 KiB alignment;
5. absence of SPMI, PMU/charger, NVRAM, flash, or persistent-write paths; and
6. the precise volatile trackpad HIDF policy boundary.

The candidate's fall-through boot performs the already-proven PCIe PHY writes
and Linux SMC endpoint-power writes `gP13`/`gP19`. X/libinput may open the
trackpad automatically, causing the exact `a1f4131d...` paired HIDF to be
uploaded into volatile coherent DMA followed by the known interface reset.

Before enrollment CJ must explicitly authorize only that non-persistent HIDF
operation. It does not authorize flash/NVM, arbitrary firmware, another board
blob, PMU/GPIO reset, SPMI, or any persistent write.

After review PASS, a separate commit may add exactly `db8ab4e4...` to
`scripts/t6040-enroll-guard.sh` and write the CJ-only 1TR enrollment preflight.
