# T6040 PCIe link training: static review and paired port-reset candidate

No rig action was performed for this work. The rollback loader remains available at
`Running proxy`; the candidate below is only an offline build and is not approved to run.

## Inputs and chronology

The successful V1 traces are pinned as:

- `linux-build-out/pcie-v1-20260729.log`
  SHA-256 `d5355c0730b8802c92b50e9768e15e7e8a4cfab8b9a7d808364237ad15e9eac2`
- `linux-build-out/pcie-v1-linux-console-20260729.log`
  SHA-256 `77a1fdc5e5ee116bab7053dc095719fb1f6a91b9bed98a094e7d2e545a9214af`

The Linux log orders the observations unambiguously: both
`link didn't come up` messages occur before the later
`no iommu-map translation for id 0x0` / `0x8` warnings. The RID mapping warnings therefore
cannot explain failure of the physical links to train.

Linux `apple_pcie_setup_link()` also already implements the paired ADT timing shape. With no
endpoint-power GPIO it:

1. asserts PERST and enables refclk;
2. waits 100–200 microseconds;
3. deasserts PERST;
4. waits 100 milliseconds before configuration.

That matches the two bridge properties `t-refclk-to-perst = 100` and
`perst-to-config = 100`; timing is not the next justified delta.

A source diff against yuka's `t8140-pcie` head `a7857af8` found no additional endpoint-power
operation or post-LTSSM-start step.

## ADT endpoint-power correction

The captured J614s ADT is:

- `linux-build-out/j614s-full-20260728.adt`
  SHA-256 `2fe477c6…`

The exact WiFi topology is `/arm-io/apcie0/pci-bridge0/wlan`. Neither that child nor
`pci-bridge0` has a `pwren` callback. The separate top-level `/arm-io/wlan` node describes
`mriya`, `amfm-managed-port-control`, and `function-sac`, but no power-enable operation.
Captured PMGR state contains the general APCIE domains and no WLAN-specific domain.

The `gP19` SMC-key callback is real, but it belongs to the SD-reader child:
`/arm-io/apcie0/pci-bridge1/pcie-sdreader/function-sd_pwr_en`, not to `pci-bridge1` itself.
It is relevant only to port 1 and remains outside the permitted SMC-write surface. No paired
evidence supports inventing a corresponding WiFi rail write.

## Paired Apple port-reset comparison

The paired executable used for the comparison was extracted from the 25F84 kernelcache:

- `com.apple.driver.AppleT6040PCIe`
  SHA-256 `04dbbfcf7e2b2a43bc49132ca02942491e8b672bcf204986a51d0c726d96dff9`
- `ApplePCIEBaseT8132Port::_resetPortHardware`
  at `0xfffffe0009b39ae0`

`AppleT6040PCIePort` uses this base implementation; its paired subclass does not override the
enable/reset sequence. Comparing the fixed port-core reset table against the proven upstream
V1 source (`04e8829cbc47ff6a05e872dd329cdabb83554ce0`) found two value mismatches:

| ADT-derived port aperture | paired Apple | m1n1 V1 |
|---|---:|---:|
| `port + 0x13c` | `0x00000000` | `0x00000010` |
| `port + 0x130` | `0x03020000` | `0x03000000` |

The captured `apcie-config-tunables` touches only `port + 0x140` (mask/value `1`), so it
does not overwrite either mismatch. The paired routine also clears 256 MSI-map entries while
m1n1 clears 512; that difference was deliberately left unchanged because it is unrelated to
pre-enumeration physical link training and is not needed to test the two fixed values.

## Bounded candidate

Source:

- worktree: `/Users/damsleth/Code/m1n1-pcie-port-reset`
- branch: `codex/t6040-pcie-port-reset`
- signed commit:
  `afd13c037597c0659cf4d0e37b75f0e3c4ad78ef`
- parent/proven V1 baseline:
  `04e8829cbc47ff6a05e872dd329cdabb83554ce0`

The change is gated on `APCIE_T8132`, uses the existing ADT-derived port apertures, and changes
only the two fixed values above. It introduces no address, SPMI, SMC, PMU, charger, NVRAM, or
firmware access.

Two clean builds were byte-identical:

- `/Users/damsleth/Code/linux-build-out/t6040-pcie-port-reset-afd13c03/m1n1.bin`
- size: `1,097,728` bytes
- SHA-256: `4316500701e247dd07a07ec799464499cc769cce32ab58e806bb8e7981860c6d`
- build tag: `afd13c03`

Ticket 180 pins this exact source and artifact. It remains `proposed` and requires:

1. Claude's exact-artifact review;
2. CJ's explicit approval and presence;
3. a fresh power cycle and exactly one `pcie_init()` invocation;
4. collection of both port link states.

PASS is port 0 `DLL_LINK_ACTIVE=1` followed by BCM4388 endpoint enumeration. Any abort or hang is
a stop/recover result. V2 remains unnecessary and must not be run.
