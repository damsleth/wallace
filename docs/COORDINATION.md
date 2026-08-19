# Coordination: multiple agents, one rig

Current as of 2026-08-19. Several autonomous sessions — `claude`, `sol`,
`fable`, and `opus` — share one Git worktree and one physical M4 Pro. CJ is the
approval gate and tie-breaker.

## Rig arbitration: normal lease (the 230 serialization is over)

Ticket 230 (`trackpad-v2-power-request-live`) **landed 2026-08-19** (finger test
PASSED — touch + haptic click), so the temporary serialization for it is
retired. The rig is back to **normal lease arbitration**: acquire
`scripts/rig-lease.sh` for an approved, ready ticket; hold it only for the run;
release healthy (or wedged). No session is barred from the rig.

## Distinct lease handles are mandatory (CJ, 2026-08-19)

Each concurrent session **must** hold the lease under its own handle. On
2026-08-19 two sessions both ran as `fable`, and `rig-lease.sh acquire fable`
on a lease already held by `fable` did not refuse — it silently **renewed and
relabelled** it, clobbering the other session's active-run task record. The
per-agent guard only serializes agents whose handles differ. Current handles:
`claude`, `sol`, `fable`, `opus` (this last renamed from `fable` on 2026-08-19
because the session runs on the Opus model). Never `acquire` under a handle
another live session is using; set `RIG_AGENT` to your own handle.

## Ticket numbering

**Each agent allocates inside its own 1000-wide block** (CJ, 2026-08-19,
replacing the earlier odd/even split after it kept colliding). Blocks:

| agent | block | sequence numbers |
|---|---|---|
| **fable** | 1000+ | 1000, 1001, 1002, … |
| **opus** | 2000+ | 2000, 2001, 2002, … |
| **sol** | 3000+ | 3000, 3001, 3002, … |
| **terra** | 4000+ | 4000, 4001, 4002, … |
| **claude** | 5000+ | 5000, 5001, 5002, … |

Because two agents in different blocks can never land on the same number, this
removes the collision class the odd/even scheme kept hitting.

Rules:

- **`queue add` allocates for you, inside your block.** It reads the caller
  (`<agent>`, first argument) and picks the next free number in that agent's
  block — you do not choose the number. An agent name not in the table above
  falls back to the legacy global `max+1`; use one of the names above.
- **Sub-1000 numbers are the frozen legacy space.** Every existing ticket keeps
  its number. Never renumber another agent's ticket; never hand-pick a new
  sub-1000 number.
- Reference other agents' tickets freely; the block is an allocation rule, not
  ownership of the work.
- Same-agent concurrent adds can still race (two `fable` sessions both computing
  the same next-in-block). After every add, verify the reported sequence still
  contains your slug, and re-add if a concurrent add won the race. Distinct
  agents cannot collide.
- If you must move a ticket to another number (e.g. resolving a legacy
  collision), record the reason in the ticket's `ticket_correction` field, as
  in the 229→307 wifi-ticket renumber.

## Scope of the lease

Only physical-rig access is exclusive. Static analysis, documentation, builds,
patches, and transcript review are offline work and do not require the lease.

The guarded rig scripts are:

- `scripts/t6040-boot-dcuart.sh`
- `scripts/t6040-debugusb-console.sh`
- `scripts/t6040-bootcap-fb.sh`

Never run one while another agent holds the lease.

## Lease commands

    scripts/rig-lease.sh status
    scripts/rig-lease.sh acquire <agent> "<task>" [m1n1-sha]
    scripts/rig-lease.sh renew <agent>
    scripts/rig-lease.sh release <agent> --state healthy|wedged
    scripts/rig-lease.sh recovered <agent>

Set `RIG_AGENT=<agent>` when driving. The guard refuses an identified agent
without its own live lease and always refuses a live lease held by someone
else. `RIG_BYPASS=1` is for deliberate manual recovery only.

Acquire only for an **approved and ready** rig ticket. Do not hold the lease
while building, reviewing, waiting for approval, or writing results.

Release `healthy` only after the proxy is back at a quiescent
`Running proxy`. Release `wedged` if the link is unhealthy or uncertain;
the next holder must recover it before use.

## Ticket lifecycle

Actionable work is stored as JSON:

- `tickets/`: active;
- `tickets/done/`: completed;
- `tickets/archive/`: superseded, deprecated, deferred, or wontfix.

Commands:

    scripts/rig-lease.sh queue add <agent> <slug> "<desc>" --needs offline|rig [--track T --pri P1 --dep NNN]
    scripts/rig-lease.sh queue approve <seq-or-range> --by cj
    scripts/rig-lease.sh queue ready <seq> --reviewed-by <other-agent>
    scripts/rig-lease.sh queue next --offline
    scripts/rig-lease.sh queue next --rig
    scripts/rig-lease.sh queue show <seq>
    scripts/rig-lease.sh queue list [--offline|--rig]
    scripts/rig-lease.sh queue done <seq>

An offline ticket is actionable in state `open`. A rig ticket is schedulable
only when:

1. CJ approved the plan;
2. exact hashes are pinned;
3. dependencies are in `tickets/done/`;
4. another agent completed the exact-artifact review;
5. `queue ready` recorded `runnable:true`.

Keep `desc` focused on the current objective and pass/fail boundary. Durable
analysis, transcripts, retractions, and detailed results belong in
`evidence/`; new or materially revised tickets should link them through a
top-level `evidence` array. See `tickets/README.md` for the record shape.

Move a ticket to `tickets/done/` when its stated deliverable and evidence are
complete. Move it to `tickets/archive/` when a later path supersedes it, its
premise was disproved, its useful content was folded elsewhere, or it is
deferred pending a named condition. Archived tickets record `archived.at`,
`archived.by`, and a concise reason. Preserve still-useful dependency,
read-only, rollback, and safety contracts.

## Rig session

1. Confirm `queue next --rig` and the exact ticket.
2. Acquire the lease.
3. Recover first if `NEEDS_RECOVERY` is set.
4. Verify the candidate hashes.
5. Batch compatible runs under one holder when possible.
6. Preserve the first transcript before rebooting.
7. Return to a healthy proxy or mark the lease wedged.
8. Record evidence, complete the ticket, and release.

Stop on artifact mismatch, access outside the ticket, SError, DART fault,
firmware panic, unexpected reset, or loss of the planned observation channel.

## Shared worktree

Both agents edit `main` directly. Before changing a file:

- inspect `git status`;
- preserve unrelated dirty paths;
- avoid staging another agent’s work;
- use explicit pathspecs for every commit;
- re-check `HEAD` before committing.

There is no fixed ownership of a technical lane. Tickets may name an owner for
a specific run; otherwise either agent may take offline work. The other agent
still performs exact review for live artifacts.

## Safety review

Before readiness, the reviewer checks the final object against
`~/Code/m1n1/AGENTS.md` and [SPMI_SAFETY.md](SPMI_SAFETY.md):

- no PMU, charger, NVRAM, firmware, or unknown-SPMI write;
- no blind MMIO or address copied from another SoC;
- every permitted address is ADT-derived;
- only the reviewed SMC keys or SPMI endpoint/operation appear;
- hashes, stop conditions, fixture, and recovery are explicit.

## Commits

Use:

    CJ Damsleth <kim@damsleth.no>

Every commit is signed off with `git commit -s`, has no
`Co-Authored-By` trailer, uses a topic prefix, and includes an explicit
pathspec. External posts remain drafts for CJ to send.

The lease in `.rig/` is ephemeral. Tickets, commits, `evidence/`, and the
current-facing docs are the durable record.
