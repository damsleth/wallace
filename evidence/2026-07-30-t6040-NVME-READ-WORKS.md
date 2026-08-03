# 🎉 NVMe READ WORKS on T6040 — internal SSD read from raw m1n1 (ticket 174)

2026-07-30, autonomous rig session, CJ pre-approved the probe incl. the CC.EN cycle.

## Result

`m1n1-t6040-nvme-two-base-ae4a8f28.bin` (branch `wallace/t6040-nvme-two-base`, head `1702259f`)
chainloaded over the rollback loader; `scripts/t6040-nvme-probe.py` invoked only INIT / READ /
SHUTDOWN. The NVMe-specific proxy also exposes FLUSH, unused here; it exposes no namespace-write
opcode:

```
nvme: ANS is on die 0
sart: SARTv3 /arm-io/sart-ans at 0x40dc50000
rtkit(nvme): booting with version 12
nvme: initialized at 0x44dcc0000          <- reg[9], the controller aperture
nvme_read(nsid=1, lba=0) -> 1             <- zeros in first 64 B; MBR fields not archived
lba 1: 45 46 49 20 50 41 52 54 ...        <- "EFI PART": the internal SSD's real GPT header
```

**This is the first read of the internal SSD on T6040 from a non-Apple OS.** The 2026-07-25
"protection is enforced below the OS" conclusion is now conclusively refuted: ANS + SART + RTKit +
controller enable + admin queue + I/O queue + a real block read all work from raw m1n1, no SPTM
involvement.

## What made it work (and what would have made it fail again)

Four yuka commits cherry-picked (`dc067af4`, `fd883241`, `8874ce87`, `11158bbb`) plus our
`1702259f` with two fixes — the second was **load-bearing**:

1. reg-entry count: `reg_len / 16 >= 10`, not `reg_len >= 10` (bytes vs entries).
2. **V_UNKNOWN fail-safe**: our machine reports `OS FW version: unknown (mBoot-18000.121.3)`, so
   yuka's `version < V15_0B1` gate evaluates TRUE on T6040 and would have re-executed the fatal
   `reg[3]+0x24908` LINEAR_SQ_CTRL write. The local fail-safe skips unknown exact strings and was
   correct for this machine's numerically new `mBoot-18000.121.3`. It is not a general ordering
   rule: an unlisted pre-15 string also becomes `V_UNKNOWN`, so upstream must compare parsed
   iBoot/mBoot versions or a hardware capability.

Shutdown note: `delete sq/cq` admin commands fail with status 2 and cleanup attempts both
`pmgr_reset(ANS)` and `pmgr_reset(ANS2)` (approved); shutdown completes. m1n1 prints the NVMe
completion status after removing the phase bit, so status 2 means **Invalid Field**, not Invalid
Opcode (which is 1). The current lead is an M4 queue-state or teardown-order mismatch, not removed
delete opcodes.

## What this unlocks

1. **`chainload=` stage-2 architecture** — enrolled stage-1 m1n1 reads stage 2 from internal
   storage; kills the 16 KiB-page appended-payload pain and the enroll-per-object cycle.
2. **Linux `nvme-apple`** — the same two-base + no-legacy-writes shape ported to the kernel driver
   is now the credible route to NVMe read/WRITE (CJ main goal). Kernel side needs the same
   reg[9]/DT split; upstream `t8132.dtsi` work (yuka) is the reference.
3. Draft for CJ→upstream: the exact-match `V_UNKNOWN` gate is unsafe for both new and unlisted old
   firmware, and the byte-vs-count `reg_len` bug affects pre-M4 machines running yuka's branch.

## Evidence

The decisive stdout excerpt was captured in this source session, but the full raw transcript was
not copied to a durable hash-pinned file; the temporary console path has since been reused. Treat
that as an evidence-hygiene defect and require the next bounded dump to preserve and hash its full
transcript. Candidate hash is pinned in
`evidence/2026-07-30-t6040-174-nvme-two-base-preflight.md`; independent exact-artifact review is in
`evidence/2026-07-30-t6040-174-nvme-two-base-adversarial-review.md`.
