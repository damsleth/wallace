# T6040 m1n1 → U-Boot SD ownership audit

Date: 2026-08-19
Ticket: 3011
Scope: source/DT audit and patch contract; no rig or hardware access

## Verdict

Use the already-proven m1n1-first PCIe model, with a stricter stage boundary:

1. m1n1 performs the full T6040 common-PHY/controller/port initialization
   exactly once in the iBoot boot cycle;
2. before that initialization, the SD-stage2 build performs only the exact
   allowlisted, ADT-gated `gP19 <- 0x01000001` endpoint-power operation and
   waits the established 100 ms Tpvperl interval;
3. U-Boot attaches only if port 1 is already linked; in this target it must not
   assert PERST#, request refclks, or retry LTSSM when the link is down;
4. U-Boot owns PCI enumeration, BAR setup, the port-1 T8110 DART translations,
   generic PCI SDHCI/MMC, and read-only bundle loading;
5. U-Boot removes its DART translations through its existing OS-prepare hook
   before Linux; the link remains up, so Linux's Apple PCIe driver takes its
   existing `PORT_LINKSTS_UP` skip path.

This is not “m1n1 initializes everything and U-Boot initializes it again.” It
splits ownership by operation. The common PHY/reset/link sequence has one owner
(m1n1); U-Boot owns only consumers above the established link.

## Why m1n1 owns the link sequence

- Current m1n1's T6040 path has the known-correct M4 PHY reset bit
  (`APCIE_PHY_CTRL_RESET_T8132 = BIT(4)`) and the ADT-derived controller
  implementation. `kboot_boot()` calls `pcie_init()` before handing off a Linux
  Image (`src/kboot.c:2887`). This exact path is what made GL9755 and WiFi/BT
  possible.
- Ticket 168 directly proved the lifetime rule. Running `pcie_init()` through
  one m1n1 proxy and then again in a chainloaded m1n1 caused a synchronous data
  abort at `0x41705a000`, in the port-2 PHY-IP window. A fresh-boot retry
  worked. The static `pcie_initialized` guard covers one m1n1 instance only.
- The local U-Boot Apple PCIe driver is not a replacement for T6040 common-PHY
  initialization. Its T602x match starts at the per-port layer: APPCLK, PERST,
  refclk requests, readiness, and LTSSM (`drivers/pci/pcie_apple.c:245-330`). It
  has no T6040 common-PHY/reset-bit sequence. That is consistent with relying on
  an earlier Apple-firmware/m1n1 stage.
- Rewriting the full, proven m1n1 T6040 initialization inside U-Boot would add a
  second implementation and a much larger MMIO surface without providing any
  capability needed for SD loading.

Therefore the SD target must preserve the m1n1 initialization, not bypass it.

## Why stock U-Boot probing is still too active

Stock `apple_pcie_setup_port()` always:

- requests the reset GPIO;
- enables port APPCLK;
- asserts PERST#;
- requests both reference clocks;
- deasserts the controller and GPIO resets;
- waits for port readiness;
- starts LTSSM.

It does this even if a preceding stage already brought the link up. By
contrast, the Wallace Linux `pcie-apple` driver reads `PORT_LINKSTS` and skips
`apple_pcie_setup_link()` when bit 0 is already set
(`drivers/pci/controller/pcie-apple.c:691-697`).

Ticket 3013 should add a stricter opt-in U-Boot mode, selected only by the
T6040 SD stage-2 DTS/config:

```text
apple,preinitialized-only;
```

In that mode the driver maps the ADT/DTS-provided ECAM/RC/port resources and
reads port 1 `PORT_LINKSTS`. `UP=1` permits PCI enumeration. `UP=0` returns a
bounded not-present/error result and goes to the no-valid-media fallback. It
must not request the reset GPIO or write APPCLK, PERST, refclk, LTSSM, PHY, or
PMGR registers. The property is local to the new target; normal U-Boot boards
retain their current behavior.

This deliberately fails closed. A link-down result means the m1n1/gP19
precondition is wrong and must be diagnosed from the prior-stage transcript,
not “fixed” by a second initialization attempt.

## Endpoint power: exact m1n1 operation

The GL9755 cannot link until the off-SoC endpoint power GPIO is asserted. This
is already established, approved, and used by the working Linux SD path:

| Item | Exact value | Source |
|---|---|---|
| ADT node | `/arm-io/apcie0/pci-bridge1/pcie-sdreader` | captured J614s ADT decode |
| ADT function | `function-sd_pwr_en = pKW4('gP19', 0x0)` | `evidence/2026-07-29-t6040-pcie-endpoint-power-decode.md` |
| permitted SMC key | `gP19` only | `AGENTS.md` and `docs/SPMI_SAFETY.md` policy boundary |
| upstream GPIO command | `CMD_OUTPUT | 1 = 0x01000001` | Linux `drivers/gpio/gpio-macsmc.c` and live-proven Wallace path |
| power-to-PERST delay | 100 ms | Linux `pcie-apple.c:618-625`; proven SD path |

