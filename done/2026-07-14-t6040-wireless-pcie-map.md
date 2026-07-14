# T6040 J614s PCIe + wireless map (2026-07-14)

## Result

The J614s internal PCIe topology is now mapped end to end from the paired ADT
to the existing Linux drivers. A separate kernel/DT build exists for the later
Linux-enumeration stage. The initial map and build required no target MMIO; the
subsequent first live result is recorded below.

The target identity is **Mac16,8 / J614sAP, MacBook Pro 14-inch M4 Pro**.  It is
not Mac14,8 and it is not the 16-inch chassis.

## Populated topology

`/arm-io/apcie0` is `apcie,t6040`, with four hardware ports and two populated
bridges:

| Port | ADT child | Device | Linux ID | PERST# | CLKREQ# | Link cap | DART |
|---|---|---|---|---|---|---|---|
| 0 | `pci-bridge0` | BCM4388 WiFi + Bluetooth | `14e4:4434`, `14e4:5f72` | GPIO 4 | GPIO 0 fn 2 | Gen2 | `0x410000000`, IRQ 1724 |
| 1 | `pci-bridge1` | Genesys Logic GL9755 SD reader | `17a0:9755` | GPIO 5 | GPIO 1 fn 2 | ADT bridge cap Gen1 | `0x411000000`, IRQ 1733 |
| 2 | absent | unpopulated | — | GPIO 6 (template only) | — | — | absent |
| 3 | absent | unpopulated | — | GPIO 7 (template only) | — | — | absent |

The saved ADT identifies `/product/wifi-chipset = "4388"` and
`/arm-io/wlan/module-instance = "mriya"`.  Linux already has both required PCI
IDs and the BCM4377-family Bluetooth driver explicitly supports BCM4388.  The
board type `apple,mriya` in the bring-up DT is an evidence-backed inference
from that module-instance, following existing Apple board DT convention.
m1n1 will copy the target's MAC addresses, antenna SKU, WiFi calibration, and
Bluetooth calibration into the aliased `wifi0`/`bluetooth0` nodes at handoff.

## T6040 host-controller register map

Shared ADT registers:

| Index | CPU PA | Size | Role |
|---|---:|---:|---|
| 0 | `0x1cb0000000` | `0x10000000` | ECAM |
| 1 | `0x414000000` | `0x4000` | root controller |
| 2 | `0x417000000` | `0x40000` | PHY common |
| 3 | `0x417040000` | `0x28000` | PHY IP |
| 4 | `0x416000000` | `0x1000000` | AXI |
| 5 | `0x415046200` | `0x4000` | CIO3 PLL core |
| 6 | `0x415044000` | `0x4000` | PCIe clock generator |

The remaining 28 entries are four repetitions of seven registers.  Linux uses
the first (`port`) and third (`phy`) entry for each port:

| Port | Port block | LTSSM | Port PHY | PHY IP | intr2axi |
|---|---:|---:|---:|---:|---:|
| 0 | `0x410028000` | `0x41003c000` | `0x417020000` | `0x417048000` | `0x410024000` |
| 1 | `0x411028000` | `0x41103c000` | `0x417024000` | `0x417050000` | `0x411024000` |
| 2 | `0x412028000` | `0x41203c000` | `0x417028000` | `0x417058000` | `0x412024000` |
| 3 | `0x413028000` | `0x41303c000` | `0x41702c000` | `0x417060000` | `0x413024000` |

Controller IRQs are 1723/1732/1741/1750.  The 32 MSI vectors start at AIC IRQ
2071.  The outbound windows are:

- 64-bit prefetchable: bus/CPU `0xbc0000000`, size `0x20000000`;
- 32-bit memory: bus `0x80000000`, CPU `0xb80000000`, size `0x40000000`.

T6040's Linux-visible port registers use the T602x layout: PERST at `0x82c`,
RID2SID at `0x3000`, and MSIMAP at `0x3800`.  The provisional DT therefore uses
`"apple,t6040-pcie", "apple,t6020-pcie"`; the existing driver binds through the
fallback.

## Resolved clock/PLL windows

The old PCIe plan stopped correctly because the two new tunable groups could
not be assigned to reg[5]/reg[6] from the ADT alone.  Static disassembly of the
paired local macOS kernelcache resolves this without probing MMIO:

