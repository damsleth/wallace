# T6040 PCIe zero-write trace control

Prepared and run once with explicit approval on 2026-07-14. This control
distinguishes a console/trace-volume artifact from the delayed PCIe SError seen
in the write-bearing traces.

## Exact build

- m1n1 main commit: `3e772779` (`v1.6.0-72-g3e772779`)
- main `build/m1n1.bin` SHA-256:
  `c9296b8d1ca146a32c7a1ba1bf17b7091281588ab90d16a69f0718c5a8fa04ea`
- curated commit: `841ca99d`
- curated `build/m1n1.bin` SHA-256:
  `6bde25019f51b9cb92f999394da2885cc91c01bcefd1b0529ef328cf4dc67e3d`
- main and curated `src/pcie.c`, `src/tunables.c`, and `src/tunables.h` are
  byte-identical; their build tags account for the binary-hash difference.

Use only the main binary for a live control. Boot the proven PCIe-free base DTB,
SHA-256
`e7691ee49ed88114154061aeaf29309e3d817ae3ae89d7196bf7ef02a9b3dc9a`.

## Static write boundary

This is zero **PCIe** MMIO, not a claim that ordinary boot contains no hardware
access. The already boot-proven MCC/cache/clock/USB kboot setup still precedes
`pcie_init()`.

For the T6040 controller, `pcie_init_controller()` performs only ADT memory
lookups through the existing port-register-count validation. It then calls
`tunables_trace_local_dry_run()` and returns before:

- `pmgr_adt_power_enable_index()` or any PCIe clock-gate RMW;
- the first AXI controller read or write;
- RC, CIO3, clkgen, PHY, port, PERST#, RID2SID, or MSIMAP access.

The dry-run helper reads the AXI property and reg base from the in-memory ADT,
calculates each displayed address, and prints the same 77 pre/`done` line pairs.
Its internal `write=false` path cannot call `mask8/16/32/64`, does not execute
the barrier/L2C sampling used by the write trace, and performs no MMIO read.

There is deliberately no extra marker before entry `[0]`, so the console stream
from `pcie: Initializing t6040 PCIe controller` through the trace pairs matches
the previous traces byte-for-byte. A completion marker is printed only after
entry `[76]`, then the controller returns. The base Linux boot may continue;
its DT has no PCIe host node and is already boot-proven.

## Live result

The exact main binary was approved for one run. It produced `[70] done`, then
the same asynchronous SError before `[71]`. The completion marker did not run.
No PCIe PMGR, controller MMIO, Linux PCIe, NVMe, or storage access occurred.

```text
+PC:       0x10004b371bc (rel: 0x2b1bc)
+ESR:      0xbe000000 (SError)
+L2C_ERR_STS: 0x82
+L2C_ERR_ADR: 0x3606905ce7a8000
+L2C_ERR_INF: 0x1000000001
```

The relative PC symbolizes to the proxy `P_CALL` site and is only the delayed
delivery point. Sanctioned DebugUSB recovery restored a fresh quiescent proxy.
Transcript: `logs/t6040-console-20260714-pcie-trace-dry-run.log`, SHA-256
`52431e2a9a7d87642fde917419f3e8e666672434953cad23466c13b61968742d`
(407 lines, 25,940 bytes).

## Log-buffer attribution

This result exonerates all PCIe writes. The remaining evidence converges on the
m1n1 stage-2 log ring:

- startup reports the top of normal RAM as `0x105ce7a8000`;
- kboot allocates the 16 KiB log buffer at
  `0x105ce7a4000..0x105ce7a8000`;
- saved exception registers repeatedly contain the buffer base, while every
  `L2C_ERR_ADR` contains its exclusive upper boundary;
- once the log device becomes writable, `iodev_console_write()` flushes its
  retained 8,192-byte console backlog into the new ring;
- the output from the buffer announcement through `[70] done` is identically
  9,274 bytes in all four traced runs;
- backlog plus new output crosses 16,384 bytes during `[61] done`; the SError is
  delivered after another 1,082 bytes at `[70] done`.

Main `a61fd099`, binary SHA-256
`1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b`,
reserved an additional unused 16 KiB above the log ring, kept its active page
away from the physical top-of-RAM boundary, and repeated this same zero-PCIe-
write trace. All 77 entries completed and base Linux reached BusyBox, proving
the fix. Full result: `2026-07-14-t6040-logbuf-upper-guard-control.md`.
