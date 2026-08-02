# T6040 NVMe CQ doorbell / CoastGuard static analysis (25F84)

Date: 2026-08-02

## Result

The paired macOS 25F84 host driver establishes one previously unmatched
ordering rule for its CoastGuard-v2 I/O completion path:

1. consume one or more CQEs and update the software head/phase;
2. write the resulting CQ head doorbell;
3. call the controller's virtual `ClearPendingRequest` method for the completed
   requests.

Linux currently does the protected-resource teardown in the opposite order:
`apple_nvmmu_inval(command_id)` runs while handling each CQE, before advancing
and writing the CQ head doorbell.  This is a real paired-driver difference, but
it is **not yet a root-cause result**: current m1n1 also invalidates its TCB
before ringing the CQ head and completes three ring wraps without an assert.
The difference is therefore a firmware-contract candidate specific to the
macOS/CoastGuard-v2 queue path, not a justified fix by itself.

The highest-value next discriminator remains a preserved modern RTKit
crashlog.  `patches/t6040-rtkit-modern-crashlog-debug.patch` adds logging-only
decoders for the modern sections that the current Linux parser reports as
unknown, and ticket 198 asks the rig owner for exactly one hashed capture.

## Paired inputs

Exact 25F84 raw kernelcache:

```text
/Users/damsleth/Code/linux-build-out/t6040-kernelcache-25F84.raw
SHA-256 ed556fe62efc2c229f3d4c7ebbbcd21fd5c8d099fbb4d9b5ae636dd78b61d3f6
```

`ipsw kernel extract` extracted the imported `IONVMeFamily` executable:

```text
/Users/damsleth/Code/linux-build-out/t6040-nvme-kexts-25F84/com.apple.iokit.IONVMeFamily
Mach-O 64-bit kext bundle arm64e
SHA-256 3427f865b409d50c7e2c548680104aa0e41cb4c76e69cdc4bf1944bdfe25b241
```

The target ADT identifies `/arm-io/ans` as ANS2 and supplies
`nvme-linear-sq`; the executable contains `AppleANS3CGv2Controller`, whose
visible overrides cover the linear SQ operations.  It does not expose a
separate `AppleANS3CGv2Controller::ClearPendingRequest` symbol, while the
inherited `AppleANS2CGv2Controller::ClearPendingRequest` is present.

## Exact static evidence

Relevant symbols from `nm -nm`:

```text
fffffe000a9a7d00 IONVMeController::RingCQHeadDoorbell(unsigned short, unsigned int)
fffffe000a9a8594 IONVMeController::ScanCompletionQueue(AppleNVMeCompletionQueue *)
fffffe000a9a9758 IONVMeController::ProcessCompletionQueue(AppleNVMeCompletionQueue *)
fffffe000a9a79ac IONVMeController::ClearPendingRequest(...)
fffffe000a9acec8 AppleANS2CGv2Controller::ClearPendingRequest(...)
```

In `ProcessCompletionQueue`:

- `0xfffffe000a9a9a6c` stores the new software head at queue offset `0x18`.
- `0xfffffe000a9a9a70` loads the CQ identifier.
- `0xfffffe000a9a9a78` forms `1 | (cqid << 1)`.
- `0xfffffe000a9a9a7c..0xfffffe000a9a9a8c` applies `CAP.DSTRD` and adds
  `0x1000`, i.e. the standard CQ doorbell offset.
- `0xfffffe000a9a9ab8` puts the new head in `w2` and
  `0xfffffe000a9a9ac0` makes the virtual MMIO-write call.
- only afterwards, at `0xfffffe000a9a9af0`, does it select vtable offset
  `0xb38`; calls at `0xfffffe000a9a9b0c` and `0xfffffe000a9a9b4c` process the
  two completion lists.  Symbol/vtable cross-reference identifies this slot as
  `ClearPendingRequest`.

The earlier part of the same function checks the CQE phase at status bit 16,
increments the head, and when the head equals queue size, sets head to zero and
flips the saved phase before reaching the sequence above.