The m1n1 stage2 helper must not accept an arbitrary ADT function. It must:

1. resolve that exact ADT node and property;
2. require the function shape to be `pKW4` and its key to equal the literal
   four bytes `gP19`;
3. initialize the existing m1n1 SMC RTKit transport;
4. write exactly one 32-bit value, `0x01000001`, to `gP19`;
5. shut down the SMC transport and wait 100 ms;
6. abort the SD path before PCIe on any mismatch or failed transaction.

It must not power `gP13`, enumerate SMC keys, accept another ADT key, or expose
an interactive arbitrary-key command. This is a build-time SD-stage2 action,
not a change to general m1n1 behavior.

## Resource and address matrix

All resources come from the existing J614s DTS, itself derived from the saved
ADT. The U-Boot memory-map builder may map only the enabled target nodes and
their declared `reg` ranges.

| Resource | DTS identity/range | Owner | Allowed operation |
|---|---|---|---|
| T6040 common PCIe PHY/controller | `pcie@1cb0000000`, RC/port/PHY ranges in `dts/t6040-j614s-dcuart-pcie.dts` | m1n1 | existing `pcie_init()` once per iBoot cycle |
| endpoint power | ADT `function-sd_pwr_en`, exact key `gP19` | m1n1 SD helper | one `0x01000001` write before PCIe |
| PCIe port 1 | port reg encoding `0x800`, Gen1, bus 2 | m1n1 for link; U-Boot read-only attach | U-Boot may read link state and use ECAM; no port setup writes |
| GL9755 | BDF 02:00.0, PCI ID `17a0:9755`, class SDHCI, `cd-inverted`, `wp-inverted` | U-Boot | PCI config/BAR and generic SDHCI/MMC operations |
| port-1 DART | `iommu@411000000`, size `0x20000`, `apple,t8110-dart`, SID 1 via `iommu-map` RID `0x200` | U-Boot | allocate/map/unmap DMA translations only for the SD endpoint |
| FAT/bundle blocks | removable MMC selected by exact controller/card identity | U-Boot | read only in first candidates |
| PCIe/DART after `booti` | same hardware | Linux | U-Boot DART removal first; Linux normal probe/translation ownership |

Ports 0, 2, and 3 are disabled in the U-Boot SD target. There is no WiFi,
NVMe, USB, SPMI, or Type-C device in this first loader's allowlist.

## DART and DMA boundary

U-Boot's `iommu-map` support resolves a PCI child's RID to an IOMMU, and
`apple_dart.c` supports `apple,t8110-dart`. It installs 16-KiB-granule mappings
for DMA and is marked `DM_FLAG_OS_PREPARE | DM_FLAG_VITAL`. Its remove method
disables translations, removes TTBRs, flushes the TLB, and tears down the
allocator (`drivers/iommu/apple_dart.c:289-325`).

That supplies a complete owner transition:

```text
m1n1: no SD DMA mappings
  -> U-Boot: DART1 mappings for SDHCI DMA
  -> booti OS prepare: remove/flush U-Boot mappings
  -> Linux: probe DART1 and create its own mappings
```

The first rig ticket remains read-only at the media level. DART page-table and
PCI configuration writes are normal controller setup, not storage writes, and
must remain confined to the exact enabled endpoint.

## Required patch split

Ticket 3013 may implement this contract as three reviewable deltas:

1. **m1n1 SD power helper:** exact ADT/property/key/value gates, then the
   existing `pcie_init()` path. No new SMC transport or generic GPIO API.
2. **U-Boot preinitialized-only PCIe mode:** link-up check and no-write attach;
   link-down is a terminal SD-not-available result.
3. **SD-only U-Boot target/DTS:** enable PCI, `PCIE_APPLE`, IOMMU/Apple DART,
   MMC/PCI SDHCI, partition and FAT/boot loading; enable only port 1, DART1, and
   GL9755; disable USB, NVMe, networking, SPMI, and interactive autoboot.

Each delta must have source-level negative checks proving the forbidden drivers
and device nodes are absent. The composed object remains tethered-only until
ticket 3016's independent review and ticket 3017's approval.

## Stop/no-go findings

- Do not make U-Boot the common-PHY owner without porting and independently
  proving the entire T6040 m1n1 sequence; this audit found no benefit to doing
  so.
- Do not use stock U-Boot `apple_pcie_setup_port()` in this target after m1n1.
- Do not let link-down trigger a retry or broader device scan.
- Do not put `gP19` behind a generic U-Boot SMC shell command or key iterator.
- Do not leave U-Boot DART mappings installed across `booti`.
- Do not enable another PCIe port merely because it shares the controller.

## Outcome

The ownership blocker is resolved offline. The SD loader can reuse the proven
m1n1 PCIe path and the existing U-Boot PCI/MMC/DART stacks with two narrow
guards: exact pre-handoff `gP19` power and a read-only, preinitialized-link
attach mode. Ticket 3013 is now the implementation owner.
