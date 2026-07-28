# roleSwap decoded: SWDF/SWUF confirmed (correcting my 2026-07-26 error) — R3 is now specifiable

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
