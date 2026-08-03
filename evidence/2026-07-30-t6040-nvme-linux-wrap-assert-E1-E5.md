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

---

## E6 — register diff: the linear-SQ doorbells are in the WRONG WINDOW in Linux

Read-only MMIO dump from a live, *working* m1n1 NVMe session (transcript
`linux-build-out/e6-regdump-m1n1.txt`), taken after `nvme_init()` and one successful read:

```
nvme+0x24908  0x00000001   LINEAR_SQ_CTRL   <- reg[9]; iBoot already enabled linear-SQ mode
nvme+0x2490c  0x00000000   DB_LINEAR_ASQ    <- reg[9]; m1n1 rings HERE
nvme+0x24910  0x00000000   DB_LINEAR_IOSQ   <- reg[9]; m1n1 rings HERE
nvme+0x0100c  0x00000001   DB_IOCQ          (after 1 read: head advanced to 1)
nvme+0x01200  0x00000100070e4000  IOSQ_CMDS     nvme+0x01208 0x00000100070e8000 IOCQ_CQES
nvmmu+0x28100 0x0000003f   NVMMU_NUM        nvmmu+0x28108/0x28110 ASQ/IOSQ TCB bases
```

**The `0x249xx` block lives in the CONTROLLER aperture (reg[9] = `0x44dcc0000`).** Confirmed two
ways: `LINEAR_SQ_CTRL` reads `1` there, and m1n1 — which rings `reg[9]+0x2490c/0x24910` — completes
reads across 3 CQ wraps. Independently, `reg[3]+0x24908` is the exact address that raised the L2C
SError on 2026-07-25, i.e. the same block in the NVMMU window is *not* valid on M4.

Linux (`apple.c`, `has_lsq_nvmmu` branch) does:

```c
anv->adminq.sq_db = anv->mmio_nvmmu + APPLE_ANS_LINEAR_ASQ_DB;   /* reg[3] + 0x2490c */
anv->ioq.sq_db    = anv->mmio_nvmmu + APPLE_ANS_LINEAR_IOSQ_DB;  /* reg[3] + 0x24910 */
anv->adminq.cq_db = anv->mmio_nvme  + APPLE_ANS_ACQ_DB;          /* reg[9] — correct */
anv->ioq.cq_db    = anv->mmio_nvme  + APPLE_ANS_IOCQ_DB;         /* reg[9] — correct */
```

On every pre-M4 machine `mmio_nvmmu == mmio_nvme`, so the choice was invisible. With the M4
two-base split it is a real difference: **Linux rings submission doorbells into the NVMMU window
while ringing completion doorbells in the controller aperture.** That the SQ and CQ doorbells for
the same queue land in different windows is, on its face, wrong.

## E7 — the fix attempt: INCONCLUSIVE, boot produced no console output

Changed both `sq_db` assignments to `mmio_nvme` (commit on `wallace/t6040-bringup`). The boot
produced **no kernel console output at all** over ttydc0 and no getty — same signature as E5/E5b.
Bootargs verified correct in the m1n1 FDT dump (`console=ttydc0` present). Machine recovered
cleanly with a reboot to the proxy.

Not interpreted as "E7 is wrong": three consecutive experiments now share this
no-console-output signature, which points at something common to these boots (possibly long
nvme admin-command timeouts stalling the boot before the DockChannel tty registers, or a
console-reader problem on the host side) rather than at each individual change. **The E7
hypothesis is untested**, not refuted.

**Next step is to watch the panel**, which carries `console=tty0` and is the one channel
independent of this failure mode — CJ can read the E7 boot directly. Until then E6 stands on its
own as a measured, reproducible discrepancy worth reporting upstream regardless of E7's outcome.

## E7/E8 resolved — and the "no console output" scare was a false alarm

**The earlier no-output boots were a host-side console problem, not hangs.** Re-run with a fresh
kisd attach, the *same* E7 kernel booted all the way to 12.5 s (486 lines captured). Every
"hang" claim about E5/E5b/E7 in the section above should be read as *unverified*; only E8 below
is a confirmed hang. Lesson: re-attach the reader and prove the console works (`wc -c` on the log)
*before* interpreting silence as a hang.

