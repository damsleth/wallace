# T6040 removable stage-2 boot architecture

Date: 2026-08-19
Ticket: 3010
Scope: offline design; no rig, media, enrollment, or hardware access

## Decision

Use one rarely changed, 16-KiB-aligned m1n1 object as the enrolled object and
embed an SD-capable U-Boot as its normal next stage. Keep a permanent short
DebugUSB/DTR proxy window before U-Boot. U-Boot loads a board-bound daily Linux
bundle from SD first; USB uses the same bundle contract later, after the VBUS
track has a bounded result. If no valid removable bundle exists, U-Boot records
a one-shot reason in reserved normal RAM and requests a warm reboot. The newly
started enrolled m1n1 consumes and clears the reason before payload selection,
then enters the real `Running proxy...` path.

This makes the removable Linux bundle the daily-changing object. Enrollment is
reserved for changes to the small stage-1 object and is never part of the normal
kernel/DT/initramfs update loop.

```text
iBoot / Boot Policy
        |
        v
enrolled m1n1 (total object size is a multiple of 16 KiB)
        |
        +-- valid one-shot proxy cookie --> clear cookie --> Running proxy...
        |
        +-- host connects during short DTR window --------> Running proxy...
        |
        `-- window expires --> embedded U-Boot
                                  |
                                  +-- valid SD bundle --> Linux daily system
                                  |
                                  +-- valid USB bundle -> Linux (later)
                                  |
                                  `-- no valid bundle
                                        -> set one-shot RAM cookie
                                        -> permitted warm reboot
                                        -> enrolled m1n1 -> Running proxy...
```

There is no U-Boot-to-m1n1 return edge. Current m1n1 treats a returned next
stage as a panic (`src/main.c:240-245`), and no reviewed reverse-handoff
contract exists. Re-entering m1n1 through iBoot after a warm reboot gives every
component its normal entry state.

## Grounded starting point

- A self-contained enrolled m1n1 object already boots when the **total object**
  is 16-KiB aligned; the investigation and corrected result are recorded in
  `evidence/2026-07-25-t6040-enrolled-payload-rootcause.md`.
- m1n1 already has a proven early proxy window. With
  `EARLY_PROXY_TIMEOUT`/`EARLY_PROXY_UNCONDITIONAL`, a host connection calls
  `uartproxy_run()` before payload selection (`src/main.c:87-130`). Its normal
  no-payload path prints `Running proxy...` and enters the same proxy
  (`src/main.c:153-172`).
- Tethered entry into a T6040 U-Boot Image is already proven. In ticket 131,
  m1n1 armed its 20-second watchdog, vectored into WDT-less U-Boot, and the
  watchdog warm-reset the machine to the enrolled proxy
  (`evidence/2026-07-25-t6040-uboot-stage2-banner-result.md`). The cookie makes
  that recovery an intentional one-shot mode selection; the existing watchdog
  remains the reset backstop if an immediate reboot request fails.
- The existing `chainload=` file loader is not a removable-media loader. It
  calls `nvme_init()` before `rust_load_image()` (`src/chainload.c:117-133`).
  This design therefore does not extend that path or depend on Linux NVMe.
- Completed ticket 128 produced a T6040 U-Boot stage-2 target, but it is
  USB-only: its defconfig disables MMC and its boot command starts USB
  (`patches/uboot-t6040-stage2-prep.patch`). It established the reusable build
  and embedding base, not removable SD support.
- The local U-Boot tree has an Apple PCIe driver with the T6020-compatible
  hardware match used by the T6040 fallback compatible, plus generic PCI
  SDHCI/MMC code that maps BAR0 and invokes the SDHCI core
  (`drivers/pci/pcie_apple.c`, `drivers/mmc/pci_mmc.c`). This makes an SD build
  testable, but does not prove the T6040 handoff.
- The Wallace J614s DTS identifies PCIe port 1's GL9755 as `17a0:9755`, with
  inverted card-detect and write-protect. Linux has already proven the reader
  and persistent SD root at `maxcpus=1`.
- The current SD64 outer filesystem is exFAT. U-Boot cannot load the daily
  bundle from it. The first loader media must therefore use a small FAT32 boot
  partition or a separately identified development card. Nothing in this
  design authorizes modifying SD64.

## State machine and failure behavior

| State | Allowed transition | Failure behavior |
|---|---|---|
| m1n1 entry | Validate and consume cookie before payload selection | Invalid, stale, or corrupt cookie is cleared/ignored; the DTR window remains available |
| early proxy window | Host handshake enters `uartproxy_run()` | Timeout continues to U-Boot; it must not be treated as a boot failure |
| U-Boot SD discovery | Enumerate only the reviewed PCIe/DART/GL9755 path | Missing card, controller error, or invalid bundle is `no valid bundle`; never scan unknown MMIO or devices |
| bundle validation | Accept only the J614s/T6040 manifest and all matching hashes/sizes | Any mismatch rejects the whole generation; do not mix files from two generations |
| Linux handoff | Boot Image + exact DTB + initramfs + bootargs | Daily profile remains `maxcpus=1`, ANS/NVMe disabled, trackpad-enabled, and Norwegian-layout compliant |
| no valid bundle | Write one-shot RAM cookie, synchronize it, request only the permitted `smc_reboot`; the already-proven m1n1 watchdog remains armed as a bounded fallback | If the immediate request fails, watchdog reset still returns to the permanent early DTR window; never store the reason in NVRAM |
| cookie proxy | Clear cookie first, then print `Running proxy...` and enter uartproxy | Clear-before-enter prevents replay/reboot loops |

The boot search is deterministic: SD is the only first implementation. USB is
added after ticket 305 proves an exact VBUS/PD contract and ticket 3018 assigns
that transition to one owner. The loader does not fall through to internal
NVMe while tickets 206/227 remain open.

