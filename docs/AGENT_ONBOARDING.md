# Agent onboarding: joining the shared rig

You're a new agent joining work on this repo (mainline Linux on the M4 Pro).
Others are already here — currently `claude` and `sol`; check the roles table in
[COORDINATION.md](COORDINATION.md) and recent `git log` for who's active. Almost
everything parallelizes fine. The one thing that does **not** is the physical
rig, and this note is how to take turns on it. Full protocol: COORDINATION.md.

## 0. Pick your handle and set your identity

Choose a short, unique lower-case handle for yourself (your model name is fine,
e.g. `gemini`, `grok`, `qwen`) — distinct from any handle already in use. Use it
everywhere below as `<you>`. Export it in the shell you drive the rig from, and,
because the other agents are already onboarded, run in strict mode:

```sh
export RIG_AGENT=<you>      # who the guard thinks you are
export RIG_ENFORCE=1        # make "you forgot to acquire" fatal, not just a warning
```

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

## 4. The schedule = the approved queue

The rig only ever runs *approved, hashed* experiments. Propose yours; CJ (the
maintainer) approves; then whoever's free runs the next approved one:

```sh
scripts/rig-lease.sh queue add <you> <slug> "what it does + key address" <sha>
scripts/rig-lease.sh queue next     # lowest approved entry — that's the turn order
scripts/rig-lease.sh queue done <seq> # after you've run + recorded it
```

Do **not** hold the lease while waiting for CJ to approve the next step — that
starves the other agents for as long as CJ is away. Approval happens offline,
ahead of rig time; you acquire only when there's already-approved work to run.

Auto-acquire is on and any agent may drive: when the lease is free and
`queue next` returns approved work, take it. When idle, don't spin — do your
offline track and re-check `status` on a boot-cycle cadence (minutes).

## 5. How the guard treats you

`scripts/rig-guard.sh` is sourced by the three rig scripts. What it does:

- If **another agent holds a live lease**, the rig scripts **refuse to run**
  (exit 5) — this stops you from corrupting the link. Wait, or check
  `scripts/rig-lease.sh status`. (`RIG_BYPASS=1` overrides, for manual recovery
  only.) This block is unconditional; it does not depend on `RIG_ENFORCE`.
- If the **rig is idle**, the scripts run even if you forgot to acquire — with
  `RIG_ENFORCE=1` (which you set in §0) that omission is fatal instead; without
  it you'd only get a warning. Either way the guard never breaks a solo run on
  an idle rig — it only blocks a real collision.

Transition caveat: **`status` only reflects an agent that actually took a
lease.** If someone drives without acquiring, `status` still says FREE — so
until every agent acquires every time, keep coordinating out-of-band too.

## 6. Before a live image goes to CJ for approval

A wrong MMIO offset raises an async SError that kills m1n1. So before proposing
a live image, another already-onboarded agent reviews it against the
non-negotiables in `~/Code/m1n1/AGENTS.md` (no SPMI/PMU/NVRAM writes, no blind
MMIO, ADT-derived addresses only, hashes pinned, intentional stop before the
first dangerous write) — and you do the same for theirs. Note the reviewer in
the queue entry. CJ approves last.
