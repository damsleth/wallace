# T6040 XZ object decode validation + iBoot size probe — PASS (2026-07-25)

Follow-up to the 22 MB enrolled-boot loop. Two independent validations landed,
which together clear the XZ object `4340ec37` for enrollment.

## 1. iBoot enrolled-object size probe (maintainer-driven ladder)

Padded bare-m1n1 probes (`1394c345` + zero pad, exact sizes), enrolled via the
UUID-guarded kmutil command and cold-booted from the boot picker:

| Size | Result |
|---|---|
| 22.2 MB (`46237ade`, real object) | **boot loop** (Apple logo cycle) |
| 16 MiB probe | **boots to `Running proxy`** ✅ |

So the iBoot enrolled-path budget is **≥ 16 MiB** with the wall somewhere in
(16 MiB, 22.2 MB). Good enough: the XZ object is 15.2 MiB. (Finer bracketing
via the 20 MiB probe is optional — not needed for B0.)

A successful padded probe leaves a fully working proxy m1n1 (zeros = no
payload → proxy), so probes double as rollback states. The enrolled 16 MiB
probe is what currently boots the m1n1 volume.

## 2. XZ decode validation (chainload, same parser as enrolled path)

Chainloaded `m1n1-b0-alpine-openrc-earlyproxy-xz.bin` (`4340ec37`, 15,945,580 B)
over KIS onto the running probe m1n1. m1n1's payload parser + minilzlib are the
same code on the chainload and enrolled paths, so this validates decode without
touching enrollment:

- `Found an XZ compressed payload` ×2 (kernel `0x10004c90091`, initramfs
  `0x1000577cf18`) — minilzlib decoded both members
- `Linux wallace-b0 7.1.3-g96ac043df12f` → OpenRC → health report begin→end,
  `input0/event0` (05ac:0359), `/proc/partitions` empty, `watchdog0=present`,
  no network runlevel → `wallace-b0:~#` on ttydc0 + panel
- No SError/DART/panic; the only "SError" strings are the benign dapf skips.

Identical acceptance state to ticket 100 — expected, since the XZ members
decompress bit-identical to the proven payload (kernel → `df7657c1`).

## 3. Finding: `Boot policy: sip0 = 0` — the early-proxy window won't arm

The dual-mode m1n1's window condition is `!display && lp_sip0 == 127`
(upstream's gate for Asahi-standard installs). This boot chain reports
**`sip0 = 0`** and `display: 0x1` (internal panel initialized), so on this
machine/volume the window can **never** open — in practice `4340ec37` behaves
as pure auto-boot. Additionally, even `macvdmtool reboot debugusb` boots show
the panel initialized, so the `!display` half would not trigger either.

Consequence: the "dual-mode" debug door needs a v2 gate to actually function
here. Candidate designs (post-B0 decision):
- **Unconditional short window**: always wait ~5 s for a proxy at every boot,
  then auto-boot. Simple, always debuggable over DebugUSB, costs +5 s per boot.
- Custom gate (e.g. a chosen-var or GPIO/key check) — more work, zero delay.

Until then, returning to the dev loop after enrollment = boot picker → main
macOS → re-enroll a proxy object (rollback `1394c345` or any padded probe).

## Cleared next step (ticket 101)

Enroll `4340ec37` (UUID-guarded kmutil, main macOS or 1TR) and cold-boot from
the boot picker → expected: untethered Alpine/OpenRC on the panel = milestone
B0. Rollback unchanged (`1394c345` on the stick).
