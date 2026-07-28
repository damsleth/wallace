# roleSwap decoded: SWDF/SWUF confirmed (correcting my 2026-07-26 error) — R3 is now specifiable

> **2026-07-28 CORRECTION — the VBUS conclusion in this document is WRONG.** `SWDF`/`SWUF` are the
> TPS6598x **data-role** commands (swap to DFP / UFP). The **power-role** commands are separate:
> **`SWSr`** (swap to source) and **`SWSk`** (swap to sink). Data role and power role are independent
> in USB-C — a DFP can be a sink — so **`SWDF` does not establish VBUS sourcing** and `SWUF` does not
> reverse a source transition. Every statement below equating DFP with "host/source … enables VBUS"
> is an unverified inference I propagated from the original 096 note, not something the disassembly
> shows. The 4CC identity, byte order, CMD1 target, and the one-byte-`0x00` DATA1 payload all remain
> correct. A replacement source/VBUS plan must decode and review `SWSr`, a source-state verification
> read, and its power-role inverse separately — and must not infer VBUS from a successful `SWDF`.
> Cross-review: `done/2026-07-28-t6040-r3-r4-crossreview-no-go.md` (reviewer `sol`).

## I was wrong on 2026-07-26; the original 096 claim was right

On 2026-07-26 I wrote that `AppleHPMInterface::roleSwap()` does NOT issue SWDF/SWUF, because I could
not find those 4CCs in the AppleHPM disassembly and concluded the claim "came from the public TPS6598x
driver." **That was my error.** I searched for the wrong encoding — ASCII bytes `SWDF` and the
LE-u32 immediate (`mov #0x5753`). The 4CCs are neither: they are **UTF-16 string constants**, loaded
via SIMD and byte-swapped. Searching those forms found nothing and I over-concluded.

## The actual decode

`AppleHPMInterface::roleSwap(unsigned char)` at VA `0xfffffe0009521fd0` (from `nm`). It branches on
the role byte and loads one of two 8-byte constants from `__PRELINK_TEXT`:

```
role == 0:  ldr d0, [x8, #520] -> 0xfffffe00074e3208 = 53 00 57 00 44 00 46 00 = UTF-16 "SWDF"
role == 1:  ldr d0, [x8, #512] -> 0xfffffe00074e3200 = 53 00 57 00 55 00 46 00 = UTF-16 "SWUF"
```

then `rev64 v0.4h` byte-swaps and the value is issued as a 4CC command. So, confirmed:

- **`roleSwap(0)` → `SWDF`** — Swap to **DFP** (downstream-facing port = **host/source**; this is what
  enables the port to source VBUS to a bus-powered device like our stick).
- **`roleSwap(1)` → `SWUF`** — Swap to **UFP** (upstream-facing = device).

Addresses cross-checked with the segment table (`__PRELINK_TEXT` vmaddr 0xfffffe000700c000, fileoff
32768) and decoded by script (not hand-arithmetic) after this session's earlier address slips.

## R3 is now concretely specifiable

The proven R2 candidate (`m1n1-hpm2`, `t6040_hpm2.c`) does:

```c
static const u8 command[4] = {'S','S','P','S'};
write_logical_reg(spmi, TPS_REG_DATA1 /*0x09*/, &target_s0, 1);
write_logical_reg(spmi, TPS_REG_CMD1  /*0x08*/, command, sizeof(command));   // poll for completion
```

An **R3 host-role candidate** is the identical code path with the 4CC changed to **`{'S','W','D','F'}`**
written to `TPS_REG_CMD1` (0x08) — i.e. one `static const u8` differs from R2. That would command the
right-port HPM to swap to DFP/host and (per the decode) source VBUS.

## What still gates building/running R3 — unchanged, and now with a cleaner alternative

1. **Confirm the target register from roleSwap's own code**, not just R2's precedent. roleSwap loads the
   4CC and calls a command helper; I decoded the 4CC values but did not fully trace that it writes
   CMD1 (0x08) vs a per-port command register. Trace that before building. (Cheap, offline, from the
   same disassembly.)
2. **Byte-level review of the 4CC**, per the DFU-4CC caution (a DFU-class 4CC exists in the vocabulary;
   a role swap and a firmware command differ by a few bytes). The maintainer authorised HPM role-swap
   writes, but the R3 candidate should still be reviewed at the byte level of the command constant.
