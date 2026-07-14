# XNU-shim → internal NVMe on M4 (T6040/T6041) — implementation plan

Goal: give Linux **internal NVMe (read + write)** on M4 by booting through a permissive
XNU kernelcache that brings up genuine SPTM, intercepting after `init_xnu_ro_data`, and
pivoting to Linux that inherits a live SPTM with the NVMe IOMMU dispatch registered.
This is ticket **055** (route), gated by ticket **053** (HV trace) and the done evidence:

- `done/2026-07-14-t6040-nvme-sptm-route-finding.md` — the blocker (raw boot: no resident SPTM)
- `done/2026-07-14-t6040-sptm-xnushim-asahi-neo-crossref.md` — the route + capability model + ticket-007 retraction
- `done/2026-07-14-t6040-sptm-nvme-guarded-backend-decode.md` — the guarded-side NVMe op map (ops 0..8)
- asahi_neo `ARCHITECTURE.md` / `docs/SPTM_FINDINGS.md` — the XNU-shim mechanism (A18 Pro origin)

## Honest status (read before touching anything)

This is a **research-stage, upstream-scale bet (~15–30%)**. Nothing here boots today. The
value delivered *now* is the offline foundation (interface from the decode, skeletons,
escalation). The boot itself is gated on three walls, none of which this session clears:

1. **Domain provenance is unproven** — the whole route assumes a post-handoff Linux at EL1
   is still tagged `XNU_DOMAIN` by SPTM (domain is read from `TPIDR`/context, not the x16
   immediate — paper §5.4.1). Until ticket **053** (HV genter trace on the rig) confirms
   this, the shim's ability to issue *any* SPTM call as Linux is a hypothesis.
2. **No permissive-kernelcache signing/build path exists here** — Phase 2 needs a
   non-Apple-signed XNU-style kernelcache under Permissive Security with our shim kext
   linked in. Toolchain + signing unproven on this project.
3. **No rig access in this workstream** — Phases 3–4 run only on the tethered M4.

Do **not** write loader/handoff code as if it works before Phase 1 (053) closes. We just
retracted ticket 007 for inventing a precise ABI; do not repeat that with invented arg
layouts. Where the decode is uncertain, the code says `/* TBD-055: … */` and cites the ticket.

## Phase map

| Phase | Deliverable | Needs | Gate | This session |
|---|---|---|---|---|
| **P0** | SPTM/NVMe interface from the decode; bring-up sequence skeleton; shim skeletons; Asahi escalation draft; signing-path scoping | offline | — | **STARTED (this pass)** |
| **P1** | Validate domain provenance + capture live per-op args; finalize `sptm_nvme_iface` | **rig** (ticket 053) | m1n1 GXF-on-M4 first | blocked → 053 |
| **P2** | Permissive XNU KC + shim kext; intercept at `IOPlatformExpert::start()` post-`init_xnu_ro_data` | signing + toolchain | P1 | blocked |
| **P3** | Linux loader via SPTM `retype`/`map_page`; FDT; EL1 handoff | rig | P2 | blocked |
| **P4** | NVMe bring-up ops 0..8 from Linux; confirm **read**; then **write** behind an APFS-safe carve-out | rig | P3 | blocked |

## P0 — what is startable now (this pass), and why each is well-founded

- **`include/sptm_nvme_iface.h`** — the SPTM dispatch descriptor + the NVMe op enum (0..8)
  from `func_state[N]`, the `allowed_functions` call-ordering, and the domain/permission
  facts. Encodes *only* what the decode proved; every arg layout is marked TBD-051/053.
- **`src/nvme_bringup.c`** — the ops 0..8 sequence a post-handoff Linux would issue, in
  `allowed_functions` order (protocol → queue-entries → TCB → admin-queue → IOQA → IOSQ →
  IOCQ → ANS-SHA). Documented skeleton; issues nothing until P1 confirms the call path.
- **`src/shim_entry.c`, `src/linux_loader.c`, `src/fdt_builder.c`** — honest skeletons of
  the intercept/load/handoff, each a TODO tied to its gating phase/ticket.
- **`docs/asahi-dev-escalation.md`** — ticket 055's stated deliverable (draft only, CJ posts).
- **`docs/signing-path.md`** — scope the Permissive-Security kernelcache question (Phase 2
  blocker): what iBoot requires, whether a shim kext can be linked, the open unknowns.

## The NVMe bring-up contract (from the decode — the spine of P4)

Guarded-side backend `nvme.c`, 9 ops in `nvme_instance->func_state[0..8]`, each gated by
`validate_nvme_call_allowed` against `allowed_functions` (call-ordering capability):

| op | function | validated |
|---:|---|---|
| 0 | protocol negotiate | `validate_nvme_protocol_version` |
| 1 | queue-entries / TCB setup | `validate_nvme_queue_entries`, `validate_cid` |
| 2–3 | TCB / CID ops | `validate_cid`, `invalidate_tcb_entry` |
| 4 | `sptm_nvme_bar_admin_queue_regs` | queue addr/len |
| 5 | `sptm_nvme_bar_ioqa_reg` | — |
| 6 | `sptm_nvme_bar_iosq_reg` | queue addr/len |
| 7 | `sptm_nvme_bar_iocq_reg` | queue addr/len |
| 8 | `sptm_nvme_ans_sha_reg` | ANS SHA addr/size |

**Write is not a separate gate**: read and write ride the same authorized queues + the
per-CID TCB DMA authorization (`sptm_nvme_map_pages`). The write-specific work is
*operational* — carve a dedicated APFS volume, respect ANS/SEP key handling — solved on
M1/M2 Asahi, layered on top, not a new SPTM gate. See P4.

## Immediate next action (the real critical path)

**Ticket 053 (HV genter trace).** It is the pivot: it answers domain provenance (go/no-go
for the whole route) and captures the live per-op arg registers that turn `sptm_nvme_iface.h`
from spec into truth. It needs the rig + m1n1 GXF-on-M4 brought up first (ticket 046). Until
053 runs, P2–P4 are premature. P0 (this pass) is the honest extent of offline progress.
