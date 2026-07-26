# Ticket 163: the dual-mode graphical daily driver — built, and provably the proven payload

`m1n1-b0-dwm-dualmode.bin`
`3aabde2d4639639f5f0603d9eac9e3c05ee1f8b3c27c2aa53901e9a471b2efa8`
**28,459,008 B = 1737 × 16 KiB**, strict verify **PASS**, `entry=0x800`, kernel `pages=4K`.

A cold boot waits **10 seconds** for a USB-serial host to take control, and otherwise falls through to
**dwm on the internal panel**. That keeps a debug door in the enrolled daily driver: without it, every
later change would cost a full 1TR enrollment cycle.

| Member | Hash | Note |
|---|---|---|
| m1n1 **window10 v6** | `c10a502f…` | the windowed loader, live-proven both ways in ticket 140 |
| kernel `Image-hid-type-fix.xz` | `cbb3e743…` | full kernel, `pages=4K` |
| DTB `t6040-j614s-dcuart.dtb` | `2782b922…` | storage-disabled |
| initramfs `initramfs-alpine-dwm-hidpi.cpio.xz` | `47d1e8ce…` | 15.17 MiB xz → ~62 MiB expanded |
| bootargs | `3659a0da…` | the proven B0 set |

## Why this can be enrolled without a tethered smoke

**A window-carrying object cannot be tethered-smoke-tested** — its own 10 s window catches
`chainload.py`'s handshake (learned 2026-07-25). So the usual "smoke it first" step is unavailable, and
the confidence has to come from somewhere else. It does:

Both m1n1 builds are **exactly** `0x10c000` bytes, so the payload lands at an identical offset in both
objects, which makes a byte comparison meaningful:

```
prefix  [0, 0x10c000)   ecd264a5… (hidpi)  vs  c10a502f… (dualmode)   -> differs, as intended
payload [0x10c000, end) 3b1ac51f69d1b5d9a102fe71b3bf953c3c3d9433dfe193e723ec679641e1a6c7
                        3b1ac51f69d1b5d9a102fe71b3bf953c3c3d9433dfe193e723ec679641e1a6c7  -> IDENTICAL
```

All 97 differing 4 KiB pages lie inside the loader (`0x0`–`0x69000`), and there is **not one differing
byte at or beyond `0x10c000`**. So the payload is provably the exact bytes that produced working dwm with
a working keyboard — **the only variable is the loader**, and that loader was live-proven in ticket 140.

The loader is also confirmed to be the right one by what it uniquely contains versus the window-free v7:
`Bringing up USB for early debug...` and `Waiting for proxy connection... `. Both builds retain
`Checking for payloads`, so both still boot the payload.

## Enrolling it (maintainer, 1TR-only)

```sh
bash scripts/t6040-enroll-guard.sh          # fail-closed pin on the m1n1 System volume UUID
# then from 1TR:
kmutil configure-boot --raw --entry-point 2048 --lowest-virtual-address 0 -v /Volumes/m1n1
```

Pass, in two parts:

1. **window path** — with a host polling the m1n1 USB gadget during the first 10 s, it prints
   `Waiting for proxy connection...  Connected!` and stays in `uartproxy` without booting the payload;
2. **fall-through path** — with no host attached, it times out and reaches **dwm** on the panel, with a
   keystroke reaching `st`, `Alt+p` opening dmenu, and æ ø å correct.

Note the window uses m1n1's **USB gadget** on the DFU port, which is mutually exclusive with
DebugUSB/KIS — so attach with `M1N1DEVICE=/dev/cu.usbmodem*`, not `/tmp/m1n1`.

**Rollback** stays `rollback-m1n1-1394c345.bin` (payload-free proxy loader, restores tethered
development). The previous dual-mode daily driver was `b409d89e` (Alpine, not graphical).

## Expectations

- Boot is slower than the 9 MiB Alpine object: ~15 MiB of xz to decompress, plus the 10 s window when no
  host attaches. A pause is not a hang.
- Duplicated dmesg and some ghosted glyphs on the panel are the normal fbcon handover replay, not a fault.
- The trackpad is still dead by design (tickets 004/126); dwm is keyboard-driven.
