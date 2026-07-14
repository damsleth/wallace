#!/usr/bin/env bash
# rig-guard.sh — sourced by every rig-touching script. Refuses to proceed
# unless the caller currently HOLDS the rig lease. This is what makes the
# lease binding rather than advisory: two agents can never drive the one
# physical cable at once.
#
# SAFETY MODEL — fail OPEN by default.
# This file is meant to be sourced by shared hardware scripts. Those scripts may
# be invoked by an agent that has NOT adopted the lease (e.g. mid-migration, or
# a human running by hand). A guard that BLOCKED such a run could wreck an
# in-flight experiment or wedge the cable. So by default the guard only WARNS on
# a violation and lets the script proceed. It REFUSES (exit 5) only when the
# caller has explicitly opted into strict mode with RIG_ENFORCE=1 — flip that on
# only once BOTH agents reliably acquire the lease before driving, and only wire
# the source line into the live scripts while the rig is idle.
#
# Contract for the sourcing script (set BEFORE `source`-ing this):
#   RIG_AGENT              who you are ("claude", "sol", "maintainer").
#   RIG_ENFORCE=1          strict: a violation exits 5 instead of just warning.
#   RIG_ALLOW_RECOVERY=1   set by the recovery-boot script; lets it run while
#                          NEEDS_RECOVERY is set (fixing the link is its job).
#   RIG_BYPASS=1           escape hatch; skips the check entirely (loud).
_rig_guard() {
  local root="${RIG_ROOT:-$HOME/Code/wallace/.rig}"
  local lease="$root/lease.env" flag="$root/NEEDS_RECOVERY" self="${RIG_AGENT:-}"
  local strict="${RIG_ENFORCE:-0}"
  if [ "${RIG_BYPASS:-0}" = 1 ]; then
    echo "rig-guard: BYPASS set — skipping lease check." >&2; return 0
  fi
  # deny(reason): refuse in strict mode, else warn and proceed (fail open).
  _deny() {
    if [ "$strict" = 1 ]; then echo "rig-guard: REFUSE — $1" >&2; exit 5
    else echo "rig-guard: WARN — $1 (proceeding; set RIG_ENFORCE=1 to make this fatal)" >&2; fi
  }
  [ -n "$self" ] || { _deny "RIG_AGENT unset; acquire first: scripts/rig-lease.sh acquire <agent> \"<task>\" [sha]"; return 0; }
  [ -f "$lease" ] || { _deny "rig lease is FREE; acquire it first: scripts/rig-lease.sh acquire $self \"<task>\" [sha]"; return 0; }
  local h e; h="$(sed -n 's/^HOLDER=//p' "$lease" | head -1)"; e="$(sed -n 's/^EXPIRY=//p' "$lease" | head -1)"
  [ "$h" = "$self" ] || { _deny "lease held by '$h', not '$self' — two agents must never drive the rig at once"; return 0; }
  { [ -n "$e" ] && [ "$(date +%s)" -lt "$e" ]; } || { _deny "your lease expired; renew: scripts/rig-lease.sh renew $self"; return 0; }
  if [ -f "$flag" ] && [ "${RIG_ALLOW_RECOVERY:-0}" != 1 ]; then
    _deny "NEEDS_RECOVERY set (link untrusted); run a recovery boot first, then: scripts/rig-lease.sh recovered $self"; return 0
  fi
  echo "rig-guard: ok — '$self' holds the rig ($(( e - $(date +%s) ))s left)." >&2
}
_rig_guard
