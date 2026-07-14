#!/usr/bin/env bash
# rig-lease.sh — turn-taking for the ONE physical t6040 rig.
#
# The rig (M4 + single DebugUSB cable + /tmp/m1n1 pty) is a hard singleton:
# two agents driving it at once corrupts the KIS link (see DEVLOG). This is a
# *lease*, not a lock — it is time-bounded with an expiry, so a holder that
# dies or wedges the cable can be reclaimed instead of deadlocking the other
# agent forever. Release carries a rig-health assertion; a wedged handoff sets
# a NEEDS_RECOVERY flag the next acquirer must clear via a recovery boot first.
#
# The scheduling model (see COORDINATION.md):
#   - Agents only ever hold the rig for work already APPROVED + hashed by the
#     maintainer. Approval happens offline; never hold the cable across a human
#     round-trip. The approved queue IS the schedule.
#   - Whoever holds drains its approved batch (grouped by m1n1 SHA to avoid
#     needless reflashes), verifies the rig healthy, then releases.
#
# Usage:
#   rig-lease.sh acquire  <agent> "<task>" [m1n1-sha]   # take the cable
#   rig-lease.sh renew    <agent>                        # extend heartbeat/expiry
#   rig-lease.sh release  <agent> --state healthy|wedged # hand back
#   rig-lease.sh status                                  # who holds it, countdown
#   rig-lease.sh recovered <agent>                       # clear NEEDS_RECOVERY
#   rig-lease.sh queue add     <agent> <slug> "<desc>" [sha]
#   rig-lease.sh queue approve <seq> [--by <name>]       # maintainer marks ready
#   rig-lease.sh queue next                              # lowest approved (schedule)
#   rig-lease.sh queue list
#   rig-lease.sh queue done    <seq>
#
# Exit codes: 0 ok · 2 usage · 3 BUSY (held by a live other holder) · 4 not holder
set -euo pipefail

RIG_ROOT="${RIG_ROOT:-$HOME/Code/wallace/.rig}"
LEASE_ENV="$RIG_ROOT/lease.env"      # a COMPLETE file; its atomic creation == the mutex
QUEUE_DIR="$RIG_ROOT/queue"
DONE_DIR="$RIG_ROOT/done"
AUDIT_LOG="$RIG_ROOT/log"
RECOVERY_FLAG="$RIG_ROOT/NEEDS_RECOVERY"
TTL="${RIG_LEASE_TTL:-1800}"         # seconds; generous vs a boot cycle (~5-10m)

