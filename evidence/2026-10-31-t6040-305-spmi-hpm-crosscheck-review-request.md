# 305: macOS SPMI/HPM cross-check, checked against our driver (claude, 2026-10-31)

Source: wallace-rex Pipeline C cross-check (`4d5b016`, private; abstract facts only). Each point is
checked here against the reviewed patches (`0001-usb-typec-tps6598x-add-SPMI-transport…`,
`t6040-spmi-apple-zero-write-encoding.patch`, the 5002 pddiag image `08de37b1`) and against m1n1's own
`src/spmi.c`. **Nothing in the reviewed patches was edited.** Items marked *review* would change the
transaction path and need the SPMI_SAFETY review before any build.

**Bottom line for run 8:** nothing blocks it. One cheap, logging-only improvement is worth making if
the pddiag image is rebuilt anyway; the behaviour changes can wait for the run 8 result.

## 1. Zero-write reply check: probably fine

- macOS compares the reply with the command under mask `0xf80` (opcode bit 7 and SID bits 3:0; the low 7
  bits ignored), then requires reply bit 15 (ACK). Ours (`apple_spmi_zero_write`) requires
  `(rsp & 0xff) == 0x80 | value`, the SID, and ACK, which is stricter on the low 7 bits.
- m1n1's `spmi_reg0_write` uses the same strict check (`reply_opcode_mask = GENMASK(7,0)`).
  **It passed on J614s hpm2:** tickets 093/094/095 ran it against right HPM2 / SID `0x0c` (selector read
  back `0x20`, state `0x07`, then SSPS completed and the state read `0x00`). So the controller does echo
  the value bits.
- Caveat: earlier *kernel* paths discarded the reply header unchecked (August review), so run 8 is
  the first time the kernel validates it on J614s. Risk is low. *Fallback if it ever fails:* accept
  `((rsp ^ cmd) & 0xf80) == 0 && (rsp & BIT(15))` and log the real reply.

## 2. Select loop: strict on transients, and silent (worth a logging fix)

- `tps6598x_spmi_select()` (0001): after the zero-write it reads select register 0 up to
  `TPS_SPMI_SELECT_TRIES = 100` times at 1–2 ms. It returns 0 for `sel == reg`, sleeps on
  `reg | BIT(7)` (busy), and returns **`-EIO` for any other value without logging it**. The 100 x 1 ms
  budget matches m1n1's proven loop.
- macOS: polls register 0 every 1 ms up to 1000 tries. `== reg` ready; `== reg | 0x80` busy;
  **anything else means re-issue the zero-write and keep polling**, not an error.
- So a transient or stale readback right after a select would fail our probe with a generic
  error, and the log would not show the value. That would be an ambiguous negative for 305.
- *Logging only (no new transactions, no envelope change):* print `reg`, `sel` and `i` in the `-EIO`
  branch. Cheap, safe, and makes any run 8 failure readable.
- *Behaviour (review):* on an unexpected value re-issue the zero-write (the same select we already
  send) and keep polling, with a 1000-try budget. This is within the existing transaction classes, but it
  is still a change to the path 3009/5002 reviewed.

## 3. Read length: unverified here

macOS reads one byte at register `0x1f` (the selected register's length) after the select, then reads the
window at `0x20` and clamps the copy to that length. Our `window_read` was not compared line by line; do
that in the review if any read returns more bytes than the register holds.

## 4. Write window: parity, not a blocker

macOS writes data to window `0xa0` without a length byte, then re-issues the zero-write (commit) and runs
the same ready-wait. Ours writes window `0x20` with no re-select. m1n1's R2 (ticket 095) wrote DATA1 and
CMD1 (`SSPS`) successfully through its own path, so writes work on J614s today. Compare with macOS
before Linux writes any 4CC or data register. Run 8 is reads only.

## Suggested handling

1. Run 8 as built is acceptable. A failure at select is informative but ambiguous (see 2).
2. If a rebuild is planned, add only the logging in 2.
3. Put the behaviour items (2 retry, 3, 4) in a review after run 8, ahead of any write phase.
