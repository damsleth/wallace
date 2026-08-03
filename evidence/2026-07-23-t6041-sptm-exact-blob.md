# Exact T6041 SPTM NVMe decode (2026-07-23)

Ticket 052 is complete. The exact `sptm.t6041.release.im4p` was range-fetched
from the pinned J614s restore IPSW, decompressed, and compared with the T8132
proxy used by tickets 051 and the original guarded-backend decode. Proprietary
payloads remain under `/private/tmp`; only the extractor and this provenance
record enter Git.

## Provenance

- restore: macOS 26.5.2, build 25F84;
- IPSW: `UniversalMac_26.5.2_25F84_Restore.ipsw`, 19,769,902,281 bytes;
- `BuildManifest.plist` SHA-256:
  `a6e764ca158e10ea2ace9b74701f445eefbf012c9cdb5aaa616aa10a0b5197ef`;
- member: `Firmware/sptm.t6041.release.im4p`;
- ZIP member size/CRC32: 192,376 bytes / `77f3bd1f`;
- IM4P SHA-256:
  `f78979b6cd9d7c0c5d13abf58229ec1ffc489751324708e1536cfba399ea4938`;
- decompressed Mach-O size: 1,228,832 bytes;
- decompressed SHA-256:
  `0755358864e4d9e24255dd126d41d0a26a803fcbac0593898f76a7ba644af01a`.

The range extractor is `scripts/t6040-extract-sptm-firmware.py`, SHA-256
`9662ee56795cb59c1866b51fe1c225b6c0ae0b9f20513385b87c8bb79d85fa85`.
It pins URL, archive size, manifest hash, product/build, member size, and CRC;
`zipfile` verifies decompression and CRC. A second invocation reproduced the
same member hash.

## Exact handler map

The Mach-O keeps the same `0xfffffff027004000` load base. Apple `objdump`
locates the exact T6041 handlers at:

| op | T6041 entry | T8132 entry | role |
|---:|---|---|---|
| 0 | `0xfffffff0270c7938` | `0xfffffff0270bb72c` | initialise |
| 1 | `0xfffffff0270c71d8` | `0xfffffff0270bb00c` | establish TCB/pages |
| 2 | `0xfffffff0270c6b90` | `0xfffffff0270ba808` | invalidate/complete TCB |
| 3 | `0xfffffff0270c6a70` | `0xfffffff0270ba6e8` | queue entries + protocol |
| 4 | `0xfffffff0270c66ac` | `0xfffffff0270ba218` | admin queues |
| 5 | `0xfffffff0270c64d8` | `0xfffffff0270b9fe4` | IOQA |
| 6 | `0xfffffff0270c626c` | `0xfffffff0270b9cb8` | IOSQ |
| 7 | `0xfffffff0270c5fec` | `0xfffffff0270b9978` | IOCQ |
| 8 | `0xfffffff0270c5c38` | `0xfffffff0270b9530` | ANS SHA |

The op-index ordering, allowed-function bit tests, and every argument register
from ticket 051 are unchanged. In particular, exact T6041 op 4 consumes ASQ
PA/depth in `x0/x1` and ACQ PA/depth in `x2/x3`; op 3 consumes queue entries
and protocol version; op 1 consumes qid/cid/TCB PA/page-list PA/count.

`nvme_bootstrap` moves from T8132 entry `0xfffffff0270bb92c` to T6041 entry
`0xfffffff0270c7a1c`. The ADT policy keys and nine-handler initialization are
structurally unchanged. Numeric offsets from the proxy blob must no longer be
used for exact-target work.

## Variant delta

The sorted NVMe string inventory is otherwise identical, but T6041 adds two
guarded violations:

- `VIOLATION_NVME_ILLEGAL_SEG_COUNT`;
- `VIOLATION_NVME_INVALID_NLB`.

This is a real strengthening of the TCB/command validation surface, not an ABI
change. Any future shim must preserve these checks; it must not copy only the
older T8132 policy.

The result closes the exact-blob uncertainty, but does not solve outer IOMMU
dispatch or caller-domain provenance. `sptm_nvme_call()` remains deliberately
stubbed.