now() { date +%s; }
mkdirs() { mkdir -p "$RIG_ROOT" "$QUEUE_DIR" "$DONE_DIR"; }
audit() { mkdirs; printf '%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$AUDIT_LOG"; }
# read one KEY from a key=value file (values may contain spaces)
getk() { [ -f "$1" ] && sed -n "s/^$2=//p" "$1" | head -1 || true; }
die() { echo "rig-lease: $1" >&2; exit "${2:-2}"; }

# Build a complete lease into a private temp file; print its path. The caller
# makes it visible atomically (ln to claim a free lease, or mv -f to renew our
# own). A partially-written lease is never visible under $LEASE_ENV.
build_lease() { # agent task sha -> echoes tmp path
  local t n; n="$(now)"; t="$RIG_ROOT/.lease.$$.${RANDOM}"
  {
    echo "HOLDER=$1"
    echo "TASK=$2"
    echo "SHA=${3:-}"
    echo "HOST=$(hostname -s 2>/dev/null || echo unknown)"
    echo "ACQUIRED=$n"
    echo "HEARTBEAT=$n"
    echo "EXPIRY=$(( n + TTL ))"
    echo "TTL=$TTL"
  } >"$t"
  echo "$t"
}

human_left() { local exp="$1" n; n=$(now); [ "$exp" -gt "$n" ] && echo "$(( exp - n ))s" || echo "EXPIRED"; }

cmd_acquire() {
  local agent="${1:-}" task="${2:-}" sha="${3:-}"
  [ -n "$agent" ] && [ -n "$task" ] || die "acquire needs <agent> \"<task>\" [sha]"
  mkdirs
  local tmp; tmp="$(build_lease "$agent" "$task" "$sha")"
  while :; do
    # Claim a FREE lease: hard-link is atomic and fails if $LEASE_ENV exists.
    if ln "$tmp" "$LEASE_ENV" 2>/dev/null; then
      rm -f "$tmp"
      audit "ACQUIRE agent=$agent task=$task sha=$sha"
      echo "rig: ACQUIRED by $agent (expires in ${TTL}s). task: $task"
      [ -f "$RECOVERY_FLAG" ] && echo "rig: !! NEEDS_RECOVERY set — run a recovery boot (t6040-debugusb-console.sh reboot) before trusting the link; then 'rig-lease.sh recovered $agent'."
      return 0
    fi
    # Held (and always fully-formed): inspect the current holder.
    local h e; h="$(getk "$LEASE_ENV" HOLDER)"; e="$(getk "$LEASE_ENV" EXPIRY)"
    if [ "$h" = "$agent" ]; then
      mv -f "$tmp" "$LEASE_ENV"             # idempotent re-acquire == atomic renew
      audit "REACQUIRE agent=$agent task=$task"
      echo "rig: already held by $agent — renewed."
      return 0
    fi
    if [ -n "$e" ] && [ "$(now)" -lt "$e" ]; then
      rm -f "$tmp"
      echo "rig: BUSY — held by ${h:-?} ($(getk "$LEASE_ENV" TASK)); expires in $(human_left "$e")." >&2
      exit 3
    fi
    # Stale (expired holder). Atomically grab it via rename; one winner.
    local stash="$RIG_ROOT/.reclaim.$$.${RANDOM}"
    if mv "$LEASE_ENV" "$stash" 2>/dev/null; then
      audit "RECLAIM agent=$agent stale_holder=${h:-?} (expired $(( $(now) - ${e:-0} ))s ago)"
      echo "rig: reclaimed stale lease from ${h:-?} (dead/wedged holder)."
      touch "$RECOVERY_FLAG"   # a dead holder likely left the cable wedged
      rm -f "$stash"
    fi
    # loop: ln the fresh lease into the now-free slot (or lose to another and go BUSY)
  done
}

cmd_renew() {
  local agent="${1:-}"; [ -n "$agent" ] || die "renew needs <agent>"
  [ -f "$LEASE_ENV" ] || die "no active lease" 4
  [ "$(getk "$LEASE_ENV" HOLDER)" = "$agent" ] || die "not the holder ($(getk "$LEASE_ENV" HOLDER) holds it)" 4
  local task sha tmp; task="$(getk "$LEASE_ENV" TASK)"; sha="$(getk "$LEASE_ENV" SHA)"
  tmp="$(build_lease "$agent" "$task" "$sha")"; mv -f "$tmp" "$LEASE_ENV"
  echo "rig: renewed by $agent (expires in ${TTL}s)."
}

cmd_release() {
  local agent="${1:-}" state=""
  shift || true
  while [ $# -gt 0 ]; do case "$1" in --state) state="${2:-}"; shift 2;; *) shift;; esac; done
  [ -n "$agent" ] || die "release needs <agent> --state healthy|wedged"
  [ "$state" = healthy ] || [ "$state" = wedged ] || die "release needs --state healthy|wedged"
  [ -f "$LEASE_ENV" ] || die "no active lease to release" 4
  [ "$(getk "$LEASE_ENV" HOLDER)" = "$agent" ] || die "not the holder ($(getk "$LEASE_ENV" HOLDER) holds it)" 4
  if [ "$state" = wedged ]; then
    touch "$RECOVERY_FLAG"
    audit "RELEASE-WEDGED agent=$agent — NEEDS_RECOVERY set for next acquirer"
    echo "rig: released by $agent as WEDGED. Next acquirer must run a recovery boot before trusting the link."
  else
    audit "RELEASE agent=$agent state=healthy"
    echo "rig: released by $agent (healthy)."
  fi
  rm -f "$LEASE_ENV"
}

cmd_recovered() {
  local agent="${1:-}"; [ -n "$agent" ] || die "recovered needs <agent>"
  rm -f "$RECOVERY_FLAG"
  audit "RECOVERED agent=$agent — NEEDS_RECOVERY cleared"
  echo "rig: NEEDS_RECOVERY cleared by $agent."
}

cmd_status() {
  mkdirs
  if [ -f "$LEASE_ENV" ]; then
    local e; e="$(getk "$LEASE_ENV" EXPIRY)"
    echo "rig: HELD by $(getk "$LEASE_ENV" HOLDER) on $(getk "$LEASE_ENV" HOST)"
    echo "     task : $(getk "$LEASE_ENV" TASK)"
    echo "     sha  : $(getk "$LEASE_ENV" SHA)"
    echo "     lease: expires in $(human_left "$e") (acquired $(date -r "$(getk "$LEASE_ENV" ACQUIRED)" '+%H:%M:%S' 2>/dev/null || echo '?'))"
  else
    echo "rig: FREE"
  fi
  [ -f "$RECOVERY_FLAG" ] && echo "rig: !! NEEDS_RECOVERY — link untrusted until a recovery boot + 'rig-lease.sh recovered <agent>'."
  local approved=0
  if ls "$QUEUE_DIR"/*.env >/dev/null 2>&1; then
    approved=$(grep -l '^STATE=approved' "$QUEUE_DIR"/*.env 2>/dev/null | wc -l | tr -d ' ') || approved=0
  fi
  echo "queue: ${approved} approved experiment(s) waiting. 'rig-lease.sh queue list' for detail."
}

next_seq() { local n=1; while ls "$QUEUE_DIR"/$(printf '%03d' "$n")-*.env >/dev/null 2>&1; do n=$((n+1)); done; printf '%03d' "$n"; }

cmd_queue() {
  mkdirs
  local sub="${1:-list}"; shift || true
  case "$sub" in
    add)
      local agent="${1:-}" slug="${2:-}" desc="${3:-}" sha="${4:-}"
      [ -n "$agent" ] && [ -n "$slug" ] && [ -n "$desc" ] || die "queue add <agent> <slug> \"<desc>\" [sha]"
      local seq f; seq="$(next_seq)"; f="$QUEUE_DIR/$seq-$slug.env"
      { echo "SEQ=$seq"; echo "SLUG=$slug"; echo "DESC=$desc"; echo "AUTHOR=$agent"; echo "SHA=$sha"; echo "STATE=proposed"; echo "CREATED=$(now)"; } >"$f"
      audit "QUEUE-ADD seq=$seq slug=$slug author=$agent sha=$sha"
      echo "queued [$seq] $slug (proposed) — maintainer approves with: rig-lease.sh queue approve $seq"
      ;;
    approve)
      local seq="${1:-}"; shift || true; local by="maintainer"
      while [ $# -gt 0 ]; do case "$1" in --by) by="${2:-}"; shift 2;; *) shift;; esac; done
      [ -n "$seq" ] || die "queue approve <seq> [--by <name>]"
      local f; f="$(ls "$QUEUE_DIR/$seq"-*.env 2>/dev/null | head -1)"; [ -n "$f" ] || die "no queue entry $seq" 2
      sed -i.bak 's/^STATE=.*/STATE=approved/' "$f" && rm -f "$f.bak"
      { echo "APPROVED_BY=$by"; echo "APPROVED_AT=$(now)"; } >>"$f"
      audit "QUEUE-APPROVE seq=$seq by=$by"
      echo "approved [$seq] by $by."
      ;;
    next)
      local f
      for f in $(ls "$QUEUE_DIR"/*.env 2>/dev/null | sort); do
        if [ "$(getk "$f" STATE)" = approved ]; then
          echo "next approved: [$(getk "$f" SEQ)] $(getk "$f" SLUG) sha=$(getk "$f" SHA)"
          echo "  $(getk "$f" DESC)"
          return 0
        fi
      done
      echo "queue: no approved work waiting."
      ;;
    list)
      printf '%-4s %-10s %-24s %s\n' SEQ STATE SLUG DESC
      local f
      for f in $(ls "$QUEUE_DIR"/*.env 2>/dev/null | sort); do
        printf '%-4s %-10s %-24s %s\n' "$(getk "$f" SEQ)" "$(getk "$f" STATE)" "$(getk "$f" SLUG)" "$(getk "$f" DESC)"
      done
      ;;
    done)
      local seq="${1:-}"; [ -n "$seq" ] || die "queue done <seq>"
      local f; f="$(ls "$QUEUE_DIR/$seq"-*.env 2>/dev/null | head -1)"; [ -n "$f" ] || die "no queue entry $seq" 2
      sed -i.bak 's/^STATE=.*/STATE=done/' "$f" && rm -f "$f.bak"
      mv "$f" "$DONE_DIR/"
      audit "QUEUE-DONE seq=$seq"
      echo "done [$seq] — moved to done/."
      ;;
    *) die "unknown queue subcommand: $sub" ;;
  esac
}

main() {
  local cmd="${1:-status}"; shift || true
  case "$cmd" in
    acquire)  cmd_acquire "$@";;
    renew)    cmd_renew "$@";;
    release)  cmd_release "$@";;
    recovered) cmd_recovered "$@";;
    status)   cmd_status "$@";;
    queue)    cmd_queue "$@";;
    *) die "unknown command: $cmd (acquire|renew|release|recovered|status|queue)";;
  esac
}
main "$@"
