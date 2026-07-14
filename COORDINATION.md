# COORDINATION.md — two agents, one rig

Two coding agents work this repo toward the same goal (mainline Linux on the
M4 Pro): **`claude`** and **`sol`** (GPT-5.6 Sol). This file is the protocol
they both follow. The maintainer (CJ) is the approval gate and tie-breaker.

## The one fact that shapes everything

There is exactly **one** physical rig: the M4, one DebugUSB cable, one m1n1
proxy, one `/tmp/m1n1` pty. Two agents touching it at once corrupts the KIS
link (DEVLOG: unattended pty buffers wedge it into an apparent one-way stream).
So the scarce resource is **rig-time**, and every handoff between agents costs a
DebugUSB recovery plus usually an m1n1 reflash. This is a *scheduling* problem,
not a file-isolation problem — worktrees are irrelevant to it.

All the offline work (static disasm, DT authoring, patch writing, kbuild, log
analysis, write-ups) parallelizes freely and needs no coordination beyond git.
Only the **live rig** is exclusive. Coordinate that, and only that.

## The mechanism

`scripts/rig-lease.sh` — a **lease** (not a lock): time-bounded, reclaimable if
a holder dies or wedges the cable. State lives in `.rig/` (gitignored, shared
between the agents via the local filesystem).

`scripts/rig-guard.sh` is the enforcement hook a rig-touching script *can*
source to refuse running unless the caller holds the lease. **It is not yet
wired into the live scripts** (`t6040-boot-dcuart.sh`,
`t6040-debugusb-console.sh`, `t6040-bootcap-fb.sh`) — wiring a fail-closed check
into a shared tool while the other agent is mid-experiment can wreck that run,
so:

- The guard is **fail-open by default**: on a violation it only WARNs and lets
  the script proceed. It REFUSES (exit 5) only under `RIG_ENFORCE=1`.
- **Wire the `source` line into the live scripts only when the rig is idle AND
  both agents reliably acquire the lease before driving.** Until then the lease
  is honor-system, backed by `rig-lease.sh status` before you touch the rig.

Until wired, the discipline is simply: **run `scripts/rig-lease.sh status`
before driving; if it's HELD by the other agent, do offline work.**

```sh
scripts/rig-lease.sh status                          # who holds it, countdown, queue
scripts/rig-lease.sh acquire  <agent> "<task>" [sha] # take the cable (blocks->BUSY if held & live)
scripts/rig-lease.sh renew    <agent>                # extend before a long step
scripts/rig-lease.sh release  <agent> --state healthy|wedged
scripts/rig-lease.sh recovered <agent>               # clear NEEDS_RECOVERY after a recovery boot

scripts/rig-lease.sh queue add     <agent> <slug> "<desc>" [sha]   # propose an experiment
scripts/rig-lease.sh queue approve <seq> [--by <name>]             # MAINTAINER marks it ready
scripts/rig-lease.sh queue next                                     # lowest approved == the schedule
scripts/rig-lease.sh queue list
scripts/rig-lease.sh queue done    <seq>
```

To actually drive the rig, hold the lease and export your name so the guard
sees it:

```sh
scripts/rig-lease.sh acquire claude "pcie op-115 isolation" b5ced9ba
RIG_AGENT=claude bash scripts/t6040-debugusb-console.sh reboot
RIG_AGENT=claude bash scripts/t6040-boot-dcuart.sh
# ... run the approved experiment, record the result (commit + done/ write-up) ...
scripts/rig-lease.sh release claude --state healthy
```

## The two hard invariants

1. **Never two drivers.** Only the lease holder runs a rig script. The guard
   enforces it; do not use `RIG_BYPASS=1` except for genuine manual recovery.
2. **Leave the rig as you'd want to find it.** Release `--state healthy` only
   after the proxy is back to a quiescent `Running proxy` (the DEVLOG
   handoff bar). If the link is wedged or you're unsure, release `--state
   wedged` — that sets `NEEDS_RECOVERY`, and the next acquirer must run a
   recovery boot before trusting the link. Handing off a wedged cable silently
   is the one unforgivable move.

## Turn-taking rules (why timing matters)

- **Only acquire the rig for work that is already APPROVED + hashed.** Approval
  (`queue approve`) happens offline, ahead of rig time. **Never hold the lease
  while waiting on the maintainer to approve the next step** — that starves the
  other agent for as long as CJ is away from the keyboard (priority inversion).
- **The approved queue IS the schedule.** The order CJ approves entries is the
  turn order. Each agent's offline job is to keep that queue full of reviewed,
  hashed, ready-to-boot manifests.
- **Batch by holder; don't ping-pong.** Because each handoff costs a recovery +
  reflash, whoever holds the rig drains the approved entries that share its
  m1n1 SHA back-to-back, then releases. Fine-grained fairness is the worst
  policy; fairness comes from CJ approving both agents' work into one queue.
- **Auto-acquire is on, either agent may drive.** When the lease is free and
  `queue next` returns approved work, an agent may take the rig on its own. The
  approval gate still bounds every live boot.
- **The idle agent does not spin.** It works its offline track and checks
  `rig-lease.sh status` on a coarse, boot-cycle cadence (minutes, not seconds).

## Experiment lifecycle (shared vocabulary)

```
proposed → approved → [acquire] → recovery-if-needed → boot → run →
           verify-rig-healthy → record(commit + done/) → queue done → release
```
Only `acquire … release` is exclusive. Everything left of `acquire`
(build, hash, cross-review) and the write-up afterward is offline.

## Cross-agent review before approval (high value here)

A wrong MMIO offset raises an async SError that kills m1n1. Before a live-image
manifest is proposed for approval, the **other** agent reviews it against the
non-negotiables in `~/Code/m1n1/AGENTS.md`: no SPMI/PMU/NVRAM writes, no blind
MMIO, addresses ADT-derived (never swept), hashes pinned, and the intentional
stop lands before the first dangerous write. Two independent models checking
each other catch the mistake a single invested author talks itself past. Note
the reviewing agent in the queue entry's `desc`. CJ approves last.

## Roles

| Who | Owns |
|---|---|
| `claude` | (fill in — e.g. PCIe op-115 + DockChannel UART IRQ) |
| `sol` | (fill in — e.g. NVMe SPTM / queue ownership) |
| maintainer (CJ) | approves queue entries; arbitrates cross-track merges; posts externally |

One agent must own the `m1n1` ↔ `m1n1-clean` sync (per AGENTS.md) so the
curated series can't diverge. Assign it above.

## What is NOT in `.rig/`

Durable records are unchanged: the commit log (`prepare X` → `record X`),
`DEVLOG.md`, `NEXT_STEPS.md`, and `done/` write-ups. `.rig/` is only the live
turn-taking board; treat it as ephemeral.
```
