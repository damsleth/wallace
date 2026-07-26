# T6040 ticket 124 — `_initializePhy()` located and partially traced (2026-07-26)

Host-only static analysis of the paired 25F84 kernelcache. No rig, no guessed offsets, and
ticket 068 was **not** retried.

## The driver is `ApplePCIEBaseT8132`

Ticket 068's work referred to "the paired AppleT6040PCIe driver"; the actual class in the
25F84 kernelcache is **`ApplePCIEBaseT8132`** (t8132 is the M4 family — the same name used in
m1n1's `dapf.c` comment about "t8132 'Neo' M4"). Its relevant members, with VAs:

| Symbol | VA |
|---|---|
| `_enableClocks()` | `0xfffffe0009b346ec` |
| `_configPciePLLs()` | `0xfffffe0009b35e98` |
| **`_initializePhy()`** | **`0xfffffe0009b36c74`** |
| `_readPhyIPReg(uint)` / `_writePhyIPReg(uint,uint)` | `0xfffffe0009b35370` / `0xfffffe0009b355e0` |
| `_readPhyCommonReg` / `_writePhyCommonReg` | `0xfffffe0009b3584c` / `0xfffffe0009b358a4` |
| `_readPhyPhyReg` / `_writePhyPhyReg` | `0xfffffe0009b35904` / `0xfffffe0009b3595c` |
| `_readPcieclkgenReg` / `_writePcieclkgenReg` | `0xfffffe0009b349c0` / `0xfffffe0009b34c2c` |
| `_readCio3PllCoreReg` / `_writeCio3PllCoreReg` | `0xfffffe0009b34e98` / `0xfffffe0009b35104` |
| `_readAxi2AfReg` / `_writeAxi2AfReg` | `0xfffffe0009b359bc` / `0xfffffe0009b35c2c` |
| `_enableRootComplex(bool)` / `_disableRootComplex()` | `0xfffffe0009b35fe0` / `0xfffffe0009b37830` |
| `_shutdownPciePLLs()` / `_quiesceClocks()` | `0xfffffe0009b3486c` / `0xfffffe0009b34780` |

**There are SEVEN distinct register apertures**, each with its own ADT/DT index accessor:
`dtRegMapApcieCommonIndex()`, `dtRegMapPhyIndex(uint)`, `dtRegMapCio3PllIndex()`,
`dtRegMapPcieClkgenIndex()`, `dtRegMapApcieAxi2AfIndex()`,
**`dtRegMapPortPhyGlueIndex(uint)`** and `dtRegMapPortPhyIPIndex(uint)`.

`PortPhyIP` is the `reg[3]` aperture whose `+0x90` read hangs (ticket 068). Note the separate
**`PortPhyGlue`** aperture — a plausible gate that m1n1 never touches.

## The finding: a PhyCommon read-modify-write precedes any PHY-IP access

Disassembled `_initializePhy()` and resolved its `bl` targets. The opening sequence is:

```text
 1.  _readPhyCommonReg(<reg>)          ; read
     orr  w8, w8, #0x1                 ; set bit 0
 2.  _writePhyCommonReg(<reg>, w8)     ; write back
 3.  _readPhyPhyReg(<reg>)
 …   IOLog / delay / helper calls
 9.  _writePhyCommonReg(...)           ; the pattern repeats later in the function
```

So the **first hardware operation of PHY initialisation is a bit-0 RMW on the ApcieCommon
aperture**, followed by a PhyPhy read — all *before* any `_readPhyIPReg`. m1n1 currently
performs the `_configPciePLLs` clkgen work and then reads PHY-IP `reg[3]+0x90` directly, with
nothing on ApcieCommon or PhyPhy in between. That is a concrete, grounded candidate for the
missing pre-`reg[3]` precondition ticket 068 asked for.

## Limits — what this does NOT yet establish

Stated explicitly so nobody builds an m1n1 change from it yet:

- **The exact register offsets and values are not extracted.** They are immediates passed in
  `w1`/`w2`; my pass resolved *which functions* are called, not their arguments. Symbol
  attribution also showed a systematic `+0x50`-ish skew (calls resolving slightly inside the
  target functions), so the offsets must be decoded properly, not inferred from this pass.
- **Ordering relative to `_enableClocks()` and `_configPciePLLs()` is not proven** — the
  caller (`configure()`/`start()`) must be traced to establish the real sequence.
- Whether the ApcieCommon RMW is *sufficient*, or merely the first of several gates
  (PhyGlue, Cio3Pll, Axi2Af), is unknown.

## Next steps for 124, in order

1. Decode the argument immediates for calls 1-3 to get exact `(aperture, offset, bit)` triples.
2. Trace `configure()` (`0xfffffe0009b31e40`) / `start()` (`0xfffffe0009b318e8`) for the
   authoritative order of `_enableClocks` → `_configPciePLLs` → `_initializePhy`.
3. Map each aperture to its ADT `reg[]` index via the `dtRegMap*Index()` accessors, so any
   future m1n1 change uses ADT-derived addresses rather than constants.
4. Only then propose a bounded, separately reviewed m1n1 candidate. **Ticket 068 must not be
   retried until (1)-(3) are grounded.**

Method note: the kernelcache's `__TEXT_EXEC` segment is not disassembled by `llvm-objdump -d`
(it reports only `__text`/`__info`), and `-b binary` is unsupported. Working recipe: compute
`file_offset = VA - 0xfffffe0008954000 + 26542080`, `dd` the bytes, then
`llvm-mc --disassemble --triple=aarch64` over a hex dump.
