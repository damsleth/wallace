# NVMe on Linux/T6040: the CQ-wrap firmware assert — evidence chain E1–E5b (ticket 192)

Campaign session over the enrolled rollback loader (chainloads only, zero enrolls). Goal: read AND
write CJ's 128 GiB exFAT partition (`nvme0n1p4`, created from macOS Disk Utility) from Linux.

## Where the boundary actually is

Everything up to sustained I/O works:

| layer | status |
|---|---|
| m1n1 ANS quiesce at handoff (`nvme_ensure_shutdown`) | ✅ |
| Linux cold-boots ANS, RTKit healthy | ✅ |
| Identify, namespace enumeration (`nvme0n1..n3`) | ✅ |
| **GPT read off the internal SSD** — `nvme0n1: p1 p2 p3 p4` | ✅ |
| exFAT probe reaches p1/p2 (rejects them correctly — they are APFS) | ✅ |
| sustained I/O (partition scan burst) | ❌ **fw assert, then dead controller** |

The assert, verbatim:

```
RTKit: Message (id=1): assert failed: [7454]:CQ (Host I/O) DB error,
  status_reg: 0x4, head: 63, valid_status: 0x4, err_info_0: 0x1, err_info_1: 0x20000
```

## Experiments

| # | hypothesis | change | result |
|---|---|---|---|
| E1 | CQ wraps are broken on this fw | m1n1 probe `--wrap-march 200` (~3 wraps) | **PASS** — m1n1 wraps fine. Wraps per se exonerated; bug is Linux-specific. Transcript `12b1a20b…` |
| E2 | Linux's *batched* doorbell (head jumps >1) is the trigger | m1n1 `T6040_E2_BATCHED_DB`: skip 3 of 4 DB writes so the 4th jumps by 4 | **PASS → hypothesis refuted.** Jumping doorbells are fine |
| E3 | concurrency; test via ring depth | `max_queue_depth = 2` | **INCONCLUSIVE** — driver never probes at depth 2 (no driver messages at all, only pmgr `sync_state pending`) |
| E4 | fw asserts when *unacknowledged* CQEs approach ring size | doorbell after **every** CQE instead of per batch | **REFUTED as a fix, but sharpened it:** crash head moved **61 → 63** at depth 64 |
| E5 | concurrency, via the right knob | `tagset.queue_depth = 1` | **INVALID** — `reserved_tags` is 2 on `has_lsq_nvmmu`, so reserved > total; boot hangs with no console output |
| E5b | same, valid tagset | `tagset.queue_depth = 3` (= 1 usable I/O tag) | **BOOT HANGS** too, no console output at all — restricting the tagset breaks the boot before console init. Cause unknown; not pursued further this session |

## What the numbers say

Crash head vs configured depth: **61** (depth 64, batched DB) → **63** (depth 64, eager DB) →
**15** (depth 16, batched DB). With eager acknowledgment Linux reaches the **last slot** and dies
**exactly at the wrap**; depth 16 shows the same last-slot pattern. So:

- it is not "ring fills with unacked completions" (E4 refuted that);
- it is not the wrap itself (E1: m1n1 wraps three times);
- it is not doorbell batching (E2);
- error fields co-vary with the mode: `err_info_0/1` = `0x3/0x40000` batched-64, `0x1/0x20000`
  for both eager-64 and depth-16. Undocumented; do not over-read.

**It is Linux's first CQ wrap specifically.** Setup differs somewhere such that everything works
until the host wraps.

## Checked and excluded this session (code reading, no boots)

- **Doorbell race between IRQ and poll paths** — excluded: `apple_nvme_irq()` and
  `apple_nvme_poll()` both take `anv->lock` around `apple_nvme_poll_cq()`.
- **Ring/qsize mismatch** — `create_cq.qsize = max_queue_depth - 1` (63 → 64 entries),
  `dmam_alloc_coherent(depth * sizeof(nvme_completion))`, wrap at 64. m1n1: identical (`qsize`
  `NVME_QUEUE_SIZE-1`, 64 CQEs, wrap at 64).
- **IOQ register write ordering** — both do create_cq → create_sq → write CQ base `0x1208`,
  SQ base `0x1200`. Same order, same registers.
- **Phase-bit convention** — both start `cq_phase = 1`, flip on wrap, compare `status & 1`.

## Next candidates (untested)

1. **The `need_ioq_register` values themselves.** Both write *a* base to `0x1200/0x1208`, but
   nothing has verified the firmware agrees on ring *size* there — if the fw derives the CQ size
   from something Linux sets differently (or not at all), the first host wrap would be the exact
   moment it diverges. Diagnostic, not boot-and-hope: dump `0x1200/0x1208` + the create_cq
   parameters from a live m1n1 session and compare with what Linux writes.
2. **Why a restricted tagset hangs the boot** (E5/E5b) — this blocks the cleanest concurrency
   test, so it is worth one debugging pass on its own.
3. **CoastGuard fw RE** (25F84 kernelcache) for the CQ doorbell contract — unbounded, last resort.

## Honest status

Read of *partition metadata* works and is reproducible. Read/write of file data does not, and
the remaining bug is one firmware assert with a narrow, well-instrumented locus but no confirmed
mechanism yet. Do not present partition enumeration as "NVMe read works" for the milestone: the
milestone is file I/O on `nvme0n1p4`.

All experiment code is on `wallace/t6040-bringup` (E3/E4/E5b commits) and
`wallace/t6040-pcie-nvme-dualmode` (E2 hook in m1n1); the probe's `--wrap-march` mode is in
`scripts/t6040-nvme-probe.py`. Rig parked at the rollback proxy, lease released healthy.
