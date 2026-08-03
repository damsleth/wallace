# T6040 stage-2 log-buffer upper-guard control

Prepared and run once with explicit approval on 2026-07-14. This control tested
the bounded cause of the zero-PCIe-write trace SError: wrapping m1n1's stage-2
log ring when it occupied the final physical page of normal RAM.

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

## Live result

The exact main binary was approved for one run. The observed layout matched the
prediction:

```text
FDT: Usable memory is ...0x105ce79c000
FDT: Adding reserved-memory node flash@105ce7a0000
     (105ce7a0000..105ce7a4000) to RAM map
```

Every dry-run AXI entry `[0]` through `[76]` printed `done`, followed by:

```text
pcie: T6040 AXI trace dry run complete; no PCIe MMIO
Preparing to boot kernel ...
*** t6040 Linux DockChannel UART console alive ***
BusyBox ... built-in shell (ash)
/ #
```

No SError occurred. The result proves the top-boundary log-ring attribution and
the 16 KiB upper guard. It also proves that none of the previous `[70]` failures
can implicate a PCIe RMW. No PCIe PMGR/controller/PHY/port access, Linux PCIe,
NVMe, or storage operation ran.

- m1n1 transcript: `logs/t6040-console-20260714-logbuf-upper-guard.log`,
  SHA-256
  `2e8624d795bc6bddab24b932a530bf7f992f35732402ed041bfc308857260d63`
  (383 lines, 24,915 bytes);
- Linux transcript: `logs/t6040-linux-20260714-logbuf-upper-guard.log`, SHA-256
  `6c6c0073bacbec235a9e54c6535a646f34ad372792c02ee30a5cb1fc5983d8e9`
  (36 lines, 2,255 bytes).

Main `f46d6e35`, binary SHA-256
`8fd7319047187f9ca05a6924462a4f24360fcc1d9e4279b089dc83a5acb05744`,
restores the existing Apple-ordered 105-operation PCIe path while retaining this
guard and the stop-before-PHY boundary. It requires separate explicit approval;
exact gate: `2026-07-14-t6040-pcie-guarded-clock-diagnostic.md`.
