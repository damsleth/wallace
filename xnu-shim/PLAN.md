# XNU-shim → internal NVMe on M4 (T6040/T6041) — implementation plan

Goal: give Linux **internal NVMe (read + write)** on M4 by booting through a permissive
XNU kernelcache that brings up genuine SPTM, intercepting after `init_xnu_ro_data`, and
pivoting to Linux that inherits a live SPTM with the NVMe IOMMU dispatch registered.
This is ticket **055** (route), with the former ticket **053** trace route retired and the
static handler work complete:

- `done/2026-07-14-t6040-nvme-sptm-route-finding.md` — the blocker (raw boot: no resident SPTM)
- `done/2026-07-14-t6040-sptm-xnushim-asahi-neo-crossref.md` — the route + capability model + ticket-007 retraction
- `done/2026-07-14-t6040-sptm-nvme-guarded-backend-decode.md` — the guarded-side NVMe op map (ops 0..8)
- `done/2026-07-23-t6040-sptm-nvme-op-args.md` — byte-proven handler arguments
- `done/2026-07-23-t6041-sptm-exact-blob.md` — exact T6041 offsets and policy delta
- asahi_neo `ARCHITECTURE.md` / `docs/SPTM_FINDINGS.md` — the XNU-shim mechanism (A18 Pro origin)

## Honest status (read before touching anything)

This is a **research-stage, upstream-scale bet (~15–30%)**. Nothing here boots today. The
value delivered *now* is the offline foundation (interface from the decode, skeletons,
escalation). The boot itself is gated on three walls, none of which this session clears:

1. **Domain provenance is unproven** — the whole route assumes a post-handoff Linux at EL1
   is still tagged `XNU_DOMAIN` by SPTM (domain is read from `TPIDR`/context, not the x16
   immediate — paper §5.4.1). The HV trace route is infeasible; only upstream knowledge
   or a future signed shim boot can confirm this.
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
| **P0** | SPTM/NVMe interface, exact handler arguments, three-SoC comparison, shim skeletons, escalation, signing scope | offline | — | **COMPLETE** |
| **P1** | Validate domain provenance and outer IOMMU marshalling | upstream answer or shim boot | signed permissive KC | blocked |
| **P2** | Permissive XNU KC + shim kext; intercept at `IOPlatformExpert::start()` post-`init_xnu_ro_data` | signing + toolchain | P1 | blocked |
| **P3** | Linux loader via SPTM `retype`/`map_page`; FDT; EL1 handoff | rig | P2 | blocked |
| **P4** | NVMe bring-up ops 0..8 from Linux; confirm **read**; then **write** behind an APFS-safe carve-out | rig | P3 | blocked |

## P0 — what is startable now (this pass), and why each is well-founded

- **`include/sptm_nvme_iface.h`** — the SPTM dispatch descriptor + the NVMe op enum (0..8)
  from `func_state[N]`, the `allowed_functions` call-ordering, and the domain/permission
  facts and exact guarded-side argument layouts. Outer IOMMU marshalling remains stubbed.
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
| 0 | guarded instance init | no caller arguments |
| 1 | SetTCB + DMA pages | qid/cid/TCB/list/count validation |
| 2 | TCB completion/invalidation | qid/cid/state transition |
| 3 | queue/protocol configure | queue entries + protocol version |
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

**UPDATE 2026-07-15: the HV genter-trace (ticket 053) is DEAD.** m1n1-HV is SPTM-blocked on
T6040 (`docs/DEVLOG.md` dead-ends:668; `done/2026-07-15-t6040-sptm-hv-trace-preflight.md`), so
there is no hypervisor to trace macOS's SPTM calls with. 053/056 closed as infeasible. The two
things it was meant to deliver are re-homed:

- **Per-op arg contract → static** (ticket 051 SPTM-blob handler disasm + 054 cross-SoC diff).
  No rig, no approval. This is the actionable next step.
- **Domain provenance across the pivot → ticket 055 escalation + static blob reasoning.** No
  longer empirically testable pre-build (that was the HV trace's job); the #asahi-dev
  escalation is now the primary answer, the shim boot itself (Phase 3+) the only full one.

**Consequence:** there is no useful *rig* experiment for the shim track until the shim is
built (Phase 2+, gated on the signing path). Pre-build progress is entirely static (051/054)
+ the escalation (055). The rig belongs to the other tracks meanwhile.
