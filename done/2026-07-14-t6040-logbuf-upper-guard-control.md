# T6040 stage-2 log-buffer upper-guard control

Prepared 2026-07-14. **Not approved or run.** This control tests the now-bounded
cause of the zero-PCIe-write trace SError: wrapping m1n1's stage-2 log ring when
it occupies the final physical page of normal RAM.

## Exact build

- m1n1 main commit: `a61fd099` (`v1.6.0-75-ga61fd099`)
- main `build/m1n1.bin` SHA-256:
  `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b`
- curated commit: `cb64c3a0`
- curated `build/m1n1.bin` SHA-256:
  `566f4f72f0adb87d5410942c9502c1e29f51899bd16126d7fec38f003ca3804b`
- main and curated `src/kboot.c`, `src/pcie.c`, `src/tunables.c`, and
  `src/tunables.h` are byte-identical.

Use only the main binary. Boot the proven PCIe-free base DTB, SHA-256
`e7691ee49ed88114154061aeaf29309e3d817ae3ae89d7196bf7ef02a9b3dc9a`.

## Exact change and memory layout

The prior binary allocated 16 KiB at the exclusive top of normal RAM:

```text
active log ring: 0x105ce7a4000..0x105ce7a8000
top of RAM:                         0x105ce7a8000
```

`a61fd099` asks the existing top-of-memory allocator for 32 KiB but exposes only
the lower 16 KiB as the active `m1n1_stage2.log` phram. On this boot layout the
expected result is:

```text
allocator guard:  0x105ce79c000..0x105ce7a0000
active log ring:  0x105ce7a0000..0x105ce7a4000
unused upper page:0x105ce7a4000..0x105ce7a8000
top of RAM:                         0x105ce7a8000
```

Both the active page and upper padding remain outside Linux's `/memory` range.
Only the active 16 KiB is advertised as the phram log. This costs 16 KiB of RAM
and does not add an MMIO address, system-register access, or hardware write.

The binary retains the exact zero-PCIe-write dry-run path from `3e772779`: it
reads the in-memory ADT and prints all 77 AXI pre/`done` pairs, but returns before
PCIe PMGR, AXI, RC, CIO3, clkgen, PHY, port, PERST#, RID2SID, or MSIMAP access.
The base DT has no Linux PCIe host node.

## Interpretation and approval gate

- If all 77 pairs and the dry-run completion marker print, followed by the
  boot-proven base Linux handoff, the top-boundary log-ring fault is fixed.
- If an SError remains, preserve the exact address and output boundary and
  continue investigating the generic console ring without PCIe MMIO.

This exact main binary requires explicit approval for one live run. Stop after
the result and recover through the sanctioned DebugUSB helper if necessary.
NVMe and all namespace/mount/repair/format operations remain out of scope.
