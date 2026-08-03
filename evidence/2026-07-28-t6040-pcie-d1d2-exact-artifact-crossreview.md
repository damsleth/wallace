# Ticket 124 D1/D2 PCIe exact-artifact cross-review

Reviewer: `sol`
Scope: m1n1 commits `19edc72b85fcda63092de3b643092cc51d508281`
and `9c35cd2c7f34d94c89d79c5a20d9dee5b99f2b70`, exact shipped binary,
captured J614s ADT, paired `AppleT6040PCIe` kernelcache, and the hard-stop
boundary
Hardware touched: **none**

## Verdict

**PASS for the bounded D1/D2 artifact itself.** The two new RMW deltas and
the 1 us delay are exact matches for operations in Apple's T8132 sequence,
all target addresses remain ADT-derived, non-T6040 paths are unchanged, and
the candidate still performs only the existing read-only first-PhyIP probe
before returning.

This review does **not** make a live run ready. A separate rig ticket still
needs CJ's explicit plan approval and an exact manifest/command pinning the
Image, PCIe DTB, initramfs, and this m1n1 hash. The current preflight says
"boot exactly as 068" instead of restating those inputs. No `queue ready`
action was taken.

## Exact artifact and provenance

- shipped binary:
  `linux-build-out/m1n1-t6040-pcie-d1d2-19edc72b.bin`
- size: 1,097,728 bytes
- SHA-256:
  `0e065589c08a6c3186c0bc3eddeae9078a3d878597db60965b88511eb881daad`
- embedded version:
  `t6040-pcie-d1d2-19edc72b85fc`
- current committed in-tree `build/m1n1.bin` is byte-identical to the shipped
  binary.
- main commit changes only `src/pcie.c`, has CJ's required author/committer
  identity, and carries the correct sign-off.
- curated commit `9c35cd2c` has the same identity/sign-off and the exact same
  patch hunks.

An independent clean clone using the pinned nightly and version tag produced
the same 1,097,728-byte shape and identical PCIe executable/rodata sections,
including byte-identical `pcie_init_controller` machine code. The full image
hash differs across checkout paths because the current build does not remap
all build-path-sensitive objects; therefore this review does not overclaim a
portable whole-image rebuild. The shipped binary is nevertheless pinned and
matches the author's current committed-state build exactly.

## Independent primary-evidence check

From the paired kernelcache, fileset entry
`com.apple.driver.AppleT6040PCIe`:

### D1: clkgen bit 5

`ApplePCIEBaseT8132::_enableRootComplex(bool)`:

```text
0xfffffe0009b3620c  call _configPciePLLs
0xfffffe0009b36224  call clkgen read accessor, offset 0
0xfffffe0009b3623c  and w8, w8, #0xffffffdf
0xfffffe0009b36248  orr w8, w8, #0x20
0xfffffe0009b36254  call clkgen write accessor
0xfffffe0009b36258  begin final enableDeviceClock call
```

The candidate places:

```c
set32(clkgen_base + 0x0, BIT(5));
```

after the bounded clkgen lock poll and before PMGR clock-gate index 7. The
base comes from `adt_get_reg(..., APCIE_T6040_PCIECLKGEN_IDX == 6, ...)`.
The captured ADT independently resolves reg[6] to CPU-physical
`0x415044000`.

### D5: 1 us delay

In `_initializePhy`, after the bit-2 `sleep_b_sml_out` acknowledgement and
before setting request bit 1:

```text
0xfffffe0009b37028  mov w0, #1
0xfffffe0009b3702c  call IODelay
0xfffffe0009b37038  orr w8, w8, #2
0xfffffe0009b37048  write PhyPhy[0]
```

The candidate adds `udelay(1)` at precisely this T6040-only point.

### D2: clear bit 4

After the bit-3 `sleep_b_big_out` acknowledgement:

```text
0xfffffe0009b37380  and w8, w8, #0xffffffef
0xfffffe0009b37390  write PhyPhy[0]
0xfffffe0009b37394  IODelay(1)
```

This is a clear of bit 4, not the old T602x-derived bit 7. The candidate uses
`clear32(..., BIT(4))` only when `state->pcie_regs == &regs_t6040`; every
other SoC retains `APCIE_PHY_CTRL_RESET`/bit 7.

`regs_t6040.compat == APCIE_T8122` causes the existing ADT-derived reg[2]
base to receive the proven `+0x8000` PhyPhy offset, resolving this RMW to
CPU-physical `0x417008000`.

## ADT and scope checks

The captured J614s ADT independently reports:

- only `/arm-io/apcie0` exists among the four controller paths attempted by
  `pcie_init()`;
- compatible `apcie,t6040`;
- `lane-cfg = 0`, so the existing `rc_base + 4 = 0` is Apple-equivalent for
  this target;
- reg[2] `0x417000000`, reg[3] `0x417040000`, reg[5] `0x415046200`,
  reg[6] `0x415044000`, after the required `/arm-io` ranges translation;
- the first `apcie-phy-ip-pll-tunables` entry remains ADT-owned and resolves
  to reg[3]+`0x90` = `0x417040090`.

There is no new literal physical base in the patch.

The probe calls `tunables_read_first_local_addr_trace()`, which:

1. derives the first entry offset and width from the ADT;
2. checks pending L2C status;
3. performs exactly one width-selected read;
4. rechecks L2C status;
5. performs no write.

Both the success and error branches return `-1`; the T6040 path cannot fall
through to PLL/AUSPMA writes, post-PhyIP D6/D7/D8, root-complex completion,
port reset, config space, link, Linux, storage, or WiFi. The other three
controller paths are absent in this ADT, so the top-level loop adds no second
hardware surface after `/arm-io/apcie0` returns.

## Risk and remaining live gate

This is not ticket 068 unchanged: D1 changes clkgen[0] bit 5 and D2 changes
the release from bit 7 to bit 4, both before the previously dead aperture.
The touched register words were already in the live-proven prefix, but these
are still attended-only PCIe PHY/clock writes. The expected negative outcome
is the known non-returning read, recoverable through the sanctioned DebugUSB
reboot; an unexpected SError/reset/lost tether remains a stop condition.

Before any run, create or amend a rig ticket with:

- this exact m1n1 SHA-256;
- the exact ticket-068 Image, PCIe DTB, and initramfs hashes (or newly
  reviewed replacements);
- the literal chainload command and fresh-window requirement;
- CJ approval and `reviewed_by=sol`;
- PASS/FAIL transcript strings and mandatory recovery/release state.

One minor source-comment defect is non-blocking: the D1 comment says it is
"the only Apple operation missing" before first PhyIP access even though D2
is also missing. The executable behavior and surrounding preflight correctly
name both.
