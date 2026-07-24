# BACKLOG — strategy & priorities

This is the **map**, not the ticket list. The actionable work lives in tickets:

- **`tickets/`** — one git-tracked JSON file per ticket, offline tasks and rig
  experiments alike. Managed only through the CLI (don't hand-edit):
  ```sh
  scripts/rig-lease.sh queue list [--rig|--offline]   # what's there
  scripts/rig-lease.sh queue next --offline           # next open offline task (grab it)
  scripts/rig-lease.sh queue next --rig               # next approved rig experiment (needs lease)
  scripts/rig-lease.sh queue add <you> <slug> "<desc>" --needs offline|rig [--track T --pri P1 --dep NNN]
  scripts/rig-lease.sh queue approve 001-006 --by cj  # rig tickets only; offline needs no approval
  scripts/rig-lease.sh queue show <seq>               # full JSON
  ```
- **`.rig/`** — the lease only (ephemeral, gitignored). Not the backlog.

Each ticket has `needs: offline | rig`. **Offline tickets** (`state: open`) need
no rig and no approval — any agent grabs one and does it; that's where parallel
speed comes from, so favour them. **Rig tickets** (`state: proposed` →
`approved` → `done`) need the lease and CJ's approval, and their depth is
bounded by data-dependency (you can't spec step N+2 before step N runs), so the
rig list stays short and the deep pipeline stays here as offline analysis.

**Pre-approval semantics:** `queue approve` authorizes the *plan*. The per-image
safety gate still stands — before an agent boots a new-MMIO image, the other
agent cross-reviews the exact hashes against `~/Code/m1n1/AGENTS.md`
(§ Cross-agent review in COORDINATION.md).

## Priority & dependency order (updated 2026-07-24)

There are now two explicit milestones. **B0 bootable build** is an enrolled,
self-contained Alpine RAM distro and does not wait for Linux storage. **B2
usable persistent distro** still requires external USB root because internal
NVMe is NO-GO near-term (008: SPTM-gated, no raw-boot guarded entry). The
sequenced gates are in `docs/BOOTABLE_BUILD_EXPERIMENTS.md`.
In rough order of leverage:

1. **Restore the rig link** (xcut, P0). Ticket 095 passed its intended
   SSPS-to-S0 boundary, but the following VDM recovery and one bounded KIS
   reattach failed. The rig is free and **NEEDS_RECOVERY**. The first hardware
   action is a recovery boot, stable `Running proxy`, and
   `rig-lease.sh recovered <agent>`—not another experiment.
2. **B0 bootable-build pipeline** (distro/HID, P1). Captures **076**, decode
   **077**, and the HID-type repair **078** are complete. The rebased
   `hid-apple` rejected the untyped BUS_HOST keyboard; the minimal type
   assignment now live-registers `input0/event0`. **079 is complete** with a
   twice-reproducible Alpine/OpenRC RAM distro (`ddd98171...`), normal
   runlevels, dual local consoles, watchdog, and no storage/network runtime
   configuration. **080 is complete**: direct raw m1n1,
   entry `0x800`, exact concatenated payload contract, and strict host
   verifier are documented. Ticket-078's exact HID-restored Alpine components
   were packed in reproducible object `b50f52ab...`; control **089** passed one
   upload with no `linux.py`. The final release object `2371ee5d...` passed
   independent review and ticket **100**'s tethered single-object boot:
   OpenRC, watchdog, panel shell, internal keyboard, and empty partitions.
   **081/100 are done.** **082** has the reversible enrollment procedure and
   now needs the target-volume UUID, enrolled-object backup/hash, review and
   trigger validation of dual-mode candidate `46237ade...`, and execution
   split confirmation. **101** is plan-approved but not runnable until those
   items and rig recovery pass. Direct m1n1 is the selected B0 route; U-Boot
   ticket **025** is B1; its no-MMIO framebuffer/EFI-hello prep is complete,
   with any live proof deferred until after B0. Installer requirements ticket
   **026** is complete:
   raw enrollment already exists upstream; atomic self-contained-object
   handling, J614s/T6040 admission, and macOS 26 firmware extraction are the
   remaining upstream gaps.
3. **USB-root pipeline** (storage, P1 — the persistent Stage D exit).
   Build/port-map gates
   are clear. Ticket 063 proved the right-port DART+xHCI root hubs but no child
   device enumerated. **064** bounded the gap to the Linux-absent SPMI HPM +
   T6040 ATC/ACIO physical-link path. Powered test **065** is cancelled unrun
   because the hub supply is unavailable. **067** booted Alpine RAM-root and
   cleared the storage-free userspace checks, but exposed a 7.1.3 USB-host
   kernel regression: MTP says the keyboard is ready while Linux registers no
   input device. Offline **069** tested the current-mailbox RX
   acknowledge/drain race with a storage-disabled mask/drain/re-arm candidate
   and the failed image's config byte-for-byte.
   The 2026-07-24 paired-kext decode now proves the T6040 44-bank ATC map and
   tunable encoding exactly. Its direct eUSB2 sequence is now bounded to banks
   0/1 and six offsets, and paired XHCI proves the exact host branch; ticket
   **023** now also proves the target is SPMI Gen3 and bounds the class-10 HPM
   discovery reads. HALType5/Type10 selection and the first nine-byte host RMW
   are exact too, but ticket 023 remains open for the separately gated
   disconnect/rollback, power/config, and repeater path.
   Yuka's new compiling `tps6598x-spmi` branch (`dcc5f1bc...`) is the first
   public code to match the exact J614s SPMI/SN201202x nodes, but reported
   hardware success covers only T6000/I2C. The 2026-07-24 endpoint-scoped
   policy now permits separately reviewed right-HPM2 operations while keeping
   PMU/charger/NVRAM/firmware and unknown endpoints prohibited. Offline
   **092** produced reproducible staged candidates. The first R0 live attempt
   failed closed before SPMI because the standard chainloader changes volatile
   ADT handoff fields. Its replacement also failed closed before SPMI after
   correctly exposing a raw-versus-translated ADT address mismatch in the
   gate. m1n1 `471700035efd` requires both the raw `0x309...` tuples and
   translated `0x509...` physical banks. R0/**093** then proved the selector
   window stays inactive until WAKEUP. Narrowed R1/**094** passed with one
   WAKEUP and a read-only state result of `0x07`; no extended write was linked.
   Ticket **095** then passed the narrowed SSPS-only boundary: initial state
   `0x07`, exact DATA1/CMD1 `SSPS`, final S0 state `0x00`; mask access was
   absent and remains untested. Offline **096** owns class-10 detach/rollback.
   Umbrellas **097/099** are decomposed into post-S0 status, optional mask only
   if justified, HPM host transition, ATC/xHCI enumeration, read-only block
   identity, separate destructive flashing, bounded read-write root, and
   untethered root boot. Corrected OpenRC image **098** is complete
   (`1c493fad...`, PARTUUID `e4731abe-...`). Each new live step needs its own
   review and approval. Exact child ladder: **102–113**.
   Canonical rules: `docs/SPMI_SAFETY.md`.
   Reviewed rig control **070** was inconclusive: the old keyboard kernel never
   reached the Alpine framebuffer shell in two exact attempts and has no
   ttydc0 failure log. Do not retry it. The one-shot corrected-kernel **071**
   still produced no input devices, disproving that change as a sufficient fix.
   Offline **072** built and statically verified the observation-only
   IRQ/FIFO/DCHID state trace without a receive-path control change.
   Independently reviewed one-shot capture **074** reached Alpine over ttydc0
   TX, but ttydc0 RX was non-responsive, so the trace could not be requested.
   Do not retry it unchanged. Offline ticket **075** built and host-tested a
   bootarg-gated automatic TX reporter; capture **076**, decode **077**, and
   HID repair **078** then completed. No speculative receive kick remains.
   **060** is complete as a guarded, host-tested recipe; do not use its
   destructive device mode or populate a persistent USB rootfs until
   enumeration and read-only block identity pass. Tickets 110–113 then isolate
   flashing, tethered read-write root, and untethered boot.
4. **PCIe → WiFi/BT** (pcie, P1). Op-115 stalls on its read side; **058** is
   the offline route-finding for the missing PHY-IP aperture precondition; only
   a new evidence-backed manifest goes live. **044** (port-0/BCM4388 manifest)
   is the pre-reviewed stage after link-up; the complete restore-recoverable
   firmware corpus is staged and ticket 030 is done.
5. **Two-way remote console** (console, P2 but high leverage for every later
   rig experiment). Poll-mode tty is proven. The ADT's IRQ 360 is now known
   wrong; measured UART input is 816, so 059's timing image is closed
   superseded. Audit/adapt the WIP direct `apple,dockchannel-uart` IRQ-816
   earlycon/`ttyDC0` path under **062** before proposing another rig test.
6. **Make the approved rig queue runnable** (smp/cpufreq/hid). The exact
   preflights **034/035** are complete; 005/006 now record their real artifact
   and review gaps instead of “hashes TBD.” Trackpad provisioning **016** is
   complete (`tpmtfw-j614s.bin` `a1f4131d...`); ticket 004's exact reproducible
   kernel/DT/initramfs set is now pinned in its 2026-07-24 preflight and needs
   only an independent exact-artifact review before it is runnable.
7. **Upstreaming proven work** (xcut, P1): SMP/cpufreq posting drafts are
   finalized under completed **019**; **046** now provides the rebased
   nine-patch m1n1 RFC and cover letter. **047** now provides the consolidated
   J614s Linux DT series, and **048** provides clean m1n1-PTY and macvdmtool
   ACE3 mail drafts (kisd's T6040 support is already upstream). PMGR series is
   draft-ready (CJ asks flokli re J773s policy and posts).
8. **Stage-D comforts, offline-preparable**: **061** SMC DT wiring (battery,
   power button, lid — read-only keys). **037** is complete: its audited patch
   set is intentionally empty because none of the 26.x deltas is
   version-gate-only. **027** suspend analysis is complete and correctly gated
   on a reviewed T6040 retention/cpuidle contract; do not allowlist T6040 in
   the existing deep-WFI driver.
9. **SPTM internal-NVMe long shot** (storage, background): keep **114–117**
   host-only. Refresh public SPTM work, validate the service-6 contracts in a
   host harness, and audit guarded-state/domain provenance. Do not retry
   unchanged GENTER or raw NVMe BAR access; both have already failed at the
   protected boundary.
10. **Track-and-test** ([UPSTREAM] tickets): 022 DCP and 023 ATC PHY remain
   watchers. Installer 026 and GPU mule prep 039 are complete; the latter has
   an exact evidence packet and test contract but no safe G16 candidate.

## Lanes (avoid duplicate work; not exclusive ownership)

Per COORDINATION.md roles, extended for the USB-root era:

| Lane | Primary | Current contents |
|---|---|---|
| Storage: RAM-root + USB-root pipeline + SPTM | **sol** | Alpine RAM-root boots; trace current-kernel HID boundary; powered USB later → ROOT boot or upstream HPM/ATC; 051/052/054/055 |
| PCIe/WiFi-BT, DockChannel console | **claude** | 058, 044; 062 IRQ-816 direct-driver audit |
| Rig-queue preflights, SMC/PM, upstream drafts | **claude** (first grab) | 061; 019/046/047/048 complete |
| Rootfs recipe, xcut, tracking | either (queue order) | 029/030, 022/023; 026/039/060 complete |

The other agent still cross-reviews every live image regardless of lane, and
either agent picks up an abandoned lane rather than waiting.

`[UPSTREAM]`-tagged tickets (DCP, ATC PHY, installer, GPU) are track-and-test,
**not** build-here — this machine's unique value is Stages A–B and the DT/
enablement halves of C–E. See ROADMAP.md for the full stage map.

## Known dead-ends — do NOT propose (graves)

- Direct NVMe main/secure-BAR register writes, or the SPTM GENTER call unchanged
  (hangs; SPRR/GXF disabled on raw boot).
- SBU analog serial (confirmed dead on ACE3).
- USB gadget console (EP0 dies post-enumeration).
- Inventing ATC PHY per-bucket reg offsets.
- Any blind MMIO probing; any PMU/charger/NVRAM/firmware or unknown-SPMI
  write; or any non-PMU SPMI transaction outside the exact
  `docs/SPMI_SAFETY.md` allowlist and ticket.
- Any further DockChannel IRQ-360 diagnostic — input 360 came from a lying ADT;
  bounded M4 Pro measurement found the real UART interrupt at AIC input 816.