- `ApplePCIEBaseT8132::dtRegMapCio3PllIndex()` reads object slot `0x2c9`;
- `ApplePCIEBaseT8132::dtRegMapPcieClkgenIndex()` reads slot `0x2ca`;
- `AppleT6040PCIe::start()` assigns `5` to `0x2c9` and `6` to `0x2ca`.

Therefore:

- `apcie-cio3pllcore-tunables` targets ADT reg[5], `0x415046200`;
- `apcie-pcieclkgen-tunables` targets ADT reg[6], `0x415044000`.

The exact newly enabled ADT RMW operations are:

| Address | Size | Mask | Value |
|---:|---:|---:|---:|
| `0x415046200` | 4 | `0x00000a0b` | `0x00000a01` |
| `0x415046224` | 4 | `0x00000c00` | `0x00000800` |
| `0x415046228` | 4 | `0x00000f00` | `0x00000b00` |
| `0x415046238` | 4 | `0x00000020` | `0x00000000` |
| `0x41504624c` | 4 | `0x000000ff` | `0x00000095` |
| `0x4150462e8` | 4 | `0x000e0000` | `0x00020000` |
| `0x415046300` | 4 | `0x00ffffff` | `0x000b40b4` |
| `0x415044000` | 4 | `0x000003e0` | `0x00000220` |

These are ADT data applied as `(old & ~mask) | value`, not invented constants.

## Code and build state

m1n1 baseline support applies the two proven T6040-only groups and continues
through the existing T6031/T8122 PHY and port sequence:

- main: `eb23c423` (`pcie: initialize T6040 clock and PLL blocks`);
- curated `t6040-bringup`: `da1791a0` (same code-only change).

The current diagnostic heads temporarily trace each T6040 tunable, stage
`APCIE_PHY_SW` after the clock groups, and then return: main `6efe2d45`, curated
`954fd4cf`. They do not reach the PHY/port sequence.

Both m1n1 trees build cleanly.  The Linux bring-up source is deliberately kept
separate at `dts/t6040-j614s-dcuart-pcie.dts`; it includes GPIO/pinctrl, all four
host resources, the two populated root ports, both DARTs, BCM4388 child nodes,
and the GL9755 child node.  `scripts/t6040-build-pcie.sh` builds it in a clean,
dedicated container tree with `PCIE=1` so stale NVMe diagnostics cannot leak
into the image.

The host controller, GPIO, and DART drivers are built in. WiFi, Bluetooth, and
SD endpoint drivers are configured as modules but are not included in the PCIe
image's initramfs. This keeps the later Linux-enumeration stage bounded to host
link, DART probe, and PCI config space; building/loading endpoint modules with
their normal dependency set is a separate follow-up.

The kernel image and DT compile cleanly with the normal build. Schema checking
is not claimed: the container's installed `dt-validate` command is incompatible
with the kernel's `dtbs_check` invocation. Endpoint modules are configured but
were deliberately not built or staged for this milestone.

Prepared Linux-enumeration artifacts:

- `Image-pcie`: `e7dcfcc1dea997ca53624ba50e50b210472dc63b003f17a5040265176351107a`;
- `t6040-j614s-dcuart-pcie.dtb`: `258ca9e52284864498dde10cabc807f94990528cfc7e3dad98356bf999ff2eb2`;
- `initramfs-dcuart-pcie.cpio.gz`: identical to the proven module-free
  DockChannel BusyBox initramfs, hash
  `512c69da94884f3ea83f9a6a4ea0731dcad6b5aaa87eb875ca5a6d7b24c317ca`;
- `System.map-pcie`: `350d8bdeb1f6e88b72591cc68381a68ff97d615b574e3f9fb4e995f2bb8396ff`.

## Complete write review

`scripts/t6040-pcie-write-plan.py` consumes the committed raw J614s ADT without
connecting to the target and expands the staged T6040 path at m1n1 `6efe2d45`.
The checked-in result is `2026-07-14-t6040-pcie-write-manifest.tsv`, SHA-256
`6a91f39f8db215305de5e354446a44eab8d604852107f91abc7d4c3074065864`.
It contains 1,571 ordered operations at 1,459 distinct addresses:

