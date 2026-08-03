# T6040 PCIe AXI barrier diagnostic

Prepared and run once with explicit approval on 2026-07-14. This bounded live
diagnostic followed the Apple-accurate staged-clock run that repeated the
asynchronous SError after AXI tunable `[70]`.

## Exact build

- m1n1 main commit: `88ce1ee3` (`v1.6.0-68-g88ce1ee3`)
- main `build/m1n1.bin` SHA-256:
  `2997b07647007f99df6ad094a2da55d66a9f7accd6758bb134d3fa92b76d0c72`
- curated commit: `82d99f17`
- curated `build/m1n1.bin` SHA-256:
  `463219a9d9a26f43ee8a92ddb7ce8ec23d55f61f81cfd4a49051d7c139fbe5f1`
- the two `src/tunables.c` and `src/pcie.c` files are byte-identical; different
  build tags account for different binary hashes.

Use the main binary for the live run. Boot only the previously proven PCIe-free
base DTB, SHA-256
`e7691ee49ed88114154061aeaf29309e3d817ae3ae89d7196bf7ef02a9b3dc9a`.

## Bounded behavior

The MMIO operation set and order are unchanged from
`2026-07-14-t6040-pcie-clock-diagnostic.tsv`, SHA-256
`ce86e51aa3d278da1d9ef9eb35fca3208859f4993480de5b6af3268dc03ef4e6`:

- 12 recursive PMGR RMWs for clock gates 0–6;
- 77 ADT-supplied AXI RMWs and one RC write;
- only if those complete, seven CIO3 RMWs and one clkgen RMW;
- only if those complete, seven recursive PMGR RMWs ending at the late
  `APCIE_PHY_SW` gate.

The diagnostic still returns before operation 106, the first PHY write. It
cannot reach PHY initialization, ports, PERST#, RID2SID/MSIMAP, Linux PCIe, or
storage.

The only new behavior is CPU-side observation around each traced tunable set:

1. `dsb sy`, then read `SYS_IMP_APL_L2C_ERR_STS` before the first RMW;
2. after every existing RMW, `dsb sy`, then read the same status register;
3. if the read is nonzero, print the property/index and return immediately;
4. never clear or write the L2C error-status register.

The pre-set sample separates a pending error from the preceding PMGR clock
work. Each post-RMW barrier forces that transaction to complete before the
read-only status sample. If the asynchronous exception arrives at the barrier,
the last pre-write trace line still identifies the exact attempted RMW.

## Live result

The exact main binary and unchanged manifest were approved for one run. AXI
`[70]` at `0x4160013fc` printed `done`. Since that line is emitted only after
`dsb sy` returns and `L2C_ERR_STS` reads as zero, neither the preceding PMGR
work nor any completed write through `[70]` had a visible pending status at its
sample point. Before `[71]` was announced, m1n1 delivered the same asynchronous
SError:

```text
+PC:       0x100051707a0 (rel: 0x307a0)
+ESR:      0xbe000000 (SError)
+L2C_ERR_STS: 0x82
+L2C_ERR_ADR: 0x3606905ce7a8000
+L2C_ERR_INF: 0x1000000001
```

The relative PC symbolizes to `uartproxy_run()` and is another asynchronous
delivery location, not the causal MMIO instruction. No nonzero diagnostic
sample printed. The uploader stopped without Linux handoff; `[71]`, CIO3,
clkgen, the late gate, PHY, ports, PERST#, Linux PCIe, NVMe, and storage were
not reached. Sanctioned DebugUSB recovery restored a fresh quiescent proxy.

Transcript: `logs/t6040-console-20260714-pcie-barrier.log`, SHA-256
`cebc058921b62b2f594855bb65db28b312570b6c707f5a29a29480c31c04667b`
(407 lines, 25,940 bytes).

The two earlier traced logs have the same 407-line/25,940-byte size and end
after the same trace line. The next diagnostic should therefore be a
zero-PCIe-write trace-volume control, not another write-order variant. Main
`3e772779`, binary SHA-256
`c9296b8d1ca146a32c7a1ba1bf17b7091281588ab90d16a69f0718c5a8fa04ea`,
enumerates the ADT AXI tunables and prints identical pre/`done` lines without
enabling PCIe clocks or reading/writing controller registers. If that control
completes, continue with a separately approved prefix-and-hold bisection. If it
faults at the same output boundary, debug the m1n1 trace/log path instead. Exact
gate: `2026-07-14-t6040-pcie-trace-dry-run.md`.