## Ownership gates

The design fixes responsibility at subsystem boundaries but deliberately does
not guess the unresolved PCIe handoff:

| Resource | Owner / rule |
|---|---|
| Boot Policy and object selection | iBoot; agents do not change it. Enrollment is maintainer-only after all tethered gates pass. |
| Early DebugUSB and proxy | m1n1. The short window is permanent in the enrolled object. |
| Proxy cookie validation/clearing | m1n1, before payload selection. |
| Proxy cookie creation and warm reboot request | U-Boot; normal RAM plus the already permitted `smc_reboot` only. |
| PCIe common PHY/controller and port-1 link | m1n1 initializes once per iBoot cycle. Ticket 3011 resolved this boundary; U-Boot's SD target may attach only to an already-up link and may not retry port setup. |
| SD endpoint power | m1n1 performs one ADT-gated, exact `gP19 <- 0x01000001` before PCIe initialization, then waits 100 ms. No other SMC key. |
| DART1, PCI enumeration, GL9755 SDHCI | U-Boot owns mappings and reads while loading; its existing OS-prepare removal clears DART translations before Linux. |
| USB/PD | Absent from the SD candidate. Later ticket 3018 is constrained to the right-port `hpm2` result and upstream-owned ATC PHY work is track-only. |
| Linux device ownership | Starts only after U-Boot's documented quiesce/handoff. ANS/NVMe remains disabled in the daily DTB. |

The single-owner PCIe rule is load-bearing. m1n1 currently calls `pcie_init()`
while preparing a Linux DT (`src/kboot.c:2887`), while U-Boot's Apple PCIe
driver performs its own reset/link setup. Earlier T6040 work established that a
wrong PHY sequence can fault, and ticket 168 directly proved the cross-instance
case: running `pcie_init()` in the proxy and again in a chainloaded m1n1 caused
a synchronous abort at the port-2 PHY-IP window. Ticket 3011 must choose and
prove one handoff before a U-Boot SD build is considered bootable. Ticket 3011
has now done so: m1n1 owns the common-PHY/link sequence; U-Boot gets a
preinitialized-link-only attach mode and owns only PCI enumeration, DART1 DMA
mappings, and SDHCI. The detailed audit is in
`evidence/2026-08-19-t6040-uboot-sd-ownership-audit.md`.

## Removable bundle contract

Ticket 3014 owns the exact encoding and tooling. The architecture requires:

1. one board identity (`apple,j614s` / T6040) and one monotonically named
   generation;
2. exact SHA-256 and size for Image, DTB, initramfs, and bootargs, or a FIT that
   binds the same inputs;
3. deterministic host construction and full readback verification on a
   synthetic image before any physical-media proposal;
4. atomic generation selection so an interrupted copy cannot combine old and
   new members;
5. the daily safety profile: `maxcpus=1`, ANS/NVMe disabled, current trackpad
   reset contract and firmware, WiFi/BT firmware, shutdown pivot, and the
   Norwegian console/OpenRC/Xorg layout checks;
6. strict maximum sizes and load ranges that do not overlap m1n1, U-Boot, the
   ADT, SEPFW, reserved cookie memory, or each other.

The loader may report why a bundle was rejected, but it never repairs,
repartitions, formats, mounts read/write, or falls back to a partially valid
generation.

## Delivery sequence

1. **3010 (this document):** freeze the architecture and fail-closed edges.
2. **3011:** choose the PCIe/DART/GL9755/gP19 ownership contract from source and
   ADT/DTS evidence.
3. **3012:** implement the one-shot RAM cookie with host tests.
4. **3013:** build the SD-only U-Boot target twice from clean trees.
5. **3014/3019:** implement bundle tooling and prepare a zero-I/O physical-media
   plan; a real card mutation requires a later exact target and explicit
   authorization.
   **3020** packages the exact daily Linux handoff and tests it against a
   synthetic FAT image before any removable target is considered.
6. **3015/3016:** compose and independently exact-review the aligned,
   tethered-only stage-1 object.
7. **3017:** with the rollback still enrolled, chainload the object and perform
   a read-only GL9755/MMC/GPT first light. SD64 intentionally has no valid FAT
   bundle, so the expected terminal path is one warm reboot back to the enrolled
   rollback proxy.
8. Only after first light, a separately authorized media-install ticket can pin
   a physical target and write/readback hashes. Tethered Linux boot follows.
9. A maintainer-attended final ticket can then enroll the reviewed object and
   prove three independent cases: DTR-to-proxy, valid-SD-to-Linux, and
   no-media-to-warm-reboot-to-proxy. The rollback object remains the recovery
   artifact until all three pass.

## Explicit non-goals and graves

- no direct U-Boot-to-m1n1 return;
- no m1n1 exFAT implementation and no claim that U-Boot reads exFAT;
- no internal-NVMe dependency or revival of refuted NVMe doorbell/tag/SPTM
  explanations;
- no NVRAM, PMU, charger, rail, or firmware write;
- no SPMI in the SD candidate;
- no generic HPM/SID iteration, guessed ATC PHY offsets, or blind MMIO;
- no automatic enrollment or Boot Policy change;
- no modification of the working SD64 fixture until an exact separately
  approved physical-media ticket exists.

## Outcome

The architecture is feasible with the components already present, but it is
not one patch away. The shortest defensible route is SD-first because the
reader and Linux root are proven and U-Boot already has the two generic driver
pieces. The critical uncertainty is the m1n1/U-Boot PCIe ownership transition,
not filesystem parsing. Tickets 3011-3017 turn that uncertainty into bounded,
reviewable work while preserving the known-good proxy recovery path.
