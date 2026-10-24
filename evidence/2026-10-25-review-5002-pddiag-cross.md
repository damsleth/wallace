# Cross-review: 5002 pddiag image (305 run-8 candidate)

Reviewer: claude, offline, 2026-10-25, at Mythos's request. No rig, boot or
build; nothing reviewed was edited.

**Verdict: PASS-with-notes.**

## 1. Patch `t6040-tipd-connector-state-diag.patch` (`4bb22141…`)

- **Reads only.** `tps6598x_diag_connector_state()` calls only
  `tps6598x_read8/16/32/64` and `tps6598x_block_read`. It issues no
  `tps6598x_exec_cmd`, no `write*`, no INT_MASK1 (0x16) or INT_CLEAR1 (0x18)
  write, and no CMD1 (0x08) or DATA1 (0x09) access. The only write in either
  hunk is the existing `tps6598x_write64(tps, TPS_REG_INT_CLEAR1, event)` in
  `cd321x_interrupt`, which is unchanged context. The patch only adds a
  `dev_info` before it, so the Entry 1 W1C is not extended.
- **Registers:** STATUS 0x1a, MODE 0x03, SYSTEM_POWER_STATE 0x20, SYSTEM_CONF
  0x28, POWER_STATUS 0x3f, PD_STATUS 0x40, DATA_STATUS 0x5f, INT_MASK1 0x16
  (readback), 0x5d, 0x2c. All are R0 under `docs/SPMI_SAFETY.md` ("any
  logical register on the allowlisted endpoint"). On the SN201202x transport
  each read is the R0 sequence: a selector zero-write, then a bounded poll, then
  a read of the data window. That transport is unchanged by this patch.
- **Buffers are type-correct:** `status/conf/dstatus` are u32 via `read32`,
  `pwr` is u16 via `read16`, `pstate/r2c` are u8 via `read8`, and `mask_rb` is
  u64 via `read64`. `mode[5]` takes 4 bytes, `pdst[5]` takes 5 and `r5d[6]`
  takes 6. Every length is at most its buffer and at most `TPS_MAX_LEN` (64).
  On SPMI, `block_read` is a straight `regmap_raw_read` of `len` bytes into
  `val`, so there is no length-prefix overrun. `"%4.4s"` on `mode` is bounded.
- Call sites: one after the probe's VID check succeeds, and one per non-zero
  event after `read_status`, inside the existing locked handler.

## 2. kbuild block (d227605) and patch order

`T6040_TYPEC_PD_DIAG` is nested under `T6040_TYPEC_PD_WAKEUP` (itself under
`T6040_TYPEC_PD`). `DIAG` without `WAKEUP`, and `WAKEUP` without `PD`, both
exit with an error. Both logs show the same order, all `applied OK`: SPMI
transport, then WAKEUP + probe diag, then zero-write encoding, then the
connector-state diag (log lines 20–26 in both).

## 3. Image markers (build1 `08de37b1…`)

All 11 `diag[%s]:` format strings are present (STATUS, STATUS-read-failed,
MODE, SYSTEM_POWER_STATE, SYSTEM_CONF, POWER_STATUS, PD_STATUS, DATA_STATUS,
INT_MASK1 readback, reg 0x5d, reg 0x2c). Also present:
`diag[event]: INT_EVENT1`, `WAKEUP to SID %u: unexpected reply`, and
`zero-write to SID %u: unexpected reply`.

## 4. Reproducibility and config

```text
08de37b12a535c01  Image build1 == build2
9166487cccd0866a  System.map build1 == build2
51aa40f0df95a693  config build1 == build2 == config-usb2pd.buildA == ticket 305 pin (cmp identical)
```

## Notes (none blocking)

1. PD_STATUS is read as 5 bytes, but upstream tipd reads it with `read8`, and
   the TPS6598x register is 4 bytes. R0 permits the read, but SPMI_SAFETY says
   "at its natural length". Reading 4 would match the datasheet. Interpret
   byte 4 with care.
2. The natural lengths used for 0x5d (6 bytes) and 0x2c (1 byte) rest on the
   claim that the paired macOS driver reads them. I did not verify this.
3. The diagnostic adds about 11 R0 transactions to every non-zero event. An
   event storm on run 8 would multiply SPMI traffic and dmesg volume. Watch for
   it, and keep run 8 attended, as planned.
