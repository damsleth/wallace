# T6040 PCIe operation-115 static analysis and read-only isolation

Prepared 2026-07-14. This is an offline result for tickets 041 and 013 and a
cross-review packet for rig ticket 002. **It has not been booted.** The rig
ticket remains proposed; another agent must review this exact manifest and CJ
must approve the pinned image before any live run.

## Outcome

The operation-115 address and width are not guessed. Apple maps the second PHY
ADT register and uses 32-bit I/O for PHY-IP accesses. On J614s that register is
ADT `reg[3] = <0x417040000 0x28000>`, so Apple PHY-IP offset `0x90` is physical
address `0x417040090`.

Apple's T8132/T6040 initialization applies the `PHY IP PLL` and `PHY IP AUSPMA`
tunable objects before a later explicit 32-bit read-modify-write at PHY-IP
offset `0x90`. The same call order and access width are present in both locally
paired Apple kernelcaches inspected below. This rules out an invented aperture
or width as the explanation for the m1n1 stall, but it does not prove that the
aperture is live at precisely m1n1's operation-115 point.

The prior traced helper combined its read and write in `mask32()`. Its missing
`done` line therefore cannot distinguish a read-side stall from a write-side
stall. The safest useful follow-up is a single read-only access: repeat the
live-proven operations 1-114, read `0x417040090` once as a 32-bit value, and
return before the operation-115 write or any later access.

## Apple static evidence

No Apple binary is committed. Two J614s/mac16j kernelcaches from this machine's
Preboot volume were extracted to `/tmp` and inspected there:

| macOS | Build | Extracted Mach-O SHA-256 |
|---|---|---|
| 15.3.2 | 24D81 | `32f34a76ec36f7e7926507de746406ca797e8de0935078706e8a0bd43c13d966` |
| 15.7.7 | 24G720 | `0cfe07102ffc0bce46d7075ca85081a672be577293c87c18aa58e49a473f25fa` |

In 24G720:

- `AppleT6040PCIe::start()` installs the T6040 register-map layout. Its PHY
  range begins at DT index 2 and ends at index 3.
- `ApplePCIEBaseT8132::configure()` calls the virtual PHY-map accessor with
  index 1. `dtRegMapPhyIndex(1)` therefore resolves to DT index 3, maps it, and
  stores the resulting virtual base in the field used by PHY-IP I/O.
- `_readPhyIPReg(unsigned int)` loads that base, adds the unsigned offset, and
  calls `ml_io_read32`.
- `_writePhyIPReg(unsigned int, unsigned int)` uses the same base and calls
  `ml_io_write32`.
- `_initializePhy()` applies the property objects labelled `PHY IP PLL` and
  `PHY IP AUSPMA`, then calls `_readPhyIPReg(0x90)`, clears bit 16, and calls
  `_writePhyIPReg(0x90, value)`.

The 24D81 image independently has the same second-PHY mapping, the same 32-bit
read/write helpers, the same two tunable applications, and the same later
`read(0x90) -> clear bit 16 -> write(0x90)` sequence. The two versions differ
in unrelated T6040 port-layout details, so the stable PHY-IP sequence is the
useful cross-version result.

This evidence does not justify moving the existing PHY clock-enable poll at
`0x417008008` bit 0 ahead of the tunables: Apple applies both PHY-IP tunable
objects before its later PHY-IP `0x90` RMW, and the saved ADT does not prescribe
such a reordered poll. No new poll, delay, or MMIO offset is proposed.

## ADT manifest audit

The existing deterministic shared-PHY manifest remains byte-for-byte
reproducible from the committed J614s ADT:

- ADT SHA-256: `87f5c391b0fc722bdaa0fdca468f160bccf1becaa2f81cec052c481b7c98f195`
- 351-operation manifest SHA-256:
  `d4496968ee8fc1202bd4d47247fc6bbaa36f0a3f7cc872a81efabe72327c50fc`
- operations 115-142: 28 `apcie-phy-ip-pll-tunables` RMWs
- operations 143-346: 204 `apcie-phy-ip-auspma-tunables` RMWs
- all 232 accesses are 32-bit; 230 addresses are unique
- minimum address: `0x417040090`; maximum address: `0x417066404`
- every access, including its full width, is inside ADT `reg[3]` range
  `[0x417040000, 0x417068000)`

Regenerate and verify the old manifest with:

```sh
git -C ~/Code/linux show feature/m4-m5-minimal-device-trees:j614s.adt \
  | scripts/t6040-pcie-write-plan.py --stop-before-ports \
  > /tmp/t6040-shared-phy.tsv
cmp /tmp/t6040-shared-phy.tsv done/2026-07-14-t6040-pcie-phy-diagnostic.tsv
```

## Exact read-only candidate for ticket 002

The candidate is committed in both m1n1 worktrees:

- main commit: `d1494f5a6867f4ffbeb87171afc992356b2fa7be`
- main `build/m1n1.bin` SHA-256:
  `5616b05fdd21a35990102ce8b711920ec8c442f75c89ce6cfe27da2f24adef67`
- curated commit: `c5d9de6c116b2aeded3d3f1014fc5068cc311192`
- curated `build/m1n1.bin` SHA-256:
  `bbf6dc7f8aa451ae8698aa732c7dd7dc8b894ccc450ab6aba55165843d0dbae1`
- main and curated `src/pcie.c`, `src/tunables.c`, and `src/tunables.h` are
  byte-identical; both builds completed successfully

Use only the main binary after cross-review and explicit approval. The exact
access manifest is `2026-07-14-t6040-pcie-op115-read-manifest.tsv`, SHA-256
`4f377fad6b1e5107cb9167af19b3899719e4e2d8a11cffeabadabfe20b167524`.
It contains operations 1-114 unchanged from the live-proven prefix followed by:

```text
115  phy  apcie-phy-ip-pll-tunables[0] read-only  0x417040090  4  READ
```

The code obtains the offset and width from the first ADT property entry and the
base from ADT `reg[3]`. It prints the full entry before the access, fences and
checks the already proven read-only L2C error-status register, performs one
width-selected read, fences/checks status again, prints the value, and returns
from PCIe initialization. It cannot execute the operation-115 write, entries
116-351, a port access, PERST#, RID2SID/MSIMAP, config space, Linux PCIe, NVMe,
or storage access. Use the same PCIe-free DTB, kernel, initramfs, and 16 KiB
log-ring guard pinned in the preceding shared-PHY result.

Regenerate the candidate manifest with:

```sh
git -C ~/Code/linux show feature/m4-m5-minimal-device-trees:j614s.adt \
  | scripts/t6040-pcie-write-plan.py --isolate-op115-read \
  > done/2026-07-14-t6040-pcie-op115-read-manifest.tsv
```

Pre-register the interpretation:

- no `read value=... done` line: the read side or its preceding hardware state
  is the boundary; do not attempt the write;
- a read value followed by the intentional stop: the read side is live and the
  previous combined RMW implicates its write side;
- nonzero L2C status before or after the read: preserve and report it; do not
  clear status or continue.

Any write-side isolation, reordered poll, new delay, or continuation past this
single read is a separate manifest requiring fresh static evidence, independent
cross-review, and explicit approval.
