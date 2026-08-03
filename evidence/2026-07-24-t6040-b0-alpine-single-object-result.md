# T6040 B0 Alpine single-object control — LIVE PASS (2026-07-24)

Ticket 089 (rig, P1, distro). The self-contained raw m1n1 object — the exact
artifact intended for untethered B0 cold-boot enrollment — chainloads from a
**single upload** and boots Alpine with a working internal keyboard and zero
storage exposure. This closes the raw-object/autoboot boundary and is the last
tethered proof before enrollment (082).

## What ran

- Object: `linux-build-out/m1n1-b0-alpine-hid-restored.bin`, SHA-256
  `b50f52ab…9172`, 21,729,039 B (author codex/sol; independently cross-reviewed
  by claude — strict verifier re-run + boot-script audit, PASS, see the 089
  preflight doc).
- Delivery: `scripts/t6040-boot-raw-object.sh` → `chainload.py -r` **once**. No
  `linux.py`, no second payload, no target command sent.
- Recovery reboot to a clean m1n1 proxy first; lease held by claude throughout.

## Result — all five pass criteria met

Authoritative capture: `raw-object-chainload.log` (chainload.py held the pty and
logged the `TTY>` console stream through the jump; the post-jump reader is empty
because Alpine's report is one-shot and the object auto-boots without re-entering
proxy).

1. **Single upload + embedded payload discovery** — `Loading kernel image
   (0x14b8f13 bytes)... Entry point: 0x10004c1c800`, then `Found a variable at
   0x10004d28000: chosen.bootargs=maxcpus=1 idle=nop … rdinit=/init` and the FDT
   picking up the same bootargs. The embedded m1n1 discovered its own
   bootargs/kernel/DTB/initramfs from the one object.
2. **Alpine on ttydc0** — `*** Alpine RAM-root ready on /dev/ttydc0 ***`,
   `Alpine 3.24.0 (aarch64)`, `Linux wallace-ramroot 7.1.3-g96ac043df12f-dirty
   #3 SMP PREEMPT … aarch64`.
3. **Report reached its end marker** — `===== T6040 HID TRACE AUTO REPORT BEGIN
   =====` … `===== T6040 HID TRACE AUTO REPORT END =====`, then `[ramroot]
   spawning Alpine root shell` → `wallace-ramroot:~#`.
4. **Internal keyboard registered** — `I: Bus=0019 Vendor=05ac Product=0359`,
   `N: Name="Apple DockChannel Keyboard"`, sysfs
   `…/514600000.hid/0019:05AC:0359.0003/input/input0`, `H: Handlers=sysrq kbd
   leds event0`, and `/dev/input/event0` present. (Same 078 HID-type-fix kernel.)
5. **No storage exposure** — `/proc/partitions` shows the header only, no device
   rows. No USB/NVMe/ANS/SART probe; storage-disabled DTB held.

Machine healthy through the boot: MMU init clean, `CPU init (MIDR: 0x611f0551
smp_id:0x4)`, display notch handling (`3024x1964 -> 3024x1890`), no SError, DART
fault, panic, or reset. Rig parked back to a quiescent m1n1 proxy and released
healthy.

## Note — chainload.py exit status is cosmetic here

`chainload.py` exited 1 on a trailing `iface.nop()` `UartTimeout`. That is
expected for a B0 object: it is built to **auto-boot its payload without
re-entering the m1n1 proxy** (its binary lacks the proxy-wait /
`EARLY_PROXY_TIMEOUT` string, per the preflight). So after the jump there is no
proxy for `nop()` to poll — the timeout is the signature of a correct auto-boot,
not a boot failure. The Alpine report printing in full *before* the timeout is
the proof the payload ran.

## Fix applied during the run

`scripts/t6040-boot-raw-object.sh` defaulted `PY` to bare `python3`, which lacks
the m1n1 proxyclient's `construct` module (first attempt died at import, before
any device I/O — machine untouched). Changed the default to the venv interpreter
`/Users/damsleth/Code/m1n1/venv/bin/python`, matching `t6040-boot-dcuart.sh`.
Re-ran; boot succeeded.

## Significance / next

- The **single self-contained object** is proven bootable end-to-end — the
  packaging the B0 enrollment path (ticket 082) will enroll for an untethered
  cold boot. Every embedded component was already individually live-proven; this
  proves they boot as one enrollable unit with no host payload upload.
- Unblocks **082** (reversible enrollment / cold-boot preflight → gated cold
  boot). That, not USB, is the nearest-term untethered-distro win: it needs no
  USB/ATC/SPMI enumeration.
- Independent of Sol's USB-stick path (SPMI ladder 093–099), which remains the
  persistent-root route once HPM/ATC enumeration lands.

Ticket 089 done.
