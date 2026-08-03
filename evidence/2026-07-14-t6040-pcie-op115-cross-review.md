# Ticket 013 cross-review: T6040 operation-115 read isolation

Reviewed by `sol` on 2026-07-14 for offline ticket 013 and rig ticket 002.
Verdict: **PASS**, limited to the exact artifact set below and one live run.

## Exact artifacts

| Artifact | SHA-256 |
|---|---|
| m1n1 main commit | `d1494f5a6867f4ffbeb87171afc992356b2fa7be` |
| `m1n1/build/m1n1.bin` | `5616b05fdd21a35990102ce8b711920ec8c442f75c89ce6cfe27da2f24adef67` |
| Linux `Image` | `14da8640398fc64b89d9241a75be0ffc8d4260b681068a3c27251cc79c3abaf4` |
| `t6040-j614s-dcuart.dtb` | `b3858f60aa96ab81f7314659284174cb10ddcec061140c1c67d397f52d617814` |
| `initramfs-dcuart.cpio.gz` | `512c69da94884f3ea83f9a6a4ea0731dcad6b5aaa87eb875ca5a6d7b24c317ca` |
| read-only access manifest | `4f377fad6b1e5107cb9167af19b3899719e4e2d8a11cffeabadabfe20b167524` |
| source J614s ADT | `87f5c391b0fc722bdaa0fdca468f160bccf1becaa2f81cec052c481b7c98f195` |

The earlier shared-PHY write-up pinned DTB `e7691e...`, but that file is no
longer present in the build output. The current default DTB was therefore
treated as a changed artifact, decompiled, reviewed, and pinned above rather
than silently substituted. It has no PCIe host node. Its ANS mailbox, SART, and
NVMe nodes are all `status = "disabled"`; the enabled DockChannel UART remains
in the standard polled mode. PMGR contains domain labels mentioning APCIE and
SPMI, but there is no enabled SPMI controller or storage consumer. Linux cannot
probe PCIe or NVMe from this DTB.

## Source and manifest review

- Main and curated `src/pcie.c`, `src/tunables.c`, and `src/tunables.h` are
  byte-identical and both builds succeed.
- The delta from the live-bounded `b5ced9ba` source adds no MMIO write. It
  parses the first local tunable entry, logs it, fences/checks the already used
  L2C status register, performs one width-selected read, checks status again,
  and returns from the T6040 path before the normal tunable application call.
- The first property entry supplies offset `0x90`, width 4, mask 1, value 1.
  Its base is obtained from ADT `reg[3] = <0x417040000 0x28000>`, producing the
  single new read at `0x417040090`.
- Apple 24D81 and 24G720 both map the second PHY ADT register for PHY-IP, use
  `ml_io_read32`/`ml_io_write32`, apply both PHY-IP tunable objects, and later
  read-modify-write offset `0x90`. The address and width are independently
  grounded; no offset was swept or invented.
- Regenerating the candidate manifest from the committed ADT reproduces SHA-256
  `4f377f...`. Its operations 1-114 are byte-for-byte identical to the
  live-proven prefix. Operation 115 is one 32-bit `READ`; there is no operation
  116.
- The return dominates the former PLL tunable RMW, AUSPMA tunables,
  post-tunable PHY controls, RC writes, every port access, PERST#,
  RID2SID/MSIMAP, config space, Linux PCIe, NVMe, and storage.
- No SPMI, PMU, charger, or NVRAM access is added. The experiment performs no
  blind MMIO and does not clear error status.

## One-run interpretation

- If the pre-read line is the final line, classify the boundary as read-side
  or missing preceding hardware state. Do not attempt a write or retry.
- If `read value=... done` prints, the read side is live and the previous
  combined RMW implicates its write side. The intentional return remains the
  endpoint; do not continue.
- If L2C status is nonzero, preserve the value and recover. Do not clear it or
  proceed.

This review does not approve a write-side isolation, changed ordering, added
delay/poll, different binary/DTB, or continuation past the one read. Any such
change requires a new manifest, review, and approval.
