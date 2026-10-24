# Review: `patches/t6040-spmi-apple-zero-write-encoding.patch` (commit `64dcbaf`) — PASS with notes

Date: 2026-10-25. Reviewer: claude (offline, no rig). Requested by CJ:
"be strict, since it is the same controller that serves the PMU bus".

Compared against:

- m1n1 `src/spmi.c @ 80badc91` (`raw_command` lines 144-204,
  `spmi_reg0_write` line 226-233) and `~/Code/m1n1-hpm2 @ baf2c20d`
  (`src/spmi.c` differs from main only by the strict-mode tracing and FIFO
  refusal; the command-word construction is identical).
- The live R1 trace, `evidence/2026-07-24-t6040-hpm2-r1-wake-read-result.md`:
  `TX sid=0x0c opc=0xa0 extra=0x2000 in=0 out=0` → `RX header=0x00008ca0`,
  no data word, no trailing RX data (strict mode would have refused).
- Linux `drivers/spmi/spmi.c @ 4f2429104009` (`spmi_register_zero_write`
  → `write_cmd(ctrl, SPMI_CMD_ZERO_WRITE=0x80, usid, saddr=0, &data, 1)`)
  and the patched `spmi-apple-controller.c` (scratch tree: base + 0001 +
  wakeup + this patch, all apply cleanly in that order).

## Verdict

**PASS.** The command word the patch emits is bit-for-bit the word m1n1
proved on hpm2; the reply check is the same check m1n1 performs for a
no-data reply; the stray TX data word that runs 6 and 7 pushed is gone; and
the PMU bus cannot reach this code path at all. Three non-blocking notes.

## Command word, field by field

m1n1 `raw_command` builds
`FIELD_PREP(GENMASK(31,16), extra) | BIT(15) | FIELD_PREP(GENMASK(14,8), addr) | FIELD_PREP(GENMASK(7,0), opc)`
with `opc = 0x80 | value` and `extra = value << 8`, no data words
(`len_in = 0`). For `value = 0x20`, SID `0x0c`: `0x2000_8ca0`, which is
exactly what the R1 trace shows.

The patch writes `opc | sid << 8 | BIT(15) | (u32)data << 24` with
`opc = 0x80 | (data & 0x7f)`:

| bits | m1n1 | patch | match |
|---|---|---|---|
| 7:0 opcode | `0x80 \| value` | `0x80 \| (data & 0x7f)` | yes |
| 14:8 SID | `addr` (4-bit checked) | `sid << 8` (7-bit field, core passes usid) | yes |
| 15 active | set | set | yes |
| 23:16 | 0 (`value << 8` has nothing here) | 0 | yes |
| 31:24 | `value` | `data` | yes |
| data words | none | none | yes |

The old path (`4f2429104009`) packed `0x80 | sid<<8 | 0<<16 | (1-1) | BIT(15)`
= `0x8c80` ("select register 0") **and then a second word carrying the
value with the active bit clear**. That is the run 6/7 failure and the
hazard the patch removes.

## Reply validation

m1n1 (no-data reply): opcode field == `opc`, addr field == `addr`, ACK
(bit 15) set, and `reply_frame_parity_mask` (31:16) == 0. The patch checks
opcode (7:0) == `opc`, SID (14:8) == `sid`, bit 15 set, and returns `-EIO`
otherwise. The trace's `0x00008ca0` satisfies both. Note 2 below covers the
one m1n1 check the patch omits.

The reply is exactly one RX word (m1n1 strict mode asserts "no trailing RX
data" after this command and the R1 run passed), so reading one `RSP_REG`
word leaves the FIFO empty. No leftover can poison the next transaction.

## The PMU-bus question, answered by construction

1. **Different controller instance.** The PMU bus is `nub-spmi0`
   (`spmi@509014000`), hpm2 is on `nub-spmi-a1` (`spmi@509198000`). Each
   `platform_device` gets its own `struct apple_spmi` and its own FIFO
   registers; a transaction on a1 cannot touch spmi0's FIFOs.
2. **The PMU path never issues a zero-write.** `apple-spmi-nvmem.c` uses
   `devm_regmap_init_spmi_ext` (extended read/write opcodes only). In the
   whole tree `spmi_register_zero_write` is called from `spmi.c` (the
   export), `regmap-spmi.c` (the `spmi_base` regmap, unused on this
   platform) and our `tipd/spmi.c`. So the new `apple_spmi_zero_write`
   branch is reachable only through the hpm2 select.
3. **No change to the extended read/write paths** the nvmem provider uses:
   the patch adds an early return keyed on `opc == 0x80` and leaves
   `spmi_write_cmd` and `spmi_read_cmd` otherwise untouched (verified by
   the diff: one `#define`, one new function, one 5-line `if`).
4. The bounds check `len != 1 || buf[0] > 0x7f → -EINVAL` **refuses** rather
   than aliases an out-of-range select. Every logical register tipd touches
   is ≤ `0x70`, so this never fires in practice, and if it did the failure is
   loud and before any bus traffic.

## Notes (non-blocking)

1. **No FIFO pre-conditions, same as the rest of the driver.** m1n1
   refuses a command when the TX FIFO is non-empty and drains (or, in
   strict mode, refuses on) leftover RX data before every command. The
   Linux driver has never done either, and the patch follows the existing
   WAKEUP `.cmd` style. With the stray data word gone there is no known
   producer of leftovers, so this is hygiene, not a defect. If it is ever
   added it belongs in a shared prologue for all three paths, not in this
   patch.
2. **Reply bits 31:16 are not checked.** m1n1 requires them to be zero for
   a no-data reply (`reply_frame_parity_mask == MASK(0)`). The patch accepts
   any value there. Harmless for a correct part; a stricter version would
   add `|| (rsp >> 16)` to the mismatch condition.
3. **`(data & 0x7f)` in `opc` is redundant** with the `> 0x7f` refusal
   above; harmless.

## What this review does not cover

Nothing live. Whether the SN201202x honours the select after this fix is
run 8's measurement; the encoding is now identical to the one that worked
under m1n1 on the same endpoint, which is the strongest offline statement
available.
