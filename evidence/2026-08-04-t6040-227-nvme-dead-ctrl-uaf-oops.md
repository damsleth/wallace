# 227: NVMe dead-controller teardown is a use-after-free that takes down all block I/O

Captured from the enrolled `wallace-sdroot-no-20260804` object, 2026-08-04. This is the
answer to "shell works for a few seconds, then seems to hang".

## Two faults, four seconds apart

**1. Warning during teardown — 4.47 s**

```
WARNING: block/blk-mq.c:4423 at blk_mq_release+0x5c/0xe8, CPU#0: kworker/u57:0/20
Workqueue: nvme-wq apple_nvme_remove_dead_ctrl_work
  blk_mq_release  <- blk_put_queue <- nvme_free_ctrl <- device_release
  <- kobject_put <- put_device <- nvme_uninit_ctrl <- apple_nvme_remove
  <- platform_remove <- device_remove <- device_release_driver_internal
  <- device_release_driver <- apple_nvme_remove_dead_ctrl_work
```

**2. Real oops — 8.16 s**

```
Internal error: Oops: 0000000096000007 [#1] SMP
Workqueue: kblockd blk_mq_timeout_work
pc : blk_mq_timeout_work+0x1cc/0x238
x2 : 0000000000000000    Code: … (f9400040)   == ldr x0,[x2] with x2 = 0
```

ESR `0x96000007` is a data abort, translation fault at level 3 — a null/freed
dereference, confirmed by `x2 = 0` and the faulting instruction being a load
through it.

## Reading

The ANS controller dies on real I/O (`Buffer I/O error on dev nvme0n1p1` and
`nvme0n1p4` precede it, so namespaces *and* partitions enumerated first — this is
the ticket 206 firmware assert). `apple_nvme_remove_dead_ctrl_work` then tears the
controller down and frees the request queue, and `blk_mq_release` already warns
that the queue is not clean at that point. Roughly four seconds later
`blk_mq_timeout_work` — still armed against that queue — runs and dereferences the
freed structure.

**Consequence, and why it matters far beyond NVMe:** the oops kills
`kworker/0:0H` on **kblockd**, the shared block-layer workqueue. Every subsequent
block-I/O timeout for *any* device — including the SD card the root lives on —
depends on that worker. So a dying NVMe controller degrades the whole machine into
an unresponsive shell a few seconds after boot. NVMe is not merely broken here; it
breaks SD with it. That fully explains the reported symptom.

## Actions

1. **Immediate (done):** the daily-driver object is built on
   `t6040-j614s-dcuart-wifi-nonvme.dtb`, which sets `status = "disabled"` on
   `ans_nvme`, `ans_sart` and `ans_mbox`. With ANS never probed it cannot die, and
   SD stability no longer depends on NVMe behaving. Verified in the built DTB, not
   just the source.
2. **Root cause (ticket 206):** the first-CQ-wrap firmware assert is what kills the
   controller. Fixing it removes the trigger.
3. **Teardown safety (this ticket):** even with 206 fixed, the removal path is
   unsound — a queue is freed with work still armed against it. The fix belongs
   with `blk_sync_queue`/`blk_mq_quiesce_queue` (or `nvme_stop_ctrl`) before
   `nvme_uninit_ctrl` in `apple_nvme_remove`, so the timeout work cannot outlive
   the queue. The `blk_mq_release` warning at 4.47 s is the same defect reported
   early and politely.

Worth noting for upstream later: this is arguably a generic `apple_nvme` bug, not
T6040-specific — nothing in the trace is M4-dependent.
