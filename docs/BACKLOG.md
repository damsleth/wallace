# Backlog strategy

Current as of 2026-08-03. The JSON files in `tickets/` are authoritative.
This page explains priority and pruning; it does not duplicate every ticket.

## Queue model

- `tickets/`: active offline and rig work.
- `tickets/done/`: completed work.
- `tickets/archive/`: superseded, deprecated, deferred, or wontfix work.
- `.rig/`: host-local lease state, not project history.

Use `scripts/rig-lease.sh queue add` for new tickets. Sequence allocation is
not atomic, so immediately verify that the reported sequence still contains
the expected slug. Use `queue done` for completed work. Archive only when the
reason is explicit and the active dependencies remain understandable.

## Priority order

| Priority | Work | Tickets | Gate |
|---|---|---|---|
| P1 | Make the SD-root system operable | 204 | Panel observation, minimal console, then services |
| P1 | Preserve the modern NVMe crashlog | 201 | Exact logging-only artifact and one retained transcript |
| P1 | Review the threaded NVMe IRQ discriminator | 203 | Offline, two byte-identical builds; follows 201 for any live A/B |
| P1 | Keep the strict SD fixture sequence available | 199 → 200 | Read-only A before separately approved write B |
| P1 | Reframe the MM/SMP fault | 121 family | New evidence must explain COW faults and non-monotonic boots |
| P1 | Resolve trackpad reset state | 126 family | Exact approved volatile blob only |
| P2 | Design stage-2 storage | 191 | Offline; compare SD and NVMe honestly |
| P2 | Upstream proven enablement | 022, 023, 114–117 and patch drafts | No speculative live access |
| P3 | Desktop polish and optional distro work | 166 and related items | After SD-root reliability |

The queue may contain older dependency ladders whose later steps are not
runnable. Do not treat `approved` as `ready`: a rig ticket is schedulable
only when its plan is approved, exact hashes are pinned, dependencies are done,
and an independent reviewer records readiness.

## Active lanes

### Persistent system

The SD reader is the current storage path. Ticket 193 proved read/write
persistence; ticket 204 owns the usable root. USB-root work is no longer the
shortest path.

### Internal NVMe

Linux reaches a real exFAT mount, then firmware asserts at the first I/O CQ
wrap. The useful sequence is crashlog preservation, offline discriminator
review, then one-variable live tests. NVMe writes remain blocked.

Raw m1n1 sustained reads are separately proven and remain useful for a
fail-closed stage-2 design.

### CPU and input

Five cores work for the smaller RAM-root desktop, but later copy-on-write
faults invalidate the old fixed-threshold story. Trackpad HIDF upload is
accepted; the following state-0 interface reset is rejected. Both tracks need
better contracts, not broader integration images.

### USB host and Type-C

The right HPM reached S0, but no reversible role/VBUS/interrupt/PHY sequence is
known. Keep the decomposed USB ladder for its read-only and storage contracts,
but do not schedule its state-changing steps until new primary evidence closes
the R3 safety gaps.

### Long-term hardware

GPU, audio, camera, suspend, cpuidle, and backlight remain roadmap work. GPU
testing waits for explicit T6040/G16 support; suspend waits for a valid
retention contract.

## Pruning rules

Move a ticket to `tickets/done/` when its stated deliverable and evidence are
complete. Move it to `tickets/archive/` when:

- a later ticket or working path supersedes it;
- its artifact is invalid and its useful part has been folded elsewhere;
- its premise was disproved;
- it is deliberately deferred until a named condition appears.

Record `archived.at`, `archived.by`, and a concise reason. Do not archive a
dependency ladder merely because its first approach stalled; preserve any
still-useful read-only, rollback, or safety contract.

## Do not revive without new evidence

- direct SPTM `genter` or blind NVMe protected-register experiments;
- the NVMe “wrong SQ-doorbell window,” non-zero-tag, simple depth, or batching
  explanations already refuted;
- DockChannel IRQ 360; the measured input is 816;
- PCIe op-115 PLL theories; the proven fixes were the T6040 reset bit and
  endpoint power;
- generic HPM iteration, SID scans, blind MMIO, or unreviewed role/VBUS writes;
- USB gadget networking to the current macOS host using already failed
  descriptor shapes;
- G14 GPU tables relabeled as G16.
