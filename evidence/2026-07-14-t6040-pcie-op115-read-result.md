# T6040 PCIe operation-115 read-only result

Reviewed and run once on 2026-07-14 under rig ticket 002. **Bounded read-side
stall; no retry.** The run repeated the live-proven prefix and replaced the
first PHY-IP PLL RMW with one ADT-derived 32-bit read.

## Exact approved artifacts

- m1n1 main commit: `d1494f5a6867f4ffbeb87171afc992356b2fa7be`
- main `build/m1n1.bin` SHA-256:
  `5616b05fdd21a35990102ce8b711920ec8c442f75c89ce6cfe27da2f24adef67`
- Linux `Image` SHA-256:
  `14da8640398fc64b89d9241a75be0ffc8d4260b681068a3c27251cc79c3abaf4`
- reviewed PCIe-free `t6040-j614s-dcuart.dtb` SHA-256:
  `b3858f60aa96ab81f7314659284174cb10ddcec061140c1c67d397f52d617814`
- `initramfs-dcuart.cpio.gz` SHA-256:
  `512c69da94884f3ea83f9a6a4ea0731dcad6b5aaa87eb875ca5a6d7b24c317ca`
- read-only manifest SHA-256:
  `4f377fad6b1e5107cb9167af19b3899719e4e2d8a11cffeabadabfe20b167524`

The independent review and the reason for pinning the changed base DTB are in
`done/2026-07-14-t6040-pcie-op115-cross-review.md`. The DTB has no PCIe host;
ANS/SART/NVMe are disabled. The candidate contains operations 1-114 unchanged,
one read at operation 115, and no operation 116.

## Live result

Operations 1-114 completed observably:

- the Apple-ordered PMGR, AXI, RC, CIO3, clkgen, and late `APCIE_PHY_SW`
  prefix;
- all five `apcie-phy-tunables` entries;
- the 100 MHz reference-clock acknowledgement;
- CLK0 and CLK1 request/acknowledgement;
- PHY reset release and T8122 pre-tunable control.

The final line was the marker emitted immediately before the only new access:

```text
TTY> tunable: apcie-phy-ip-pll-tunables[0] read-only addr=0x417040090 size=4 mask=0x1 value=0x1
```

No `read value=... done` line, L2C status line, exception, or later marker
followed. The proxy request remained blocked until the host-side uploader was
terminated. Therefore the 32-bit read itself does not complete at this point
in m1n1's sequence. The previous combined `mask32()` failure was read-side; it
cannot be attributed to the write half of the RMW.

The experiment executed no write at `0x417040090`, no PLL entry 1 or later, no
AUSPMA tunable, no post-tunable PHY or RC operation, no port access, PERST#,
RID2SID/MSIMAP, config space, Linux PCIe, NVMe, or storage access. Linux did not
hand off.

Two attempts before the recorded run failed locally because the automation
process reaped kisd and left a stale `/tmp/m1n1` symlink. Neither attempt opened
the pty or chainloaded the candidate, so neither reached the rig experiment.
Keeping the console helper's process group alive restored the documented pty
discipline; the single successful chainload above is the only live run.

The sanctioned DebugUSB reboot then restored a fresh, quiescent `Running
proxy` target. Transcript:
`logs/t6040-console-20260714-pcie-op115-read.log`, SHA-256
`bdf7c2f8be0947c5da91c2c7f44f9e41a967a048ca35d0362782d8509bafafc8`
(411 lines, 26,720 bytes).

## Consequence

Do not attempt a write-only operation 115: a write-only test would not repair
the inaccessible read path and would discard the ADT RMW semantics. The next
step is offline route-finding for the missing PHY-IP access precondition or
Apple-only transition before `_initializePhy()` reaches its tunable callbacks.
Any reordered poll, added clock/reset transition, delay, or new register access
requires static evidence, an exact manifest, cross-review, and fresh approval.
