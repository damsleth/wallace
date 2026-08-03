# T6040 NVMe — Linux/m1n1 completion-order audit

Date: 2026-08-03

Ticket: 202

Rig use: **none**. This is a source-only audit and diagnostic patch proposal.

## Outcome

Hard-IRQ completion is a real, still-unmatched Linux/m1n1 difference, but the
source does not prove it is the firmware-assert cause. Two other unmatched
facts remain: Linux keeps a live admin queue and uses the ADT-declared NVMMU
aperture for linear SQ doorbells, while m1n1 performs no post-init admin
traffic and reaches the SQ doorbell through the controller mapping.

A minimal per-driver discriminator is ready:

```text
patches/t6040-nvme-threaded-irq-discriminator.patch
SHA-256 c3524c888cb056f9fe136b254bac136ab115a8fcffd83a3bb5b79bb19f1b4fe3
```

It changes only `devm_request_irq()` to
`devm_request_threaded_irq(..., NULL, apple_nvme_irq, IRQF_ONESHOT, ...)`.
The existing completion function, queue structures, MMIO addresses and
values, DMA barriers, TCB invalidation, and storage-command stream remain
unchanged. Generic IRQ code masks the interrupt line while the thread runs.
This distinguishes hard-IRQ servicing from threaded servicing, although a
positive result would still combine execution-context, scheduling-latency,
and interrupt-masking effects.

The patch applies cleanly to the current Linux source and passes strict
`checkpatch.pl` with zero errors and warnings. It is deliberately **not built
or runnable** in this ticket.

## Pinned source lineages

| source | commit | file SHA-256 |
|---|---|---|
| Linux `wallace/t6040-bringup` | `cd5da1d058e31ab1d3f933bd6c4206d6337c2cd5` | `drivers/nvme/host/apple.c` `44969a88c0b60b8629533d6b1c7f6d32756d0b4e52f7f2c92497ea64e3949abe` |
| m1n1 `wallace/t6040-pcie-nvme-dualmode` | `80badc91e62c8b4228a857730f160ffb62a29335` | `src/nvme.c` `76606416f012027d61485e0447c2dd0b348d9c0e9e72d5282e15a9a99fb32d95` |

The Linux completion code itself predates the T8132 changes. Commit
`8dc17800b4db` adds the separate NVMMU mapping and T8132 queue-register setup,
but retains the existing CQ/IRQ algorithm.

## Ordering matrix

| operation | Linux `nvme-apple` | m1n1 | verdict |
|---|---|---|---|
| Command/TCB visibility before SQ doorbell | coherent DMA followed by ordered `writel()` | explicit `dma_wmb()`, then `write32()` | semantically matched; barrier expression differs |
| CQ phase observation | `READ_ONCE(status)` phase check, then `dma_rmb()` before the remaining CQE fields | `dma_rmb()`, copy entire CQE, then phase check | both are valid producer/consumer shapes; exact instruction order differs |
| TCB invalidation | write tag to `NVMMU_TCB_INVAL`, read `TCB_STAT` | same | matched |
| CQ head/phase | increment; wrap to zero and toggle phase at queue depth | same at depth 64 | matched |
| CQ-head doorbell | normally once after draining all pending CQEs | once per synchronous completion | E4 already tested immediate Linux updates; not the remaining discriminator |
| Command tag/TCB slot | block tag, non-zero I/O slots | E11 forced tag/slot 2 | ticket 194 refuted tag value alone |
| CQ interrupt enable | enabled, vector 0 | E9 enabled the same CQ flag | flag matched; m1n1 still never services the MSI |
| Execution context | hard IRQ under `anv->lock` | synchronous proxy-thread polling | **unmatched** |
| Admin activity after I/O queue creation | live admin queue used by the NVMe core | admin queue remains allocated but idle | **unmatched; ticket 195** |
| Linear IOSQ doorbell aperture | declared NVMMU region (`reg[3]`) | controller mapping (`reg[9]` via broad arm-io map) | **unmatched; prior Linux move to reg[9] hung** |

## Linux completion path

The unmodified handler is a normal hard handler registered without
`IRQF_NO_THREAD`. It takes `anv->lock`, drains the I/O CQ, then the admin CQ.
For each CQE it:

1. observes the phase and executes `dma_rmb()`;
2. invalidates the command's NVMMU TCB and reads invalidation status;
3. records the block request's status/result;
4. advances the CQ head and toggles phase at wrap;
5. after draining, writes the final CQ head to the doorbell;
6. completes any locally batched requests.

The source comment above the submit doorbell already describes a
firmware-sensitive interval between TCB invalidation and final CQ update.
`anv->lock` prevents a new submission from ringing its SQ doorbell during that
interval. With the diagnostic's `maxcpus=1`, the normal read path is locally
batched: actual request teardown/tag release occurs after the CQ doorbell.
On SMP a remote completion can be queued earlier, but a new submission still
cannot pass the same lock until the handler has updated the CQ.

## m1n1 completion path

m1n1 has one synchronous command outstanding. It polls RTKit and the current
CQE, invalidates the TCB, advances head/phase, immediately writes the CQ-head
doorbell, and returns to its caller. E9 changed the create-CQ flag but did not
install or take an MSI handler; therefore E9 did not test real interrupt
servicing. E11 matched the non-zero tag and TCB slot but retained polling.

## Why not use `threadirqs`

The kernel's `threadirqs` early parameter would convert `nvme-apple`, because
the handler is not marked `IRQF_NO_THREAD`, and the current configs have
`CONFIG_IRQ_FORCED_THREADING=y`. It would also thread other eligible handlers,
including surrounding platform/RTKit paths, creating a broad timing confounder.
The two-line driver patch is narrower and preserves every other handler's
context.

## Safety and stop boundary

The patch adds no MMIO, storage command, SPMI, PMU, SMC, firmware, or NVRAM
operation. It changes IRQ registration only. A future live discriminator must
reuse an exact baseline that first reproduces the known `[7454] CQ (Host I/O)
DB error`, then change only this patch. It must retain read-only I/O, complete
transcript capture, exact artifact hashes, watchdog recovery, independent
review, CJ approval, and the rig lease.

## Next

Ticket 202 is complete. Open a separate offline build/review ticket for the
threaded-IRQ patch. Do not make it a rig ticket until the baseline and patched
artifacts are byte-reproduced and hash-pinned. Ticket 195 remains the separate
admin-traffic discriminator; ticket 201 remains the crashlog capture and is
the preferred baseline-evidence source.