**E7 (sq_db → `mmio_nvme`, stock 0x10000 window): boots fine, NVMe silent.**
`nvme-apple … RTKit: Initializing (protocol version 12)` and then nothing — no assert, no crash,
no namespaces. Explanation: `APPLE_ANS_LINEAR_IOSQ_DB` is at **+0x24910**, far outside the
**0x10000** `nvme` resource, so the write never reaches the register. This also explains yuka's
choice: she pointed the SQ doorbells at `mmio_nvmmu` because that window is **0x60000** — she
needed the *size*, not the base.

**E8 (same, plus `nvme` window widened to 0x60000): HANGS the machine.** Confirmed hang — console
dead, no response, recovered by reboot to proxy. So making the write actually land at
`reg[9]+0x24910` from Linux is *fatal*, even though m1n1 writes the identical address happily.

### What that leaves

Three verified facts that do not yet fit one story:

1. `reg[9]+0x24908` **reads** `1` from m1n1, and m1n1 **writes** `reg[9]+0x2490c/0x24910` and
   completes I/O across 3 CQ wraps. (E6, measured.)
2. `reg[3]+0x24908` raises an L2C SError (2026-07-25).
3. Linux writing `reg[9]+0x24910` through a proper ioremap **hangs the machine** (E8), while the
   same driver writing `reg[3]+0x24910` reaches partition enumeration and then hits the CQ-wrap
   assert (E1–E5 baseline).

The difference between (1) and (3) is the access *context*, not the address: m1n1 runs with no
other agent touching ANS, Linux runs with DART/IOMMU active and interrupts live.

**The posted-vs-nonposted hypothesis is already dead** (refuted by code reading, no boot spent):
m1n1's `mmu_map_mmio()` maps every `/arm-io` range as `MAIR_IDX_DEVICE_nGnRnE` — non-posted, the
same semantics Linux derives from `nonposted-mmio`. Both sides use identical access attributes,
so the mapping type is not the difference.

Remaining candidates, cheapest first: (a) the E8 hang was never bisected — one boot, one changed
DTB, and the hang was *assumed* to come from the doorbell write; re-run E8 with the widened window
but the driver still writing `mmio_nvmmu`, which isolates "widening the window" from "writing the
register"; (b) whether the ADT declares a *separate* reg entry covering `0x44dce000`-ish that
should be mapped instead of widening reg[9]; (c) CoastGuard fw RE for the linear-SQ contract.

**Tree state: both experiments reverted.** `drivers/nvme/host/apple.c` is back to stock upstream
(`sq_db = mmio_nvmmu`) and the DT window is back to the ADT-declared `0x10000`, with the finding
recorded in a comment so nobody "fixes" it blindly. The rebuilt kernel in `/out` is the known-good
baseline again.

## CORRECTION to E6: the "wrong window" claim is weaker than I stated

Full ADT reg map for `/arm-io/ans` (CPU addresses):

```
reg[0] 0x409600000..0x409688000   reg[3] 0x40dcc0000..0x40dd20010 (0x60010)
reg[1] 0x409050000..0x409054000   reg[4] 0x40b000000..0x40b018000
reg[5] 0x40db90000..0x40db9c000   reg[6] 0x40dd47c00..0x40dd4bc00
reg[9] 0x44dcc0000..0x44dcd0000 (0x10000)
```

**No declared window covers `0x44dce4910`** (= reg[9]+0x24910, where m1n1 rings and E6 read
`LINEAR_SQ_CTRL == 1`). m1n1 reaches it only because `mmu_map_mmio()` maps whole `/arm-io`
*ranges*, not per-device regs, so undeclared space inside a range is still mapped.

Meanwhile `reg[3]+0x249xx` **is** inside a declared window, and stock Linux — which rings there —
successfully submits admin and I/O commands and enumerates all four partitions. So:

- the SQ doorbells are **not** simply "in the wrong window" in Linux; that path demonstrably works;
- the 2026-07-25 SError at `reg[3]+0x24908` was most likely a *state/timing* fault during early
  m1n1 init (old single-base code), not proof that the address is invalid;
- both `reg[3]+0x249xx` and `reg[9]+0x249xx` appear to alias the same block.