- 19 recursive PMGR RMWs, including repeated parent visits exactly as m1n1
  executes them; the last seven are staged after clkgen;
- 91 controller operations and 241 shared-PHY operations;
- 610 operations for each populated port, including every RID2SID/MSIMAP loop
  element and both ports' ADT config/DBI tunables.

Every row provides address, access size, operation, mask, and value. `WRITE`
replaces the full value; `RMW` is `(old & ~mask) | value`; `SET` and `CLEAR`
state the exact bit operand. The source ADT hash is
`87f5c391b0fc722bdaa0fdca468f160bccf1becaa2f81cec052c481b7c98f195`.
Regenerate it with:

```sh
git -C ~/Code/linux show feature/m4-m5-minimal-device-trees:j614s.adt \
  | scripts/t6040-pcie-write-plan.py \
  > done/2026-07-14-t6040-pcie-write-manifest.tsv
```

## First live result

The maintainer approved one m1n1-only attempt using `eb23c423` and the
PCIe-free base DT. The clean retry reached the controller on 2026-07-14:

```text
pcie: Error getting node /arm-io/apcie
pcie: Initializing t6040 PCIe controller
pcie: ADT uses 7 reg entries per port
pcie: No common tunables
```

Output then stopped. PMGR recursion, all 77 AXI tunables, and the RC `+0x4`
write necessarily completed before the last line. The exact later boundary is
not yet known because the original build did not print around local tunables;
the stall could be in either new clock group or the following pre-poll PHY
tunables. An asynchronous fault is plausible but not proven.

The uploader timed out without a proxy reply. The sanctioned HPM DebugUSB warm
reboot recovered the target to a healthy `Running proxy`; the opaque sequence
was not retried. Linux never handed off, no endpoint/port result was observed,
and no NVMe or user-storage access occurred. Transcript:
`logs/t6040-console-20260714-pcie-stage1.log`, SHA-256
`b850b08a6ce2b40a2067324dabacaa52102f6b4c07b1c7b045237f64fb2a5398`.

## Traced follow-up result

The maintainer approved the bounded trace on main `81da3522`. It reached
`Ready to boot`, entered `pcie_init()`, and printed `done` for AXI tunable
`[70]` at `0x4160013fc`. Before the pre-write line for `[71]`, m1n1 reported:

```text
+Exception: SError
+Exception taken from EL2h
+PC:       0x1000495f140 (rel: 0x2b140)
+ESR:      0xbe000000 (SError)
+L2C_ERR_STS: 0x82
+Unhandled exception, rebooting...
```

The relative PC symbolizes to `proxy_process()` at `src/proxy.c:50`, the
`P_CALL` trampoline running kboot. It therefore does not identify a synchronous
bad-address instruction. `[70]` is the asynchronous delivery boundary only;
the causal access may be any earlier AXI operation. The slower per-entry UART
trace explains why this run delivered the pending fault before the original
untraced run's later `No common tunables` line.

The uploader was terminated without a Linux handoff. HPM DebugUSB recovery
restored a fresh, quiescent `Running proxy`. No CIO3, clkgen, PHY, port, PERST#,
RID2SID, MSIMAP, Linux PCIe, or storage access occurred. Transcript:
`logs/t6040-console-20260714-pcie-axi-trace.log`, SHA-256
`41774ef8866e775de30ca2c98957d167085943163fe24d25c7aaca29eb177860`.

## Corrected clock-gate ordering

Offline disassembly of `ApplePCIEBaseT8132::_enableRootComplex()` resolved the
remaining sequencing difference. `AppleT6040PCIe::start()` supplies a count of
eight clock gates. The base driver enables indices 0–6, applies AXI tunables,
then CIO3 PLL tunables, then PCIe clkgen tunables, and only afterward enables
index 7. The committed J614s ADT proves index 7 is `APCIE_PHY_SW`. m1n1's generic
`pmgr_adt_power_enable()` instead enabled all eight before AXI, switching on the
PHY against a partially configured controller.

