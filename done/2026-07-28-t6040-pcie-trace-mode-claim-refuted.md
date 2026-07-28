# PCIe: the "T6040 tunables are traced, never written" claim is refuted — 068 already applied them

Offline code-inspection finding, 2026-07-28. No rig run, no hardware access. This corrects the
2026-07-26 note `done/2026-07-26-t6040-pcie-trace-mode-and-op115-identified.md` (finding 1), the
matching ticket-124 progress entry, and the NEXT_STEPS top-block statement of WiFi priority 2.

## The claim under test

The 2026-07-26 session concluded from `src/pcie.c`:

> On T6040 every tunable application is routed to `tunables_apply_local_trace()`, which **logs
> addr/size/mask/value instead of writing** … so the missing precondition for the op-115 PLL-lock
> poll is *applying* the `apcie-phy-tunables` that m1n1 currently only traces.

That became WiFi priority 2: "a bounded m1n1 change that applies ONLY those tunables, then re-check
the op-115 poll."

## The refutation, from the code at the exact live-run commits

`src/tunables.c` — at current main `7f687aae`, and unchanged at both PCIe live-run commits
`85b01036` (2026-07-14 shared-PHY continuation) and `e4671e08` (2026-07-24 ticket 068):

```c
int tunables_apply_local_addr(...)        { return ..._internal(path, prop, base, false, true); }
int tunables_apply_local_addr_trace(...)  { return ..._internal(path, prop, base, true,  true); }
int tunables_trace_local_dry_run(...)     { return ..._internal(path, prop, base, true,  false); }
```

The signature is `tunables_apply_local_addr_internal(path, prop, base, bool trace, bool write)`.
So **`tunables_apply_local_trace` traces AND writes** — the `_trace` suffix means "verbose, with
`dsb sy` fences and `L2C_ERR_STS` sampling around each RMW" (commit `00760c79` "tunables: fence
traced T6040 MMIO writes"), not "no write". The genuinely write-free helper is
`tunables_trace_local_dry_run`, which **nothing in the current PCIe path calls**.

`pcie_apply_local()` at both live-run commits routes T6040 to `tunables_apply_local_trace` —
i.e. the tunables were **applied to hardware** in both runs.

## Where the "dry run" log line actually came from

`pcie: T6040 AXI trace dry run complete; no PCIe MMIO` exists only in the 2026-07-14
**zero-write trace-volume control** (commit `cc8b0ead` "pcie: add T6040 zero-write trace control",
run as the log-buffer diagnostic — `done/2026-07-14-t6040-logbuf-upper-guard-control.md`,
`logs/t6040-console-20260714-logbuf-upper-guard.log`). That control existed to prove the traced
SError was a console/log-buffer artifact. The dry-run call was removed again by `0bede592` /
`f46d6e35` "pcie: restore guarded T6040 clock diagnostic". Reading that line as the *current*
behavior of the PCIe path was the 2026-07-26 error.

## Consequence: the priority-2 experiment has already been run, and it failed

The project's own live history, reread with the corrected semantics:

- **2026-07-14, `85b01036`:** completed operations 1–114 — *including all five controller
  `apcie-phy-tunables` RMWs* (0x417008000 mask 0x4000000; 0x417020000/24/28/2c mask 0x10000000,
  all clearing, all applied with fences and clean L2C status) — then hung at the op-115 pre-read.
- **2026-07-24, ticket 068 at `e4671e08`:** the same applied prefix *plus* the decoded clkgen PLL
  enable+lock. PLL locked, 100 MHz refclk OK, CLK0/CLK1 acked, PHY reset released — and the
  op-115 PLL-lock poll at `0x417040090` still hung
  (`done/2026-07-24-t6040-pcie-op115-clkgen-pll-result.md`).

So "apply the five phy tunables, then re-check op-115" is not a new experiment: it is **ticket 068,
which is negative and marked never-retry-unchanged**. Do **not** stage an attended session for it.

## What remains the real open lead (ticket 124, unchanged)

The `_initializePhy()` decode (`done/2026-07-26-t6040-pcie-initializephy-trace.md`): Apple performs
shared-PHY-aperture initialization that m1n1 never does — a bit-0 RMW of PhyCommon[0]
(`0x417004000`) plus PhyPhy setup (`0x417008000` window) — *before* any PHY-IP access. The exact
PhyPhy register/value pairs, the second PhyCommon write, and the authoritative
`_enableClocks → _configPciePLLs → _initializePhy` order are being extracted from the paired
kernelcache now (2026-07-28 offline session). Only after that full op list is grounded and
independently reviewed does a bounded m1n1 candidate — and an attended run — make sense.

## Lesson

Two of them, both recurring project patterns:

1. **A function name is not a semantics statement.** `*_trace` here means "instrumented", not
   "read-only". The five-line `_internal(…, bool trace, bool write)` dispatcher was the whole
   answer and takes thirty seconds to read.
2. **A log line must be matched to the binary that printed it.** The "dry run" line was true of a
   one-off 07-14 control binary and was quoted as the behavior of the current tree. Before building
   a premise on a transcript line, `git log -S` the string and pin the commit it came from.
