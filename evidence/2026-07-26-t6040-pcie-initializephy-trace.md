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

## Register offsets decoded (2026-07-26)

Continued the trace to exact offsets.

### The first PHY-init hardware op

```asm
mov  w1, #0                  ; register = 0x0
bl   _readPhyCommonReg       ; x0=this, w1=0  -> read PhyCommon[0]
orr  w8, w8, #0x1            ; set bit 0
mov  w2, w8
bl   _writePhyCommonReg      ; x0=this, w1=0, w2=val|1 -> write PhyCommon[0]
```

**First operation of `_initializePhy()` = read-modify-write of PhyCommon register `0x0`,
setting bit 0.** A PhyPhy read follows, then (after global-flag checks and delays) a second
PhyCommon write later in the function.

### Aperture sub-window layout (from the accessors themselves)

Both `_readPhyCommonReg` and `_readPhyPhyReg` add a fixed offset to the caller's register
number and dispatch through the same vtable slot (`+0xb28`), i.e. they are sub-windows of one
shared PHY register region:

| Accessor | Addend | So register N lands at |
|---|---|---|
| `_readPhyCommonReg(N)` | `+0x4000` | shared-PHY `+0x4000 + N` |
| `_readPhyPhyReg(N)` | `+0x8000` | shared-PHY `+0x8000 + N` |

So `_initializePhy`'s first op writes shared-PHY aperture offset **`0x4000`**, bit 0.

`_readPhyIPReg` is different: it dereferences a **cached per-port base pointer at `this+0x240`**
and panics (loads a format string + calls the log/abort path) if it is null. So the PHY-IP
aperture must be mapped into `this+0x240` before any PHY-IP read; ticket 068's hang is
downstream of a valid pointer (a non-responding aperture), not a null one.

### The reg indices are ADT-derived, not constants

The `dtRegMap*Index()` accessors do **not** return literals — they compute from consecutive
per-instance byte fields populated at `start()`/`configure()` from the ADT `reg-names`:

| Accessor | ivar (byte offset in `this`) |
|---|---|
| `dtRegMapApcieCommonIndex()` | `[this+709]` |
| `dtRegMapPhyIndex()` (shared PhyCommon/PhyPhy) | `[this+710]`, `[this+711]` |
| `dtRegMapPortPhyGlueIndex(port)` | `[this+718]` |
| `dtRegMapPortPhyIPIndex(port)` | `[this+719]` |

`PortPhyGlue` (718) and `PortPhyIP` (719) are **adjacent** reg-map entries. So a candidate m1n1
change must resolve these apertures from the ADT `reg-names` of the `/arm-io/apcie*` node, never
from hardcoded addresses — matching Wallace's standing "ADT-derived, never swept" rule.

## Grounded candidate for the missing precondition

Before m1n1 reads PHY-IP `reg[3]+0x90`, the driver does — in the **shared PHY aperture** —
a bit-0 RMW at offset `0x4000` (PhyCommon[0]) plus PhyPhy setup at `+0x8000`. m1n1 currently
does the `_configPciePLLs` clkgen work and jumps straight to PHY-IP with nothing on the shared
PHY aperture in between. **That shared-PHY-aperture initialization is the concrete missing
precondition candidate.**

### Still required before any m1n1 change (do not build yet)

1. Extract the exact PhyPhy register/value pairs and the second PhyCommon write (this pass
   confirmed offset `0x4000`/bit 0 for the first op; the rest are still symbolic).
2. Identify the shared-PHY ADT `reg-name` (the entry `dtRegMapPhyIndex` selects) from the
   captured J614s ADT, and confirm `PortPhyGlue`/`PortPhyIP` reg-names + that `this+0x240` maps
   the PhyIP window.
3. Trace `configure()`/`start()` for the authoritative order of `_enableClocks` →
   `_configPciePLLs` → `_initializePhy`.
4. Only then a bounded, separately reviewed m1n1 candidate. **068 stays un-retried until 1-3 land.**

## ADT reg[] map resolved over the live proxy (2026-07-26)

Read `/arm-io/apcie0` from the running rollback loader (read-only ADT fetch, no MMIO poke).
**Apple's ADT has no `reg-names` property** — the node maps `reg[]` purely by index, which is
exactly why the driver caches indices in ivars (`[this+709/710/711/718/719]`) instead of names.

35 entries = **7 header regs + 4 ports × 7 regs** (`#ports`=4). Header:

| reg[] | addr | size | role (inferred) |
|---|---|---|---|
| 0 | `0x1cb0000000` | 0x10000000 | ECAM / config space (256 MiB) |
| 1 | `0x214000000` | 0x4000 | apcie common core — **dtRegMapApcieCommonIndex** candidate |
| 2 | `0x217000000` | 0x40000 | **shared PHY region — dtRegMapPhyIndex** |
| 3 | `0x217040000` | 0x28000 | PHY-IP super-region (per-port windows carve from here) |
| 4 | `0x216000000` | 0x1000000 | (16 MiB window) |
| 5 | `0x215046200` | 0x4000 | |
| 6 | `0x215044000` | 0x4000 | |

Per-port block (7 regs; port 0 shown, others add the stride):

| off | port0 addr | size | region |
|---|---|---|---|
| +0 | `0x210028000` | 0x8000 | port core (0x21p_0000 per port) |
| +1 | `0x21003c000` | 0x4000 | port core |
| +2 | `0x217020000` | 0x4000 | **shared-PHY** — PortPhyGlue candidate (`+port*0x4000`) |
| +3 | `0x217048000` | 0x8000 | **shared-PHY** — PortPhyIP candidate (`+port*0x8000`) |
| +4 | `0x210024000` | 0x4000 | port core |
| +5 | `0x210048000` | 0x4000 | port core |
| +6 | `0x210044000` | 0x4000 | port core |

Ports use core bases `0x210/0x211/0x212/0x213_xxxxx` and shared-PHY sub-windows at
`0x217020000+port*0x4000` (glue, 0x4000) and `0x217048000+port*0x8000` (PHY-IP, 0x8000).

### Concrete resolved addresses for `_initializePhy` (port 0)

Combining the disassembly offsets with reg[2] = `0x217000000`:

- **PhyCommon reg 0x0** = reg[2] + 0x4000 = **`0x217004000`** — the first op sets **bit 0** here.
- **PhyPhy base** = reg[2] + 0x8000 = **`0x217008000`**.
- **PHY-IP (port 0)** = reg[]+3-of-port = `0x217048000`; the op-115 read that hangs is
  `0x217048000 + 0x90` = **`0x217048090`** (per port: `+port*0x8000`).

So the missing precondition, in absolute MMIO terms: **before reading `0x217048090`, set bit 0
of `0x217004000` and run the PhyPhy setup at `0x217008000`** — none of which m1n1 currently does.

### Not done (needs the paired driver / attended session, not autonomous)

- Confirming these are powered before reading: a live read of `0x217004000` risks an SError on an
  ungated PHY aperture (same class as the NVMe `nvme_init` SError) and could wedge the tether, so
  it is **not** an autonomous probe — defer to an attended session.
- Exact PhyPhy register/value pairs and the second PhyCommon write.
- Mapping `dtRegMapApcieCommonIndex` (reg[1] candidate) definitively via the probe-time ivar fill.
