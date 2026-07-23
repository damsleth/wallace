# SPTM NVMe/SART structural diff: T8132, T8140, T6041

Date: 2026-07-23
Ticket: 054
Scope: static firmware comparison only

The three independently packaged SPTM images retain the same NVMe/SART
dispatch architecture. T8132 was a sound proxy for the op numbering and
argument ABI, but not for numeric addresses or the complete validation policy.

## Inputs

| SoC | decompressed bytes | SHA-256 |
|---|---:|---|
| T8132 (M4) | 1,130,528 | `a265ec66a6b61b7d75704ac68f5dbdb8ab6cecce9a6605e78f39b89baaa979cb` |
| T8140 (A18 Pro) | 1,114,144 | `3292847e931ad6188b8dc8539646b66cdef2a5096ac695d96783c1adde5c1b0e` |
| T6041 (M4 Max family) | 1,228,832 | `0755358864e4d9e24255dd126d41d0a26a803fcbac0593898f76a7ba644af01a` |

All are arm64e Mach-O executables loaded at `0xfffffff027004000`. The Apple
payloads and decompressed binaries remain outside Git.

## Stable ABI

Across all three images:

- domain ids retain the published ordering: SPTM 0, XNU 1, TXM 2, SK 3,
  XNU-hibernate 4;
- IOMMU dispatch table 5 is SART and table 6 is NVMe;
- IOMMU id 1 is SART and id 2 is NVMe;
- NVMe registers XNU/XNU-hibernate permission mask `0x12`;
- `func_state[0..8]` is the same allowed-function state machine;
- op roles remain init, SetTCB, invalidate TCB, configure, admin queues, IOQA,
  IOSQ, IOCQ, and ANS SHA;
- guarded argument consumption matches ticket 051 in all three images;
- `sptm_nvme_map_pages`, `sptm_nvme_unmap_pages`, queue/CID validators, and
  SART violation handling remain part of the same security boundary.

T8132 and T8140 have byte-identical sorted NVMe/SART symbol-and-violation
inventories despite different overall Mach-O sizes. T6041 retains that entire
inventory and adds `VIOLATION_NVME_ILLEGAL_SEG_COUNT` and
`VIOLATION_NVME_INVALID_NLB`.

## Relocated implementation

| op | T8132 | T8140 | T6041 |
|---:|---|---|---|
| 0 | `0xfffffff0270bb72c` | `0xfffffff0270bb1bc` | `0xfffffff0270c7938` |
| 1 | `0xfffffff0270bb00c` | `0xfffffff0270baa9c` | `0xfffffff0270c71d8` |
| 2 | `0xfffffff0270ba808` | `0xfffffff0270ba44c` | `0xfffffff0270c6b90` |
| 3 | `0xfffffff0270ba6e8` | `0xfffffff0270ba32c` | `0xfffffff0270c6a70` |
| 4 | `0xfffffff0270ba218` | `0xfffffff0270b9f68` | `0xfffffff0270c66ac` |
| 5 | `0xfffffff0270b9fe4` | `0xfffffff0270b9d94` | `0xfffffff0270c64d8` |
| 6 | `0xfffffff0270b9cb8` | `0xfffffff0270b9b28` | `0xfffffff0270c626c` |
| 7 | `0xfffffff0270b9978` | `0xfffffff0270b98a8` | `0xfffffff0270c5fec` |
| 8 | `0xfffffff0270b9530` | `0xfffffff0270b94e8` | `0xfffffff0270c5c38` |
| bootstrap | `0xfffffff0270bb92c` | `0xfffffff0270bb2a0` | `0xfffffff0270c7a1c` |

The non-uniform relocation proves why raw offsets must always be tied to an
exact firmware hash. The stable contract is semantic—dispatch ids, op index,
arguments, and state transitions—not a shared text address.

## Consequence for the shim route

The three-image result hardens the op map against a single-image artifact.
It does not make direct GENTER viable: outer XNU IOMMU marshalling and caller
domain provenance remain unknown. A shim must also preserve T6041's stricter
segment-count/NLB checks and the SoC-specific DART/SART/register layout learned
by `nvme_bootstrap`; copying T8132 machine offsets would be invalid.

The repository's `sptm_nvme_call()` therefore remains a stub. No live action,
MMIO, storage access, or external post occurred.
