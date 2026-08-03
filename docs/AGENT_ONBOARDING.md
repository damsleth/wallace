# Agent onboarding

Read [COORDINATION.md](COORDINATION.md) and
`~/Code/m1n1/AGENTS.md` before doing any work.

## Identity

Choose a unique lower-case rig handle and export it when driving:

    export RIG_AGENT=<handle>

Commits use `CJ Damsleth <kim@damsleth.no>`, `git commit -s`, no
`Co-Authored-By`, and an explicit pathspec.

## Before editing

    git status --short
    git log -5 --oneline

This is a shared worktree. Preserve unrelated dirty files and stage only your
paths.

## Offline work

Offline analysis, builds, patches, documentation, and transcript review need
no lease:

    scripts/rig-lease.sh queue next --offline

New tickets must be added through the queue tool. Immediately verify the
reported sequence because concurrent adds can collide:

    scripts/rig-lease.sh queue add <handle> <slug> "<desc>" --needs offline
    scripts/rig-lease.sh queue show <seq>

## Rig work

A rig run requires an approved, dependency-complete, hash-pinned ticket that
another agent marked ready.

    scripts/rig-lease.sh queue next --rig
    scripts/rig-lease.sh status
    scripts/rig-lease.sh acquire <handle> "<ticket and task>" <m1n1-sha>

Only the lease holder may run a rig script. Release promptly:

    scripts/rig-lease.sh release <handle> --state healthy

Use `--state wedged` if the proxy is not back at a quiescent
`Running proxy`. Never leave uncertain rig state for the next agent.

## Exact review

Before `queue ready`, independently verify:

- final hashes and source commits;
- ADT-derived addresses;
- no blind MMIO;
- no prohibited PMU, charger, NVRAM, firmware, SMC, or SPMI operation;
- explicit pass, stop, fixture, and recovery conditions.

The complete hardware policy is in `~/Code/m1n1/AGENTS.md`; the only current
SPMI exception is defined in [SPMI_SAFETY.md](SPMI_SAFETY.md).
