# T6040 Alpine dual-mode daily-driver object (2026-07-25)

The "best of both worlds" B0 object: a normal cold boot offers a **10-second USB-serial
window** for host control, then auto-boots Alpine if nobody connects.

```text
m1n1-b0-alpine-dualmode.bin
SHA-256 b409d89e85d309edb79defe01465c094fa642d5643a004a81c54c3e862f5bb5a
9,469,952 B = 9.03 MiB = 578 x 16 KiB pages (auto-padded, aligned)
```

| Member | SHA-256 |
|---|---|
| m1n1 v6 (10 s unconditional window + fb console first) | `c10a502f28750f34c7bd6daedcd312cc4f89e228256d892f0746fe54839f2227` |
| diet kernel (xz) | `efba5999…` |
| storage-disabled DTB | `2782b922…` |
| Alpine OpenRC root + Norwegian `no-mac` keymap (xz) | `d7fcc795…` |
| bootargs | `3659a0da…` (`… rdinit=/sbin/init`) |

Strict verifier PASS. m1n1 v6 is byte-reproducible across two clean builds;
`patches/m1n1-dualmode-window.patch` (33 lines) on `a61fd099`, built with
`-DEARLY_PROXY_TIMEOUT=10 -DEARLY_PROXY_UNCONDITIONAL=1 -DFB_CONSOLE_ALWAYS=1`.

## Behaviour

1. iBoot → m1n1 → fb console activated **immediately**.
2. `Bringing up USB for early debug...` / `Waiting for proxy connection... ....`
   for **10 seconds**, visible on the internal panel.
   - A host that connects within the window gets an m1n1 proxy: full chainload/debug,
     and the payload is **not** booted.
   - Nobody connects → `Timed out` → the embedded Alpine boots as usual.
3. Untethered cost: **+10 s** on every cold boot.

## Two fixes over the earlier attempts

- **`fb_set_active(true)` now runs first**, before the window. In v3/v4 it sat *after*
  the window, so the countdown was invisible on the panel — the window was working and
  simply could not be seen.
- **The object is page-aligned** (ticket 129). Every earlier dual-mode object was
  misaligned, so m1n1 never ran at all and the window could never have been observed
  when enrolled. The 5 s loop period back then was iBoot's retry cadence, not the
  10 s/60 s timeout.

## Open question this run answers

Whether the m1n1 USB gadget **enumerates on the host within 10 s at cold boot**. Earlier
evidence is mixed: a 5 s window never produced a `/dev/cu.usbmodem*` node, but that was
on objects where m1n1 never ran, so it proves nothing. The gadget does appear reliably
once m1n1 reaches `Running proxy` and holds it up indefinitely.

- Window visible on the panel **and** `/dev/cu.usbmodem*` appears → dual-mode works;
  10 s is the keeper value.
- Window visible but no host node in time → raise `EARLY_PROXY_TIMEOUT` (15/20 s) purely
  for host enumeration latency; nothing else changes.

Cable note: the window uses m1n1's **USB gadget**, not DebugUSB/KIS. They are mutually
exclusive on the DFU port, so do **not** run `macvdmtool debugusb` for this — just a
plain cold boot with the M1 cable attached, then connect with
`M1N1DEVICE=/dev/cu.usbmodemJ22GYCN4YG1`.
