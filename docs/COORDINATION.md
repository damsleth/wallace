# Coordination: two agents, one rig

Current as of 2026-08-03. `claude` and `sol` share one Git worktree and one
physical M4 Pro. CJ is the approval gate and tie-breaker.

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

`queue add` allocates sequence numbers non-atomically. After every add,
immediately verify that the reported sequence still contains the expected
slug. Re-add or re-sequence if another concurrent add won the race.

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

The lease in `.rig/` is ephemeral. Tickets, commits, `done/`, and the
current-facing docs are the durable record.