m1n1 main `6efe2d45` and curated `954fd4cf` reproduce Apple's staging. The two
`src/pcie.c` files are byte-identical and both builds complete cleanly. Main
`m1n1.bin` SHA-256:
`c2a5b7e27bb8d56479f46d6b485a195d2eb1cd64a3b86fbe3c90db1f00424735`;
curated binary SHA-256:
`cb08ad798a263293c3adf5bcd96f7cb142ca14c5f72cc8b2e5028f034746e73f`
(the build tags differ).

The regenerated full 1,571-operation manifest has SHA-256
`6a91f39f8db215305de5e354446a44eab8d604852107f91abc7d4c3074065864`.
The staged subset is exactly operations 1–105, ordered as:

- 12 recursive PMGR RMWs for clock gates 0–6;
- 77 AXI RMWs, one RC write, seven CIO3 RMWs, and one clkgen RMW;
- seven recursive PMGR RMWs ending in `APCIE_PHY_SW` at operation 105.

`2026-07-14-t6040-pcie-clock-diagnostic.tsv` has SHA-256
`ce86e51aa3d278da1d9ef9eb35fca3208859f4993480de5b6af3268dc03ef4e6`.
The build logs every T6040 tunable before and after its RMW, logs the late PHY
gate before and after, then returns before operation 106, the first PHY register
write. It cannot reach ports, PERST#, RID2SID/MSIMAP, or Linux PCIe.

## Staged clock-gate result

The maintainer separately approved one run of that exact main binary and
105-operation set. It booted with the PCIe-free base DT and again reached AXI
tunable `[70]` at `0x4160013fc`, which printed `done`. Before the pre-write line
for `[71]`, m1n1 delivered:

```text
+Exception: SError
+PC:       0x100042c722c (rel: 0x2b22c)
+ESR:      0xbe000000 (SError)
+L2C_ERR_STS: 0x82
+L2C_ERR_ADR: 0x3606505ce7a8000
+L2C_ERR_INF: 0x1000000001
```

The relative PC again symbolizes to the proxy `P_CALL` site, so it is an
asynchronous delivery location rather than a causal MMIO instruction. The
result is nevertheless decisive about sequencing: CIO3, clkgen, and the late
`APCIE_PHY_SW` gate had not run, yet the boundary was identical to the earlier
trace. Enabling gate 7 early was not the cause of this SError. The staged order
remains the Apple-accurate implementation and should be retained.

The uploader stopped without Linux handoff. No PHY, port, PERST#, Linux PCIe,
NVMe, or storage access occurred. The sanctioned DebugUSB reboot restored a
fresh quiescent proxy. Transcript:
`logs/t6040-console-20260714-pcie-staged-gate.log`, SHA-256
`c31275546280b9df2dbf9b014d2e6411cfb708f87f1c803e10b11e2cdb95ec2f`
(407 lines, 25,940 bytes).

The narrowest next diagnostic adds no MMIO addresses or values: issue a
full-system barrier and sample the read-only `L2C_ERR_STS` system register after
each existing traced RMW. That can reveal whether an error is already pending
before its asynchronous exception is delivered. Because it changes target
timing, its exact build still requires new explicit approval before one live
run. The PCIe-free base DT remains mandatory; storage stays out of scope.

## Full-path gate

`pcie_init()` is a kboot-time invasive operation. A complete target boot remains
**unattempted and gated**. It will apply the full existing ADT-derived
AXI/PHY/PHY-IP/bridge tunable sets and the reused T6031/T8122 clock/reset/port
sequence. After the asynchronous fault is localized and corrected, use two
further stages:

1. Boot a corrected full m1n1 path with the current PCIe-free base DT. The Image
   and initramfs are previously boot-proven; the concurrently rebuilt DT differs
   from the older build-15 hash but contains no PCIe host node. Current hashes:
   Image `14da8640398fc64b89d9241a75be0ffc8d4260b681068a3c27251cc79c3abaf4`,
   DTB `e7691ee49ed88114154061aeaf29309e3d817ae3ae89d7196bf7ef02a9b3dc9a`,
   initramfs `512c69da94884f3ea83f9a6a4ea0731dcad6b5aaa87eb875ca5a6d7b24c317ca`.
2. Only after reviewing that result, boot the prepared PCIe DT for Linux
   host/DART and config-space enumeration. Endpoint modules remain absent.

Neither stage may access the NVMe namespace or mount/repair/format any storage.
