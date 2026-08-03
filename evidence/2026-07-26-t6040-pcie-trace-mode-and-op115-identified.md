# PCIe/WiFi: m1n1 runs T6040 in TRACE mode, op-115 is a PLL-lock poll, and my addresses were wrong

> **2026-07-28 CORRECTION — finding 1 below is WRONG.** `tunables_apply_local_trace()` traces
> **and writes** (`_internal(…, trace=true, write=true)`); the five `apcie-phy-tunables` RMWs were
> applied in both the 2026-07-14 and ticket-068 live runs, and op-115 still hung. "Apply the
> tunables, re-poll op-115" is therefore a retry of negative ticket 068 — do not stage it. The
> quoted "dry run" log line came from the 07-14 zero-write log-buffer control binary, not the
> current path. Full evidence: `evidence/2026-07-28-t6040-pcie-trace-mode-claim-refuted.md`.
> Finding 2 (op-115 is a PLL-lock poll) and the section-3 address correction still stand.

Offline session, no rig run, no hardware writes. Three findings, one of which corrects something I
published earlier today.

## 1. m1n1 never writes any PCIe register on T6040 — by design

`src/pcie.c`:

```c
static int pcie_apply_local(const struct state *state, const char *path, const char *prop, u32 reg_idx)
{
    if (state->pcie_regs == &regs_t6040)
        return tunables_apply_local_trace(path, prop, reg_idx);   /* prints, does not write */
    return tunables_apply_local(path, prop, reg_idx);
}
```

On T6040 every tunable application is routed to `tunables_apply_local_trace()`, which **logs
addr/size/mask/value instead of writing**. Hence `pcie: T6040 AXI trace dry run complete; no PCIe MMIO`.

So PCIe on this machine is not *failing* — it is deliberately stubbed. That is the single most
load-bearing fact for the WiFi path, and it means the remaining work is a bounded, reviewable change to
let specific tunables actually apply, not further reverse engineering.

**The T6040 register indices are independently confirmed.** `regs_t6040` declares `rc_idx=1`,
`phy_common_idx=2`, `phy_idx=2`, `phy_ip_idx=3`, `axi_idx=4`, and today's live `/arm-io/apcie0` ADT read
gave `reg[1]=0x214000000`, `reg[2]=0x217000000`, `reg[3]=0x217040000`, `reg[4]=0x216000000` — the same
roles, derived from a completely separate source. The comment's claim of 35 regs / `#ports=4` /
`shared_reg_count=7` also matches exactly.

## 2. op-115 is a PLL-lock poll, not an arbitrary read

The captured trace already contains Apple's own PHY tunables — they were logged, never written:

```
apcie-phy-tunables[0] addr=0x417008000 size=4 mask=0x4000000  value=0x0
apcie-phy-tunables[1] addr=0x417020000 size=4 mask=0x10000000 value=0x0
apcie-phy-tunables[2] addr=0x417024000 size=4 mask=0x10000000 value=0x0
apcie-phy-tunables[3] addr=0x417028000 size=4 mask=0x10000000 value=0x0
apcie-phy-tunables[4] addr=0x41702c000 size=4 mask=0x10000000 value=0x0

apcie-phy-ip-pll-tunables[0] read-only addr=0x417040090 size=4 mask=0x1 value=0x1
```

That last line **is op-115**. It is marked `read-only` with `mask=0x1 value=0x1`, i.e. *poll bit 0 of
`0x417040090` until it reads 1* — a **PLL-lock wait**. The "hang at the first PHY-IP PLL read" is a poll
that never satisfies, which is a completely different problem from an unmapped or unpowered read, and it
fits ticket 068's result (the clkgen sequence locks *a* PLL, but this bit never comes up).

It also means a bare read of that address is harmless in itself — the earlier fear that op-115 might
SError was unfounded; it hangs because m1n1 spins waiting for a bit.

## 3. Correction: the absolute addresses I published today are wrong

In `evidence/2026-07-26-t6040-pcie-initializephy-trace.md`, and repeated in DEVLOG/README, I converted the
decoded offsets against the ADT `reg[]` values and published:

| | I published | Actually (from the trace) | delta |
|---|---|---|---|
| PhyPhy | `0x217008000` | **`0x417008000`** | `+0x200000000` |
| PLL poll (op-115) | `0x217048090` | **`0x417040090`** | — |
| PhyCommon[0] | `0x217004000` | **`0x417004000`** (inferred) | `+0x200000000` |

**The offsets from the disassembly were right and are now independently confirmed** — PhyPhy at
`base+0x8000` and the PLL bit at `phy_ip_base+0x90` both land exactly on the traced addresses. What was
wrong was the base: the ADT `reg[]` values I read are `0x216`/`0x217`, while the tunables address
`0x416`/`0x417` — a `+0x200000000` alias. Since AIC reports "1/2 dies" on this part, the likely
explanation is a die/alias offset applied between the ADT reg entry and the address the tunables use;
that is not yet established and must not be assumed.

**Lesson:** I derived absolute addresses by arithmetic on one source and published them as fact. The
trace was sitting in a log we already had and disagreed. Offsets survived; bases did not.

## 4. The next step, and why it needs no new authorisation

The values are known. A bounded m1n1 change would let T6040 *apply* rather than trace
`apcie-phy-tunables` (five register RMWs with explicit masks, all value 0 — i.e. **clearing** bits
`0x4000000` and `0x10000000`), then re-run and observe whether the PLL-lock bit at `0x417040090` comes
up.

Cheaper and strictly safer first step: **extend the trace, do not enable writes.** Confirm the full
tunable set for `apcie-phy-ip-pll-tunables`, `apcie-phy-ip-auspma-tunables` and
`apcie-cio3pllcore-tunables` is being logged (only 1 PLL and 14 cio3pll lines appeared, which may be
truncated), and resolve the `0x216/0x416` base question from the ADT before writing anything. That is
pure logging — no hardware writes, no new permission needed.

Do **not** enable the writes blind: the same reasoning that stopped the HPM R3 candidate applies here.
The addresses were wrong by `0x200000000` an hour ago, and a masked RMW to a wrong PHY base is a real
hardware write to an unknown register.
