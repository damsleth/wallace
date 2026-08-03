# T6040 internal-NVMe path — reassessment (2026-07-24)

Where the internal-SSD/NVMe route stands after the SPTM tickets (007/051/052/054/
055) closed and the 07-22..24 #asahi-dev signal. Static only; no rig, no storage
access ever performed.

## Verdict: unchanged headline, sharply reduced uncertainty

**Internal NVMe from raw m1n1 boot is still NO-GO** — and the reason is now
precisely bounded, not vague. Knowledge is **no longer the blocker**; the ABI is
fully decoded. The blocker is architectural (no genuine SPTM guarded state under
raw boot) plus two survival unknowns that *cannot be answered by any raw-m1n1
experiment*.

## What is now SOLVED (offline, all committed)

- **Service-6 guarded NVMe ABI fully decoded** (007): T6041 SPTM dispatch table 6,
  IOMMU id 2, XNU/XNU-hibernate permission mask `0x12`; all **nine** guarded
  handler arguments byte-proven; ops 0..8 mapped to the controller methods.
- **Structurally stable across T8132 / T8140 / T6041** (054): dispatch ids, op
  index, args, and state transitions are the stable contract; raw text offsets
  relocate per-firmware (proven by the three-image diff), so any offset must be
  tied to an exact firmware hash. T6041 adds stricter **segment-count / NLB**
  enforcement.
- **Exact T6041 SPTM blob offsets extracted** (052) for the paired firmware.
- **XNU-shim P0 foundation scaffolded** (055): guarded interface header, argument
  contract, bring-up-order skeleton, loader/FDT/shim skeletons, signing-scope doc,
  and the sharpened Asahi escalation draft. `sptm_nvme_call()` is a **hard stub**
  — no code can issue a live/malformed guarded call.

## The two decisive unknowns (block any live attempt; not statically answerable)

1. **Domain provenance:** after an XNU→Linux pivot, does Linux actually execute
   as `XNU_DOMAIN` in SPTM's *tracked* state, or merely write an XNU-looking
   descriptor SPTM won't honor?
2. **State survival across the EL1-owner change:** do CoastGuard TCB/CID, SART
   mappings, NVMe queue ownership, and the **SEP-loaded APFS key / controller
   state** survive when Linux replaces XNU as EL1 owner?

Neither can be resolved by more raw-boot probing — the ticket-007 decode already
proved the ABI is not the missing piece, and raw m1n1 boots with SPRR/GXF off and
an unconfigured GENTER vector.

## New external signal (07-22..24 IRC) — the wall may be moving

- **sven is prototyping SPRR emulation under hv on M4** (shadow pagetables +
  patching XNU: genter/gexit/locked-msr→`hvc`, lazy shadow-PTE fill, stage-2
  no-access trap for SPTM's new mappings, commpage/libsystem patch for the EL0
  JIT flip). This is the **first real movement on the SPTM wall**. If it lands it
  (a) reopens macOS-driver tracing on M4 and (b) is the most plausible substrate
  for observing/entering the guarded NVMe path our ABI decode already describes —
  our shim scaffold + decoded args would plug straight in.
- **chaos_princess (07-20): "order SEP to load specific keys into the nvme
  controller, and then magic happens"** — directly names unknown #2's mechanism:
  controller access is gated by a **SEP key-load step**, not just queue
  programming.

## Forward routes (both external/upstream; no rig time here)

- **A. Ride sven's hv/SPRR work** (track). When a degraded M4 hv exists, revisit
  tracing the macOS service-6 NVMe path and testing whether a shim inherits live
  SPTM state. Our 007/051/052/054/055 decode is the ready payload.
- **B. Asahi escalation** (CJ posts `archive/xnu-shim/docs/asahi-dev-escalation.md`): does
  the M4 boot chain offer *any* documented way for a permissive/custom object to
  enter genuine SPTM and expose the service-6 NVMe ABI — or is internal NVMe
  gated on an open SPTM re-implementation? Attach the ABI decode + the SEP-key
  and domain-provenance questions.

## Storage recommendation (unchanged, refined)

1. **Do not spend rig time** forcing service-6 GENTER from raw boot. Offline
   decode is complete; the remaining unknowns are architectural/external.
2. **Daily-driver storage stays off the internal controller:** the **B0 RAM
   distro** (works now, no persistent storage) is the immediate bootable milestone;
   **USB-attached root** is the persistent path — itself blocked on the HPM/ATC
   physical link (ticket 064), which **yuka's in-progress m1n1 tps6598x/HPM
   refactor** (07-23) is the upstream track to unblock.
3. **Internal NVMe re-opens only via route A or B** — both external. Keep the
   paired macOS at 26.x (not the 27 beta) so the decoded firmware offsets and any
   future shim/trace stay valid.
