# 🎉 NVMe READ WORKS on T6040 — internal SSD read from raw m1n1 (ticket 174)

2026-07-30, autonomous rig session, CJ pre-approved the probe incl. the CC.EN cycle.

## Result

`m1n1-t6040-nvme-two-base-ae4a8f28.bin` (branch `wallace/t6040-nvme-two-base`, head `1702259f`)
chainloaded over the rollback loader; `scripts/t6040-nvme-probe.py` (read-only surface: INIT /
READ / SHUTDOWN, no write opcode exists in the proxy):

```
nvme: ANS is on die 0
sart: SARTv3 /arm-io/sart-ans at 0x40dc50000
rtkit(nvme): booting with version 12
nvme: initialized at 0x44dcc0000          <- reg[9], the controller aperture
nvme_read(nsid=1, lba=0) -> 1             <- protective MBR (zeros in first 64 B)
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
   `reg[3]+0x24908` LINEAR_SQ_CTRL write. With the fail-safe, unknown ⇒ skip. Without this fix the
   probe SErrors identically to 07-25 and the two-base theory looks falsely refuted.

Shutdown note: `delete sq/cq` admin commands fail with status 2 and the error path performs
`pmgr_reset(ANS)` (approved); shutdown completes. Same on both runs; macOS re-inits ANS at next
boot. Probably the same "FW >= 15.0 no longer supports those admin opcodes" class as the skipped
legacy writes — harmless for us, worth a look before any Linux nvme-apple attempt.

## What this unlocks

1. **`chainload=` stage-2 architecture** — enrolled stage-1 m1n1 reads stage 2 from internal
   storage; kills the 16 KiB-page appended-payload pain and the enroll-per-object cycle.
2. **Linux `nvme-apple`** — the same two-base + no-legacy-writes shape ported to the kernel driver
   is now the credible route to NVMe read/WRITE (CJ main goal). Kernel side needs the same
   reg[9]/DT split; upstream `t8132.dtsi` work (yuka) is the reference.
3. Draft for CJ→upstream: the V_UNKNOWN gate hazard affects every future-fw machine, and the
   byte-vs-count reg_len bug affects every pre-M4 machine running yuka's branch.

## Evidence

Full transcripts in the rig console log (`/tmp/m1n1-console.log` during this session); probe stdout
captured in this doc's source session. Candidate hash pinned in
`done/2026-07-30-t6040-174-nvme-two-base-preflight.md`.
