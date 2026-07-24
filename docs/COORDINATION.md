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
a holder dies or wedges the cable. The lease itself lives in `.rig/`
(gitignored, host-local, shared between agents via the filesystem); the same
tool also manages the **ticket store** in `tickets/` (git-tracked JSON — the
durable backlog, see below).

`scripts/rig-guard.sh` is sourced by the three rig-touching scripts
(`t6040-boot-dcuart.sh`, `t6040-debugusb-console.sh`, `t6040-bootcap-fb.sh`) and
enforces the lease. Its semantics are chosen so it protects a holder without
ever false-positiving an idle run:

- **A live lease held by another agent → always REFUSE (exit 5).** This is the
  only case that corrupts the KIS link, so it is unconditional (independent of
  `RIG_ENFORCE`). `RIG_BYPASS=1` overrides it — for genuine manual recovery only.
- **An identified agent (`RIG_AGENT` set) driving without its own live lease →
  REFUSE under enforcement, which is the default.** This makes acquire-first
  mandatory and keeps `status` trustworthy. `RIG_ENFORCE=0` relaxes it to a warn.
- **A manual run with no `RIG_AGENT` (i.e. CJ by hand) → PROCEED on an idle
  rig** (with a note). Enforcement never blocks a human's solo run; only the
  collision case above stops it.

So the discipline is: **`RIG_AGENT=<you> scripts/rig-lease.sh acquire` before
driving.** If you skip it on an idle rig you'll get a warning but proceed; if
the other agent holds the rig you'll be stopped.

```sh
scripts/rig-lease.sh status                          # who holds it, countdown, queue
scripts/rig-lease.sh acquire  <agent> "<task>" [sha] # take the cable (blocks->BUSY if held & live)
scripts/rig-lease.sh renew    <agent>                # extend before a long step
scripts/rig-lease.sh release  <agent> --state healthy|wedged
scripts/rig-lease.sh recovered <agent>               # clear NEEDS_RECOVERY after a recovery boot

# the ticket store — git-tracked JSON in tickets/, offline tasks AND rig experiments:
scripts/rig-lease.sh queue add <agent> <slug> "<desc>" --needs offline|rig [--track T --pri P1 --dep NNN]
scripts/rig-lease.sh queue approve 001-006 --by cj   # MAINTAINER plan approval; runnable stays false
scripts/rig-lease.sh queue ready 001 --reviewed-by sol # after exact review + completed deps
scripts/rig-lease.sh queue next --rig                # next approved+runnable rig experiment
scripts/rig-lease.sh queue next --offline            # next open offline task (no approval needed)
scripts/rig-lease.sh queue list [--rig|--offline]
scripts/rig-lease.sh queue show <seq>                # full JSON
scripts/rig-lease.sh queue done <seq>
```

Two ticket kinds. `needs: offline` (state `open`) — no rig, no approval, any
agent grabs and does it; this is the bulk of the backlog and where parallel
speed comes from. `needs: rig` (state `proposed`→`approved`→`done`) needs the
lease and CJ's batch plan approval. An approved ticket is schedulable only
after `queue ready` records the independent exact-artifact review, verifies
pinned hashes, and finds every dependency in `tickets/done/`. Tickets live in
git (`tickets/`); the strategy/priorities/graves map is `BACKLOG.md`.

