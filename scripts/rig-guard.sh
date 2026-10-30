#!/usr/bin/env bash
# rig-guard.sh — sourced by every rig-touching script so the lease is binding,
# not honor-system: two agents can never drive the one physical cable at once.
#
# SAFETY MODEL — block real collisions and hold identified agents to
# acquire-first, without ever blocking a human's manual run on an idle rig.
#   * If a LIVE lease is held by someone OTHER than you, REFUSE (exit 5) —
#     always, regardless of RIG_ENFORCE. This is the only situation that
#     actually corrupts the KIS link, so it is unconditionally fatal.
#     RIG_BYPASS=1 still overrides it, for genuine manual recovery.
#   * If you are an IDENTIFIED agent (RIG_AGENT set) driving without a live
#     lease of your own, REFUSE under enforcement (the default). This is what
#     makes acquire-first mandatory and keeps `status` trustworthy.
#   * If RIG_AGENT is UNSET (a human running by hand), stay lenient: WARN and
#     proceed on an idle rig. A manual run is never blocked by enforcement;
#     only the collision case above stops it.
#
# Enforcement is ON by default (RIG_ENFORCE defaults to 1). Set RIG_ENFORCE=0
# to relax the acquire-first nudges back to warnings.
#
# Contract (set BEFORE `source`-ing this):
#   RIG_AGENT              who you are ("claude", "sol"); unset = manual/human.
#   RIG_ENFORCE=0          relax: acquire-first nudges warn instead of refusing.
#   RIG_ALLOW_RECOVERY=1   set by the recovery-boot script; lets it run while
#                          NEEDS_RECOVERY is set (fixing the link is its job).
#   RIG_BYPASS=1           escape hatch; skips the check entirely (loud).
_rig_guard() {
  local root="${RIG_ROOT:-$HOME/code/wallace/.rig}"
  local lease="$root/lease.env" flag="$root/NEEDS_RECOVERY" self="${RIG_AGENT:-}"
  local strict="${RIG_ENFORCE:-1}"
  if [ "${RIG_BYPASS:-0}" = 1 ]; then
    echo "rig-guard: BYPASS set — skipping lease check." >&2; return 0
  fi

  # Effective current holder: empty if no lease or the lease has expired.
  local holder="" e=""
  if [ -f "$lease" ]; then
    holder="$(sed -n 's/^HOLDER=//p' "$lease" | head -1)"
    e="$(sed -n 's/^EXPIRY=//p' "$lease" | head -1)"
    if [ -z "$e" ] || [ "$(date +%s)" -ge "$e" ]; then holder=""; fi   # expired → gone
  fi

  # THE TEETH: a live lease held by someone else is a collision. Always fatal.
  if [ -n "$holder" ] && [ "$holder" != "$self" ]; then
    echo "rig-guard: REFUSE — rig is HELD by '$holder', you are '${self:-anonymous}'. Driving now would corrupt the KIS link. Wait for release, or 'scripts/rig-lease.sh status'. (RIG_BYPASS=1 overrides, for manual recovery only.)" >&2
    exit 5
  fi

  # deny(reason): fatal under enforcement; otherwise warn and proceed.
  _deny() {
    if [ "$strict" = 1 ]; then echo "rig-guard: REFUSE — $1" >&2; exit 5
    else echo "rig-guard: WARN — $1 (proceeding; RIG_ENFORCE=1 makes this fatal)" >&2; fi
  }

  if [ -z "$self" ]; then
    # Unidentified = a human by hand. Never block on an idle rig (the collision
    # case above already handled a live other-holder). Just note it.
    echo "rig-guard: note — no RIG_AGENT set; treating as a manual run. Agents must set RIG_AGENT and acquire a lease." >&2
    return 0
  fi
  if [ "$holder" != "$self" ]; then
    # rig is free but you didn't acquire (or your own lease expired)
    _deny "rig is free but you don't hold a live lease; acquire it first: scripts/rig-lease.sh acquire $self \"<task>\" [sha]"; return 0
  fi
  if [ -f "$flag" ] && [ "${RIG_ALLOW_RECOVERY:-0}" != 1 ]; then
    _deny "NEEDS_RECOVERY set (link untrusted); run a recovery boot first, then: scripts/rig-lease.sh recovered $self"; return 0
  fi
  echo "rig-guard: ok — '$self' holds the rig ($(( e - $(date +%s) ))s left)." >&2
}
_rig_guard
