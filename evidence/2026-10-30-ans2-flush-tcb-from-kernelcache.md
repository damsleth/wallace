# ANS2 Flush TCB: how the macOS driver encodes a data-less command (offline, for 5023/5006)

claude, 2026-10-30, offline and read-only. Source: the J614s macOS kernel
extensions in the private wallace-rex workspace. Symbol names, addresses
and the full reasoning are in wallace-rex
`findings/2026-10-30-ans2-durability.md`. This file carries only the
encoding facts. Nothing here has been tested on hardware.

## Result

**The macOS driver sends Flush with TCB opcode 0, dma_flags 0, length 0, and
no PRPs.** Before submission it explicitly clears both direction bits for any
command that has no data buffer. This matches the
`t6040-nvme-apple-flush-nodma.patch` hypothesis (ticket 5023) and contradicts
both encodings that failed in 5006: FROM_DEVICE from our kernel, and 3 from
m1n1.

## How the macOS driver builds the per-command TCB

The macOS NVMe driver has several ANS controller variants. Two of them build
a TCB entry in the driver, an older one and a newer one. Steps 1, 2, 5 and 6
are the same in both. Steps 3, 4 and 7 are the newer variant; the older one
sets no direction bits in the driver and hands mapping to the IOMMU layer by a
different call. For Flush, both variants give byte 1 = 0. Which variant runs on
J614s is not established here (see "Not established").

1. It starts from an **all-zero** entry on every submission, so nothing is
   carried over from the previous command in the same tag slot.
2. **Bytes 0–3 are a copy of SQE DWORD0:** byte 0 = opcode, byte 1 = DWORD0
   bits 15:8, bytes 2–3 = command ID. The Flush and Read command builders put
   nothing in DWORD0 bits 15:8 except an optional bit 13. So byte 1 starts
   as 0x00 (or 0x20; see below).
3. **The direction bits are then ORed into byte 1**, but only when the request
   has a data buffer:
   - buffer direction device→memory (read): byte 1 |= **0x01**
   - buffer direction memory→device (write): byte 1 |= **0x02**
   - bidirectional: both.

   These match Linux's `APPLE_ANS_TCB_DMA_FROM_DEVICE` (bit 0) and
   `APPLE_ANS_TCB_DMA_TO_DEVICE` (bit 1).
4. **The special case for data-less commands:** if the request has no
   buffer and no PRP list, the driver sets the page count to 0 and explicitly
   clears byte 1 bits 0 and 1 (mask `~0x300` on the first 32-bit word). That
   is the path Flush takes.
5. **Length (u16 at offset 4)** is written only when there is a buffer: CDW12
   bits 15:0 (zero-based block count), or for two vendor opcodes (`0x11`,
   `0xd1`) a page count derived from CDW10. For Flush it stays **0**.
6. **Offsets 0x38 and 0x3c** = CDW14 and CDW15. These are 0 for Flush. This is
   the field Linux calls `aes_iv`.
7. The PRP/page addresses are not written into the entry by the driver. A
   page list and a count go to the platform's protected IOMMU layer with the
   entry, and that layer fills the hardware TCB. For Flush the count is 0.

So for Flush: byte 0 = 0x00, byte 1 = 0x00, length = 0, PRPs = none, and
everything else zero.

## Bearing on our encodings

| Encoding | dma_flags | TCB zeroed | Result |
|---|---|---|---|
| T6040 apple.c (211 run 1) | 0x01 FROM_DEVICE | no | status 2 |
| m1n1 proxy (5006) | 0x03 | yes | status 2 |
| `flush-tcb.patch` (unused) | 0x03 | yes | not run; same as m1n1, expect status 2 |
| `flush-nodma.patch` (5023) | **0x00** | **no** | not run; matches macOS except for the zeroing |
| macOS | **0x00** | **yes** | (reference) |

Supporting detail: 5006 also saw m1n1's admin delete-SQ/CQ fail with status 2.
Those commands are data-less too, and m1n1 gave them dma_flags 3. The macOS
shutdown path issues delete-SQ and delete-CQ through the same builder, so they
also go out with dma_flags 0. If the dma_flags theory holds, an m1n1 probe with
dma_flags 0 for data-less commands should fix the deletes as well as Flush.
That is a cheap second prediction for the same rig run.

**Suggested adjustment to `flush-nodma.patch` (not made here):** also
`memset` the TCB before filling it, as macOS does every time. As written, the
patch leaves the bytes Linux does not set (the IV area at 0x38–0x3f and the
unknown fields) with whatever the previous command in that tag slot left
there. That is harmless if the IV area is always zero on our path, but zeroing
removes the variable.

## Other encoding facts found on the way (not needed for 5023)

- The macOS Flush builder writes **CDW10 = 1** ("barrier" flush) when the
  controller advertises a barrier capability (a controller flag bit, value not
  established) and the caller asks for a barrier. Otherwise it writes 0.
  Standard NVMe has no meaning for CDW10 in Flush. If dma_flags 0 alone still
  returns status 2, try CDW10 = 1 next.
- An optional request flag maps to SQE **DWORD0 bit 13** (TCB byte 1 bit 5,
  0x20) on Flush, Read and Write. None of the request-flag writers checked so
  far sets it. Its meaning is unknown; leave it 0.
- The embedded block-device layer's synchronize call can **return success
  without sending any command**, depending on a per-namespace option set at
  creation. So macOS may not flush ANS2 at all in normal operation and may rely
  on the clean-shutdown path (delete IOSQ/IOCQ, CC.SHN = 1, poll CSTS.SHST = 2),
  as our r3 run did. Which way that option is set on J614s is not established.
- FUA on writes is CDW12 bit 30, set only when the caller asks for it.

## Not established

- Which of the macOS ANS controller variants J614s instantiates. The split
  kext binaries do not contain the IOKit matching personalities, so this needs
  either the `__PRELINK_INFO` of the full kernelcache or a macOS `ioreg` on the
  machine. Both TCB-building variants give a Flush entry with dma_flags 0.
  The plain variant does not build a TCB in the driver at all.
- What the protected IOMMU layer does to the entry before it reaches hardware.
  The claim that hardware byte 1 is 0 for Flush is inferred from the entry the
  driver hands over.
- Whether ANS2 actually accepts the Flush with dma_flags 0, and whether that
  Flush makes the volatile cache durable. 5023's run settles both.