**Therefore E7/E8 were chasing a non-bug**, and the CQ-wrap assert (E1–E5) remains the real
target. Time cost: two boots plus a hang. The lesson worth keeping: an address that *reads
plausibly* from m1n1 is not evidence that the other path is wrong — check whether the suspect
path already works before "fixing" it.

---

# Session 2 (2026-07-31): the bisect, and four more hypotheses down

## Environment note

The host's case-sensitive kernel volume (`linux-case-sensitive.sparsebundle`) was unmounted and
the podman VM was down at session start — both restored with `hdiutil attach` +
`podman machine start` + `podman start kbuild`. Worth knowing: `/Users/damsleth/Code/linux` is a
symlink into that sparsebundle, so a `cd: no such file or directory` there means "volume not
mounted", not "tree deleted".

## E8 bisect: widening the window is HARMLESS

Widened `nvme` reg to `0x60000` with the **stock** driver (`sq_db = mmio_nvmmu`). Boot completed
normally — 911 lines of console, full userspace. So E8's hang was **not** caused by the DT change;
it was caused by the driver actually *writing* `reg[9]+0x24910`. Ringing the linear-SQ doorbell in
the controller aperture from Linux is fatal, while m1n1 does it happily — one more entry in the
"same address, different context" column. Stock `mmio_nvmmu` is the correct path for Linux.

## 🎉 The exFAT partition MOUNTED

From that same boot:

```
t6040-data: /dev/nvme0n1p3 mounted at /mnt/nvme
[    5.060179] nvme-apple … assert failed: [7454]:CQ (Host I/O) DB error, … head: 63 …
```

**Linux mounted CJ's 128 GiB exFAT partition off the internal SSD** (it is `p3`, not `p4` as
assumed earlier) and did real filesystem I/O for ~5 s before the assert killed the controller.
The data path works end to end; only the wrap assert stands between this and the milestone.

## E9 — IRQ-enabled CQ: refuted

Linux creates the IOCQ with `NVME_QUEUE_PHYS_CONTIG | NVME_CQ_IRQ_ENABLED` + `irq_vector 0`;
m1n1 uses contiguous-only. Added `T6040_E9_CQ_IRQ` to m1n1's `create_cq` and re-ran
`--wrap-march 200`: **PASS**, 3 wraps, no assert (transcript `1d19ebac…`). The interrupt-enabled
CQ is not the trigger.

## E10 — concurrency: REFUTED (and E5b was a false negative)

`git show` on the `Revert E7` commit confirms it restored `tagset.queue_depth = 3` — so the
boot above, which mounted the filesystem and then asserted, was **already running with exactly one
usable I/O tag**. A single in-flight I/O command still produces `head: 63`. Concurrency is not the
trigger, and E5b never hung — it worked, and its "hang" was the console false alarm.

## Differences now MATCHED between m1n1 (works) and Linux (asserts)

`create_cq` qsize 63 · `NVMMU_NUM_TCBS` 63 · physically-contiguous flag · CQ interrupt ·
one in-flight I/O command · phase-flip logic · ring allocation size · IOQ base registers
(`0x1200`/`0x1208`) · doorbell batching (both tested)

## Differences that REMAIN

1. **SQ doorbell window** — m1n1 rings `reg[9]+0x24910`, Linux `reg[3]+0x24910`. Linux cannot use
   reg[9] (hangs, bisected above), and reg[3] demonstrably submits commands fine. Still the most
   conspicuous asymmetry.
2. **Tag value** — m1n1 always uses tag 0, so NVMMU TCB slot 0; Linux draws from a pool with
   `reserved_tags = 2`, so its I/O tag is non-zero. Cheap to test m1n1-side (force tag 2 and
   wrap-march).
3. **Admin traffic** — Linux issues Identify and keeps a depth-2 admin queue live alongside I/O,
   sharing the NVMMU TCB table; m1n1 issues neither after init.
4. **Real interrupt servicing** — E9 only set the *flag* in m1n1; m1n1 never takes or services the
   MSI. Linux completes inside its IRQ handler.

Next cheapest: (2), then (3) by making m1n1 issue an Identify before the wrap-march.

Tree left at the baseline: stock `queue_depth`, stock `sq_db = mmio_nvmmu`, DT window back to the
ADT-declared `0x10000`, `/out` rebuilt. m1n1 keeps the E2/E9 hooks (both compile-time, default off).
