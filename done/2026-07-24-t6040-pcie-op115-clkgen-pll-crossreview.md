# T6040 ticket 068 PCIe clkgen/op-115 cross-review (2026-07-24)

Reviewer: Sol. Result: **PASS for one exact bounded run**.

This is not a write-free test. The exact m1n1 object adds two clkgen writes to
the previously live-proven prefix:

```text
reg[6] + 0x4: set bit 31
reg[6] + 0x0: replace low three bits with 1
```

It then polls bit 31 at `reg[6]+0x0` with a finite bound. The base is obtained
from J614s ADT `apcie` reg index 6; the offsets, masks, and values match the
paired `ApplePCIEBaseT8132::_configPciePLLs` decode recorded by ticket 058.
All other writes before op 115 are the same prefix that already reached the
first PHY-IP read on this rig. The candidate still performs exactly one
32-bit read of the first PHY-IP PLL tunable at `reg[3]+0x90` and returns before
any PHY-IP write, port, PERST, RID/SID, config-space, link, ANS, or NVMe action.

The current m1n1 source differs from candidate commit `e4671e08` only by
documentation commits. Its build artifacts exactly match:

- `m1n1.bin`
  `3e0c90af77e1f13930e432f3ed124215d2ddeb6de050c8b29b90173a2818f31f`
- `m1n1.macho`
  `2373e435677d5cf97ba9e2eee065abb7d659a7badcc7bd687896f1ae59ea5ae3`

The remaining exact inputs also match the manifest:

- Image `aca9a55614b1a588e33cf8a41ad01108d0d3de15b77c8b047991bd04b8b44000`
- PCIe-free DTB
  `b3858f60aa96ab81f7314659284174cb10ddcec061140c1c67d397f52d617814`
- initramfs
  `512c69da94884f3ea83f9a6a4ea0731dcad6b5aaa87eb875ca5a6d7b24c317ca`

One run may distinguish lock timeout, successful op-115 read, or the known
read-side hang. Stop and recover on SError, missing bounded output, reset, or
nonzero L2C status. No second candidate may follow in the same run.