**Concurrent-add race:** `queue add` allocates the next sequence number
non-atomically — two agents adding at the same time can silently clobber one
another (observed 2026-07-21: an add reported `[057]` and was later overwritten
by the other agent's 057). After every `queue add`, re-check
`queue show <seq>` actually contains *your* slug; if not, re-add.

To actually drive the rig, hold the lease and export your name so the guard
sees it:

```sh
scripts/rig-lease.sh acquire claude "pcie op-115 isolation" 85b01036
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

- **Only acquire the rig for work that is APPROVED + READY.** Plan approval
  (`queue approve`) and exact review (`queue ready`) happen offline, ahead of
  rig time. **Never hold the lease
  while waiting on the maintainer to approve the next step** — that starves the
  other agent for as long as CJ is away from the keyboard (priority inversion).
- **The approved+ready queue IS the schedule.** `queue next --rig` skips
  approved plans whose review is incomplete or whose dependencies remain
  open. Each agent's offline job is to turn approved plans into reviewed,
  hashed, ready-to-boot manifests.
- **Batch by holder; don't ping-pong.** Because each handoff costs a recovery +
  reflash, whoever holds the rig drains the approved entries that share its
  m1n1 SHA back-to-back, then releases. Fine-grained fairness is the worst
  policy; fairness comes from CJ approving both agents' work into one queue.
- **Auto-acquire is on, either agent may drive.** When the lease is free and
  `queue next` returns approved+ready work, an agent may take the rig on its
  own. The approval and review gates still bound every live boot.
- **The idle agent does not spin.** It works its offline track and checks
  `rig-lease.sh status` on a coarse, boot-cycle cadence (minutes, not seconds).

## Experiment lifecycle (shared vocabulary)

```
proposed → plan-approved → exact review/ready → [acquire] →
           recovery-if-needed → boot → run →
           verify-rig-healthy → record(commit + done/) → queue done → release
```
Only `acquire … release` is exclusive. Everything left of `acquire`
(build, hash, cross-review) and the write-up afterward is offline.

## Cross-agent exact review before readiness (high value here)

A wrong MMIO offset raises an async SError that kills m1n1. Before a live-image
manifest is marked runnable, the **other** agent reviews it against the
non-negotiables in `~/Code/m1n1/AGENTS.md`: no
PMU/charger/NVRAM/firmware or unknown-SPMI writes; any eligible non-PMU SPMI
transaction matches `docs/SPMI_SAFETY.md` exactly; no blind MMIO; addresses
are ADT-derived (never swept); hashes are pinned; and the intentional stop
lands before the next operation class. Two independent models checking each
other catch the mistake a single invested author talks itself past. Note the
reviewing agent through `queue ready --reviewed-by`. CJ may approve the plan
before that review; approval alone never schedules it.

## Roles

Primary focus, **not exclusive ownership** — so that if one agent runs out of
tokens or goes away, the other can pick up its track without waiting on anyone.

| Who | Primary focus |
|---|---|
| `claude` | PCIe op-115 + DockChannel UART IRQ |
| `sol` | NVMe SPTM / queue ownership |
| maintainer (CJ) | approves queue entries; arbitrates; posts externally |

**`m1n1` ↔ `m1n1-clean` sync has no fixed owner.** Whoever last changed `m1n1`
`src/` mirrors it into the curated `m1n1-clean` `t6040-bringup` series in the
same session. A fixed owner would deadlock everyone else the moment that agent
disappears mid-work — the same reason the rig uses a reclaimable lease, not a
lock. The cost is that two agents touching `src/` close together must
reconcile; keep such edits announced in the queue `desc` or a commit note.

## Committing

Linear history on `main`, no per-agent attribution. Every commit is authored
and signed off as the maintainer — `git commit -s`, `Signed-off-by: CJ Damsleth
<kim@damsleth.no>`, **no `Co-Authored-By` trailer** (keeps the m1n1/kernel
series upstream-clean). Use the existing topic-prefix style (`dockchannel:`,
`pcie:`, `docs:`, `rig:`) and the `prepare X` → `record X` two-phase pattern;
who did what is read from the commit content, not a trailer.

## Enforcement

`RIG_ENFORCE` defaults to **on**: an identified agent (one that set `RIG_AGENT`)
that drives without a live lease is refused, not just warned. A manual run with
no `RIG_AGENT` set (i.e. CJ by hand) stays lenient on an idle rig. The
collision block — refusing when another agent holds a live lease — is
unconditional regardless. Set `RIG_ENFORCE=0` only to deliberately relax this.

## Durable vs ephemeral

Durable, git-tracked: `tickets/` (the backlog), `BACKLOG.md`/`ROADMAP.md`
(strategy), the commit log (`prepare X` → `record X`), `DEVLOG.md`,
`NEXT_STEPS.md`, and `done/` write-ups. Ephemeral, gitignored, host-local:
`.rig/` — just the lease (the mutex) and its audit log. Treat `.rig/` as
throwaway; treat everything else as the record.