3. **Attended run** on the framework of 096/097 (SPMI, right-HPM identity gate, recovery). Worst case
   remains odd port state until a power cycle (the 2026-07-25 risk calibration holds; our writes are
   register RMW + 4CC, no flash/OTP).
4. **The cleaner long-term path (170):** the t6040 PD controller is SPMI and the upstream Type-C stack
   is the reviewed way to do role/VBUS. The SWDF R3 is the fast test to source VBUS *now*; the DT/SPMI
   route is the maintainable answer. Both are worth pursuing; the SWDF decode does not obsolete 170.

## Bottom line

The VBUS blocker for USB read/write now has a concrete, decoded command (`SWDF` to CMD1), correcting my
earlier claim that it was undecodable. It needs step 1 (a short offline register-trace) plus a
maintainer-attended run — it is no longer knowledge-blocked, only review/rig-gated.

## Addendum: command register confirmed CMD1 (0x08) — R3 fully specified

Traced roleSwap's call target: `AppleHPMInterface::execute4Cc(uint16_t, uint8_t* cmd, uint8_t* data,
uint8_t)` at `0xfffffe0009519774`. Its first argument is a **command-register selector**: execute4Cc
compares it against `#8` and `#16` (`cmp w23, #16` / `cmp w23, #8` repeatedly) — i.e. `0x08` (CMD1) and
`0x10` (CMD2), the TPS6598x 4CC command registers.

This confirms two things at once:
1. The 4CC command register is **CMD1 = 0x08** (the same register the proven R2 SSPS path writes).
2. R2's direct-SPMI approach (`write_logical_reg(0x08, "SSPS")`) is the correct concrete instance of
   the AppleHPM `execute4Cc` operation — it bypasses the vtable machinery and writes the logical
   register directly, which R2 proved reaches S0.

So **R3 is fully specified with no further RE needed**: it is the R2 `t6040_hpm2.c` path with one change —
`static const u8 command[4] = {'S','W','D','F'};` written to `TPS_REG_CMD1` (0x08), poll for completion.
(SWUF, role→device, is the inverse for a clean rollback.) Step-1 gate from above is now satisfied; what
remains is only the byte-level review of the 4CC const and a maintainer-attended run on the 096/097
framework — no knowledge gap left.

## Addendum 2: independent byte-level review PASSED, with three refinements (2026-07-28)

A second, fully independent re-derivation from the raw kernelcache
(`t6040-kernelcache-25F84.raw`, capstone + scripted VA math) confirmed the substance and
corrected the mechanism:

1. **Identity/polarity CONFIRMED.** `roleSwap(0)` → UTF-16 "SWDF" (host/DFP), `roleSwap(1)` →
   "SWUF" (device); `roleSwap(≥2)` issues nothing. Constants verified at file bytes
   `53 00 57 00 44 00 46 00` / `53 00 57 00 55 00 46 00`.
2. **No DFU/flash 4CC exists to confuse with.** A full-image scan (ASCII + UTF-16) for
   `DFUs/DFUd/DFUc/DFUi/DFUe/FLrd/FLwr/FLem/FLad/FLvy/FLbd/FLip/FLsr` found zero occurrences.
   The only 1-byte-adjacent 4CC to SWDF is SWUF itself (byte 2, 'D'↔'U' = host↔device) —
   the one slip that matters is polarity, not a firmware command.
3. **Byte order CONFIRMED, mechanism corrected.** roleSwap does **not** call `execute4Cc`; both
   are siblings calling `AppleHPM::atomic4CC` (vtable slot 0x9a8). roleSwap does
   `rev64`+`uzp1` (producing "FDWS"), and atomic4CC's write site does a second `rev` — the two
   **cancel**, so CMD1 receives forward ASCII `53 57 44 46` = 'S','W','D','F' at bytes 0..3,
   exactly the R2-proven convention (`!CMD` = LE u32 `0x444d4321`). atomic4CC's p1==1 selects
   register 0x08 (CMD1) explicitly.
4. **One real spec change: DATA1 is written.** The strict "SWDF takes no input data" reading is
   refuted — atomic4CC as called by roleSwap writes exactly **one 0x00 byte to DATA1 (0x09)
   before CMD1** (p7=1, payload byte zeroed by roleSwap). The R3 candidate was updated to match:
   DATA1 ← `0x00` (1 byte), then CMD1 ← "SWDF" — which is byte-for-byte the R2 SSPS shape
   (whose `target_s0` was also 0x00) with only the 4CC changed.