## Linux and m1n1 comparison

In `~/Code/linux/drivers/nvme/host/apple.c`:

- `apple_nvme_handle_cqe()` calls `apple_nvmmu_inval()` before request
  completion;
- `apple_nvme_poll_cq()` then advances `cq_head`/phase for every CQE;
- after the drain loop it writes the final `cq_head` doorbell.

So the relevant Linux order is:

```text
TCB invalidation -> CQ head/phase advance -> CQ head doorbell
```

In `~/Code/m1n1/src/nvme.c`, lines 263 onward likewise invalidate the completed
TCB before advancing and ringing the CQ.  This refutes any unconditional claim
that invalidation-before-doorbell alone violates all 25F84 firmware paths.

There is also a read-only status-register discrepancy to audit:

```text
Linux APPLE_NVMMU_TCB_STAT 0x28120
m1n1 NVMMU_TCB_STAT        0x29120
```

Both implementations write invalidation at `0x28118`.  The differing status
offset cannot directly explain the CQ doorbell assertion because it only
affects the follow-up status read/warning, but it should not be silently copied
into another experiment.

## What remains unknown

Static host-driver analysis does not decode the firmware's `[7454]` assert
condition or the meanings of `status_reg`, `valid_status`, `err_info_0`, and
`err_info_1`.  The observed co-variation remains:

| Linux mode | `err_info_0` | `err_info_1` |
|---|---:|---:|
| depth 64, batched head updates | `0x3` | `0x40000` |
| depth 64, eager update | `0x1` | `0x20000` |
| depth 16, eager update | `0x1` | `0x20000` |

That pattern associates the extra bits with the batched-doorbell run, but does
not yet establish whether they encode delta, pending events, an error class, or
another state.

The ANS firmware is loaded separately by iBoot and the `[7454]` string is not
present in the persistent raw kernelcache.  A prior Linux run did emit a full
modern RTKit crashlog, but its complete console was left only in the rotating
`linux-build-out/dcuart-console.log` scratch path and was overwritten during a
later run before it was named and hashed.  It therefore is **not durable
evidence**.  The surviving output was sufficient only to identify these
previously undecoded section tags:

```text
0x43637374  Ccst  task and firmware call stack
0x43617343  CasC  ASC error registers
0x4372746b  Crtk  task inventory/stacks
0x43636470  Ccdp  firmware VA-to-PA mappings
```

The layouts were ported from m1n1's
`proxyclient/m1n1/fw/asc/crash.py` into the logging-only Linux diagnostic
patch.  Its SHA-256 is
`849f06144da0dc867e766f6c0d8f1854a2f44238d9a99e3493e12c3e233c2669`;
`git apply --check` and `scripts/checkpatch.pl --strict` both pass.

## Next decision after ticket 198

1. Symbolicate the decoded firmware PCs if the `Ccdp` map gives a usable image
   base and the code pages are present in a paired artifact.
2. If the pages are only resident on the target, request a separate bounded,
   read-only dump ticket using the exact `Ccdp` mapping.  Do not guess or scan
   physical ranges.
3. Determine whether the `[7454]` path tests teardown state before accepting a
   CQ head update.  Only then stage an isolated ordering experiment.
4. Any Linux ordering experiment must avoid releasing/reusing a blk-mq tag
   before its old mapping is cleared; a naive move of `apple_nvmmu_inval()`
   after `nvme_try_complete_req()` would introduce a new tag-reuse race.

## Refutations preserved

- The static evidence does not revive wrap-per-se, batching, queue depth,
  concurrency, IRQ enablement, posted MMIO, or the IRQ/poll-lock hypotheses
  already killed by E1-E10.
- It does not prove that macOS performs a direct write to the same NVMMU
  invalidation register as Linux.  `AppleANS2CGv2Controller::ClearPendingRequest`
  uses the protected pmap/SPTM path before falling through to base cleanup.
- It does not justify changing Linux until the firmware call stack or a bounded
  one-variable experiment discriminates the ordering contract.
