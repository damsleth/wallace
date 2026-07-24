# Agent onboarding: joining the shared rig

You're a new agent joining work on this repo (mainline Linux on the M4 Pro).
Others are already here — currently `claude` and `sol`; check the roles table in
[COORDINATION.md](COORDINATION.md) and recent `git log` for who's active. Almost
everything parallelizes fine. The one thing that does **not** is the physical
rig, and this note is how to take turns on it. Full protocol: COORDINATION.md.

## 0. Pick your handle and set your identity

Choose a short, unique lower-case handle for yourself (your model name is fine,
e.g. `gemini`, `grok`, `qwen`) — distinct from any handle already in use. Use it
everywhere below as `<you>`, and export it in the shell you drive the rig from:

```sh
export RIG_AGENT=<you>      # who the guard thinks you are
```

Enforcement is on by default: once you've set `RIG_AGENT`, the rig scripts will
**refuse** to run unless you hold a live lease (so you can't forget to acquire).
Don't set `RIG_ENFORCE=0` — that's the relax switch, for CJ's manual use only.

Commits here always go out under the maintainer's identity — `git commit -s`
with `Signed-off-by: CJ Damsleth <kim@damsleth.no>`, and **no** `Co-Authored-By`
trailer. Never commit under your own name.

## 1. The one rule

There is exactly one rig: the M4, one DebugUSB cable, one m1n1 proxy, one
`/tmp/m1n1` pty. **Two agents touching it at once corrupts the KIS link**
(unattended pty buffers wedge it into an apparent one-way stream; recovery costs
a reboot). So before you run *any* rig-touching script — `t6040-boot-dcuart.sh`,
`t6040-debugusb-console.sh`, `t6040-bootcap-fb.sh` — you take a **lease**, and
you release it when done.

The lease tool is `scripts/rig-lease.sh`. State lives in `.rig/` (gitignored,
shared between all agents on this host's filesystem).

## 2. Wrap every rig session in a lease

```sh
cd ~/Code/wallace

# a. Is it free?  (see the caveat in §5)
scripts/rig-lease.sh status

# b. Take it — your handle, the task, and the m1n1 SHA you're testing.
scripts/rig-lease.sh acquire <you> "short task description" <m1n1-sha>

# c. Drive the rig as usual (recovery boot, chainload, run the experiment)…
bash scripts/t6040-debugusb-console.sh reboot
bash scripts/t6040-boot-dcuart.sh
#    …for a long step, extend your lease so it can't be reclaimed under you:
scripts/rig-lease.sh renew <you>

# d. Record the result the usual way (commit + a done/ write-up).

# e. Hand the rig back. Say whether the link is healthy or wedged:
scripts/rig-lease.sh release <you> --state healthy
#    If the link is wedged or you're unsure:
scripts/rig-lease.sh release <you> --state wedged
```

`acquire` succeeds if the rig is free (or already yours). If another agent holds
it, `acquire` prints who/what and exits **3 (BUSY)** — don't touch the rig; do
offline work and try later.

## 3. Two hard invariants

1. **Never drive unless you hold the lease.** If `status` shows it HELD by
   another agent, stay off the cable.
2. **Leave it as you'd want to find it.** Release `--state healthy` only after
   the proxy is back to a quiescent `Running proxy`. Otherwise release `--state
   wedged` — that sets a `NEEDS_RECOVERY` flag, and the next acquirer (maybe you)
   must run a recovery boot before trusting the link, then clear it:
   `scripts/rig-lease.sh recovered <you>`. Silently handing off a wedged cable is
   the one unforgivable move.

## 4. The backlog: one ticket store, offline + rig

All actionable work is tickets in `tickets/` (git-tracked JSON), managed through
the CLI. Two kinds:

```sh
# OFFLINE work — no rig, no approval. This is most of the backlog; favour it.
scripts/rig-lease.sh queue next --offline            # next open offline task — just grab it
scripts/rig-lease.sh queue add <you> <slug> "<desc>" --needs offline --track T --pri P1

# RIG experiments — need the lease + CJ approval.
scripts/rig-lease.sh queue add <you> <slug> "<desc>" --needs rig --pri P1 [--dep NNN]
scripts/rig-lease.sh queue next --rig                # next APPROVED rig experiment == the turn order
scripts/rig-lease.sh queue done <seq>                # after you've run + recorded it
```

The rig only ever runs *approved, hashed* experiments. Propose yours; CJ
batch-approves (`queue approve 001-006 --by cj`); whoever's free runs the next
approved one. Do **not** hold the lease while waiting for CJ to approve the next
step — that starves the other agents while CJ is away. Approval happens offline,
ahead of rig time.

When the rig is busy or you're between experiments, **pull an offline ticket** —
that's the point of the unified store, and it never needs the lease. Auto-acquire
is on: when the lease is free and `queue next --rig` returns approved work, take
it. When idle, don't spin — grab offline work and re-check `status` on a
boot-cycle cadence (minutes).

## 5. How the guard treats you

`scripts/rig-guard.sh` is sourced by the three rig scripts. What it does:

- If **another agent holds a live lease**, the rig scripts **refuse to run**
  (exit 5) — this stops you from corrupting the link. Wait, or check
  `scripts/rig-lease.sh status`. (`RIG_BYPASS=1` overrides, for manual recovery
  only.) This block is unconditional; it does not depend on `RIG_ENFORCE`.
- If the **rig is idle** but you (an identified agent, `RIG_AGENT` set) haven't
  acquired, the scripts **refuse** — enforcement is on by default, so you can't
  forget to take the lease. A manual run with no `RIG_AGENT` (CJ by hand) is the
  only thing that proceeds on an idle rig without a lease.

Because enforcement makes every agent acquire before driving, `status` is a
trustworthy picture of who holds the rig — provided nobody sets `RIG_ENFORCE=0`.

## 6. Before a live image goes to CJ for approval

A wrong MMIO offset raises an async SError that kills m1n1. So before proposing
a live image, another already-onboarded agent reviews it against the
non-negotiables in `~/Code/m1n1/AGENTS.md`: no PMU/charger/NVRAM/firmware or
unknown-SPMI writes, exact compliance with `docs/SPMI_SAFETY.md` for any
allowlisted non-PMU SPMI transaction, no blind MMIO, ADT-derived addresses
only, hashes pinned, and an intentional stop before the next operation class.
You do the same for theirs. Note the reviewer in the queue entry. CJ approves
last.
