# Ticket 305 run 7 (2026-10-25): WAKEUP works; the register-select zero-write is mis-encoded

Claude, CJ present (approved run 7). Kernel `fb8cd3c4…` (pdwake, two identical
builds; patch f430d1f, Mythos review PASS-with-notes), physfix DTB
`eaf8cceb…`, initramfs `4cc65133…`, m1n1 `7de07c71…`. S128 in the right
port; SD card out, so init stops at its ttydc0 rescue shell, with no storage
touched. Observation-only bootargs addition: `console=ttydc0 console=tty0`. Lease
released **healthy**.

## Result

```text
[0.197580] tps6598x-spmi 1-0c: after WAKEUP: power-state read ret=-5 state=0x00
[0.210283] tps6598x-spmi 1-0c: VID read failed: ret=0 vid=0x00000000
```

- **WAKEUP now reaches the bus and is ACKed.** There is no "SPMI WAKEUP
  failed" and no "WAKEUP to SID … unexpected reply", so the new `.cmd`
  validated the reply's opcode, SID and ACK.
- The register window still returns nothing. The cause is in the select:
  Linux's `spmi_register_zero_write(sdev, reg)` becomes
  `spmi_write_cmd(ctrl, 0x80, sid, 0, &reg, 1)`, and spmi-apple sends a
  command word with opcode `0x80` **plus a separate data word**. m1n1's
  proven encoding (`src/spmi.c:232`, R1 trace `opc=0xa0 extra=0x2000`) is
  one word, `opcode = 0x80 | value` and `extra = value << 8`, with no data
  word. So the part receives "select register 0" every time. VID (register 0)
  "selects" and reads zeros; the power-state select (`0x20`) reads back 0, so
  the driver's select loop returns `-EIO`.
- No typec port, no USB child (`usb1`/`usb2` root hubs only). Full dmesg
  (486 lines, `dmesg-run7-full.txt` `e21d4bf7…`) has no SError, DART fault,
  panic or Oops. Console `linux-build-out/transcripts/305-claude-20261025-run7/t6040-console-20261025-claude-ticket305-run7.log`.

## Safety note

Runs 6 and 7 each sent mis-encoded zero-writes: a `0x80`-opcode command
(writing 0 to register 0, which is just "select logical register 0", an R0
select), followed by a stray TX data word without the command-active bit. No
fault resulted. The fix removes the stray word.

## Next

Patch spmi-apple's write path so `SPMI_CMD_ZERO_WRITE` uses m1n1's encoding
and validates the reply. Then two clean builds, independent review and run 8.
