# T6040 m1n1-side NVMe probe — RESULT: SError, route closed (2026-07-25)

Ticket 127, maintainer-approved, run read-only against the enrolled bare loader
`1394c345`.

## Result: `nvme_init()` raises an async L2C SError

Identity gate passed (`target-type='J614s'`, `model='Mac16,8'`,
`chip-id=0x6040`, `board-id=4`, `/arm-io/ans` + `/arm-io/sart-ans` present), then
the single `p.nvme_init()` call took m1n1 down:

```text
PC:       0x1000484eef8 (rel: 0x22ef8)
SPSR:     0x60000009
FAR:      0x0
ESR:      0xbe000000 (SError)
L2C_ERR_STS: 0x82
L2C_ERR_ADR: 0x28360040dce4908
L2C_ERR_INF: 0x1400000001
Unhandled exception, rebooting...
```

m1n1 self-rebooted and came back on the enrolled bare loader; the USB-gadget
proxy re-appeared on its own. **No data-loss path was ever present** (the proxy
has no `P_NVME_WRITE` opcode; the run reached only `nvme_init`, never a read).

## Interpretation: the same M4 fault family m1n1 already works around

The signature is the *known* M4 async L2C SError. m1n1 already skips whole DARTs
for exactly this reason — `src/dapf.c:171`: *"On t8132 ('Neo' M4) initializing
this DAPF raises the async L2C SError"*, and every T6040 boot log shows
`dapf: Skipping /arm-io/dart-aop|dart-pmp|dart-isp0 (async L2C SError on this M4
SoC)`. ANS/SART belongs to that family: touching it from m1n1 faults at the
fabric/L2C level rather than returning an error.

**Consequence that matters beyond this ticket:** the NVMe wall is **not merely a
Linux-driver / guarded-ABI problem**. m1n1 — running bare, pre-Linux, at the
highest privilege available to us — cannot bring ANS up either. That is evidence
the protection is enforced *below* the OS (SPTM/CoastGuard-era fabric filtering),
which is directly relevant to the NVMe research track (tickets 051/052/054/055):
a perfect Linux-side driver would still hit this.

## What this closes

The upstream Asahi architecture (small enrolled stage 1 + `chainload=` stage 2
read from storage) is **unavailable on T6040** for internal NVMe, because
`chainload_load()` depends on `nvme_init()`. Combined with the appended-payload
root cause (`done/2026-07-25-t6040-enrolled-payload-rootcause.md`), both routes to
an untethered enrolled boot are now closed:

| Route | Status |
|---|---|
| Enrolled object with appended payload | closed — payload scan lands in m1n1's own image |
| Enrolled stage 1 + `chainload=` from NVMe | **closed — `nvme_init()` SErrors** |
| Enrolled stage 1 + stage 2 from USB | open, but needs Sol's R3 ATC/HPM host link **and** mass-storage + FAT support in m1n1 (absent; U-Boot has it, ticket 025/B1) |
| Tethered chainload over KIS/USB-gadget | **works today** (the proven configuration) |

## Optional follow-up (low expected value)

`pmgr: Cleaning up device states...` runs before this, so ANS's power domain may
simply be off, and a PMGR enable before `nvme_init()` is conceivable (m1n1
already does this for `ATC*_COMMON`). But given the fault is an L2C/fabric SError
of the same family as the DAPF blocks m1n1 deliberately skips, and given the
independent SPTM evidence, the probability that a power-domain enable fixes it is
low — and it is a PMGR write, i.e. a different risk class. Not recommended without
a specific reason to expect success.

## Value delivered

A single approved, read-only, bounded experiment closed an entire architecture
branch in one boot, with no data risk and self-recovery. The negative result is
also a positive contribution to the NVMe track: the boundary is enforced below the
OS, so Linux-side effort alone cannot cross it.
