# T6040 untethered Ubuntu object (ticket 136) — built (2026-07-25)

```text
m1n1-b0-ubuntu-untethered.bin
SHA-256 6b5060d04388b91335416c1f524330a79b974ce76bbdf853228e420aa5f816aa
23,691,264 B = 22.59 MiB = 1446 x 16 KiB pages (auto-padded, aligned)
```

| Member | SHA-256 | Size |
|---|---|---|
| m1n1 v3 (fb console forced on) | `c59d5820…` | 1.05 MiB |
| diet kernel (xz) | `efba5999…` | 4.68 MiB |
| storage-disabled DTB | `2782b922…` | 0.05 MiB |
| **Ubuntu 24.04 RAM root (xz)** | `e02e9a88…` | **16.81 MiB** |
| bootargs `5a24d959…` | — | `… rdinit=/init` |

Strict verifier PASS. Headroom against the measured 64 MiB ceiling: **41.4 MiB**.

## Notes

- The Ubuntu root is the ticket-091 live-proven image (`initramfs-ubuntu-ramroot-no.cpio.gz`,
  `0987cb7c…`) **re-compressed as minilzlib-safe xz** (`-9e --check=crc32 -T1`):
  28.0 MiB gz → **16.8 MiB xz**, saving 11.2 MiB. Content is unchanged (same cpio bytes).
- `rdinit=/init` — this image boots its custom `/init` at the root, not `/sbin/init`
  (unlike the Alpine/OpenRC B0 root). Confirmed present in the archive.
- Its keymap path differs from Alpine's too: Ubuntu ships a real `usr/bin/loadkeys` plus
  `usr/share/keymaps/i386/qwerty/no-latin1.kmap.gz`, so it uses `loadkeys`, not BusyBox
  `loadkmap`.
- The kernel will unpack a **97.3 MiB** cpio into RAM. m1n1's xz decoder advertises a
  1 GiB ceiling and the machine has ~23 GiB, so this should be fine — but it is the
  first large-payload decompression on this path and is the one genuinely untested
  aspect (iBoot's *load* ceiling and m1n1's *decompress* capacity are different limits).
  Expect a visibly slower boot than the 3.4 MiB Alpine root.

## Test order

1. **Tethered chainload smoke** (`scripts/t6040-boot-raw-object.sh` with this object) —
   proves the diet kernel + Ubuntu root + large xz decompression before spending an
   enroll cycle. Requires a working loader enrolled.
2. **Enroll + cold boot** (1TR, maintainer) → untethered Ubuntu on the panel.

Pass: Ubuntu userspace on the internal panel, Norwegian keymap loaded, watchdog fed,
`/proc/partitions` empty.

## Two harness lessons from the first smoke attempts (2026-07-25)

### 1. A dual-mode object cannot be tethered-smoke-tested

The first attempt chainloaded the dual-mode-based object. Its own 10 s window caught
`chainload.py`'s post-jump handshake:

```text
Waiting for proxy connection...  Connected!
Proxy is alive again
```

so m1n1 handed control back to the host and never booted the payload. Correct behaviour,
useless as a test. **Rule: enrolled/daily-driver objects use the window build; tethered
smoke objects must be window-free.** Added `m1n1-t6040-fbonly-v7.bin`
(`ecd264a51f83673a2d0ff00bd7dd882a0c582f982c7a940f4a63b564f55b4796` — `FB_CONSOLE_ALWAYS`
only, no early-proxy window) for exactly this, and
`m1n1-b0-ubuntu-smoke.bin` (`4784c29c957ac206ffb2367c5e28c89792d65896e5793da4ae388a015728904f`,
22.59 MiB) built from it.

### 2. The USB gadget cannot observe this image at all

The window-free object uploaded and jumped cleanly (`Loading kernel image (0x1698004
bytes)... Entry point: 0x100052f4800`; the trailing `Reconnection timed out` is the
expected autoboot signature), but **0 bytes** of post-jump console appeared, because:

- the object's bootargs are `console=tty0` — the internal panel only;
- the Ubuntu image's init writes to `/dev/ttydc0`, the **DockChannel UART**, which is
  observable only over **DebugUSB/KIS**;
- we were attached via the **USB gadget**, and gadget vs DebugUSB are mutually exclusive
  on the DFU port.

So the agent is blind in that configuration and only the panel shows the result.
**Rule: smoke-test this image over the KIS path** (`macvdmtool debugusb` + kisd +
`M1N1DEVICE=/tmp/m1n1`), which is how the original tethered Ubuntu RAM-root test produced
readable output. Use the gadget for *proxy control*, KIS for *watching a boot*.

## ✅ LIVE PASS — untethered Ubuntu shell on the panel (2026-07-25)

Maintainer confirmed: **the Ubuntu shell came up on the internal display.** Ticket 141
passes. So both distro targets now boot untethered on the M4 Pro:

| Object | Root | Size | Status |
|---|---|---|---|
| `m1n1-b0-alpine-dualmode.bin` `b409d89e` | Alpine 3.24 / OpenRC (musl) | 9.03 MiB | untethered + 10 s debug window |
| `m1n1-b0-ubuntu-smoke.bin` `4784c29c` | **Ubuntu 24.04 (glibc)** | 22.59 MiB | untethered (window-free build) |

This also settles the open technical question: **large-payload decompression works.** m1n1
un-XZ'd a 16.8 MiB member and the kernel unpacked a **97.3 MiB** cpio into RAM, then
handed off successfully. iBoot's load ceiling and m1n1's decompress capacity are separate
limits and neither binds at this scale.

Corroborating remote evidence, before the panel confirmation: the USB gadget disappeared
after the jump and never returned. The gadget is m1n1's, so its loss means m1n1 completed
the handoff rather than failing in its decompressor (which would have kept m1n1 alive and
printing), and its non-return means there was no reset loop.
