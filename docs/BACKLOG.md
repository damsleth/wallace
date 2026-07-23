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

## Priority & dependency order (updated 2026-07-23)

There are now two explicit milestones. **B0 bootable build** is an enrolled,
self-contained Alpine RAM distro and does not wait for Linux storage. **B2
usable persistent distro** still requires external USB root because internal
NVMe is NO-GO near-term (008: SPTM-gated, no raw-boot guarded entry). The
sequenced gates are in `docs/BOOTABLE_BUILD_EXPERIMENTS.md`.
In rough order of leverage:

1. **B0 bootable-build pipeline** (distro/HID, P1). Run proposed TX-only trace
   capture **076** only after explicit approval; decode it offline in **077**,
   build one minimal HID-restored candidate in **078**, then produce the
   release-like RAM distro in **079**. **080 is complete**: direct raw m1n1,
   entry `0x800`, exact concatenated payload contract, and strict host
   verifier are documented. **081** packages a single self-contained object
   and prepares a tethered one-object proof; **082** prepares reversible raw
   enrollment and cold boot. Direct m1n1 is the selected B0 route; U-Boot
   ticket **025** is B1; its no-MMIO framebuffer/EFI-hello prep is complete,
   with any live proof deferred until after B0. Installer requirements ticket
   **026** is complete:
   raw enrollment already exists upstream; atomic self-contained-object
   handling, J614s/T6040 admission, and macOS 26 firmware extraction are the
   remaining upstream gaps.
2. **USB-root pipeline** (storage, P1 — the persistent Stage D exit).
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
   Reviewed rig control **070** was inconclusive: the old keyboard kernel never
   reached the Alpine framebuffer shell in two exact attempts and has no
   ttydc0 failure log. Do not retry it. The one-shot corrected-kernel **071**
   still produced no input devices, disproving that change as a sufficient fix.
   Offline **072** built and statically verified the observation-only
   IRQ/FIFO/DCHID state trace without a receive-path control change.
   Independently reviewed one-shot capture **074** reached Alpine over ttydc0
   TX, but ttydc0 RX was non-responsive, so the trace could not be requested.
   Do not retry it unchanged. Offline ticket **075** built and host-tested a
   bootarg-gated automatic TX reporter; independent exact-archive review
   passed. Proposed one-shot TX-only capture **076** awaits explicit maintainer
   approval. No speculative receive kick.
   **060** is complete as a guarded, host-tested recipe; do not use its
   destructive device mode or populate a persistent USB rootfs until
   enumeration persists for ≥10 s. Then ROOT-mode `switch_root` → **024**
   interim untethered boot.
3. **PCIe → WiFi/BT** (pcie, P1). Op-115 stalls on its read side; **058** is
   the offline route-finding for the missing PHY-IP aperture precondition; only
   a new evidence-backed manifest goes live. **044** (port-0/BCM4388 manifest)
   is the pre-reviewed stage after link-up; then firmware (staged, ticket 030
   corpus).
4. **Two-way remote console** (console, P2 but high leverage for every later
   rig experiment). Poll-mode tty is proven. The ADT's IRQ 360 is now known
   wrong; measured UART input is 816, so 059's timing image is closed
   superseded. Audit/adapt the WIP direct `apple,dockchannel-uart` IRQ-816
   earlycon/`ttyDC0` path under **062** before proposing another rig test.
5. **Make the approved rig queue runnable** (smp/cpufreq/hid). 004/005/006 are
   approved with hashes TBD — **034** (SMP DT preflight) and **035** (cpufreq
   DT preflight) produce the pinned images. Trackpad provisioning **016** is
   complete (`tpmtfw-j614s.bin` `a1f4131d...`); ticket 004 now needs its exact
   kernel/DT/initramfs rebuild and review before it is runnable.
6. **Upstreaming proven work** (xcut, P1): SMP/cpufreq posting drafts are
   finalized under completed **019**; **046** rebases and shapes the actual
   m1n1 T6040 patch series, followed by **047** DT consolidation and **048**
   host tools. PMGR series is draft-ready (CJ asks flokli re J773s policy and
   posts).
7. **Stage-D comforts, offline-preparable**: **061** SMC DT wiring (battery,
   power button, lid — read-only keys). **037** is complete: its audited patch
   set is intentionally empty because none of the 26.x deltas is
   version-gate-only.
8. **SPTM internal-NVMe long shot** (storage, background): 051/052/054/055 —
   static decode + the XNU-shim escalation draft for #asahi-dev. No rig time.
9. **Track-and-test** ([UPSTREAM] tickets): 022 DCP, 023 ATC PHY, 026
   installer, 039 GPU — watch, report, don't build here.

## Lanes (avoid duplicate work; not exclusive ownership)

Per COORDINATION.md roles, extended for the USB-root era:

| Lane | Primary | Current contents |
|---|---|---|
| Storage: RAM-root + USB-root pipeline + SPTM | **sol** | Alpine RAM-root boots; trace current-kernel HID boundary; powered USB later → ROOT boot or upstream HPM/ATC; 051/052/054/055 |
| PCIe/WiFi-BT, DockChannel console | **claude** | 058, 044; 062 IRQ-816 direct-driver audit |
| Rig-queue preflights, SMC/PM, upstream drafts | **claude** (first grab) | 061; 046/047/048 (019 complete) |
| Rootfs recipe, xcut, tracking | either (queue order) | 060, 029/030, 022/023/026/039 |

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
- Any blind MMIO probing, or any SPMI/PMU/charger/NVRAM write.
- Any further DockChannel IRQ-360 diagnostic — input 360 came from a lying ADT;
  bounded M4 Pro measurement found the real UART interrupt at AIC input 816.
