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
# The scheduling model (see docs/COORDINATION.md):
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
# The ticket store (git-tracked JSON in tickets/; needs jq) — the backlog for
# BOTH offline tasks and rig experiments:
#   rig-lease.sh queue add <agent> <slug> "<desc>" [--needs rig|offline]
#              [--track T] [--pri P1] [--dep NNN]... [--image H --dtb H --initramfs H]
#   rig-lease.sh queue approve <seq|start-end|all> [--by <name>]   # rig tickets only
#   rig-lease.sh queue next [--rig|--offline]            # rig: next approved; offline: next open
#   rig-lease.sh queue list [--rig|--offline|--all]
#   rig-lease.sh queue show <seq>                        # full JSON
#   rig-lease.sh queue done <seq>
#
# Exit codes: 0 ok · 2 usage · 3 BUSY (held by a live other holder) · 4 not holder
set -euo pipefail

# Ephemeral, host-local, gitignored: the lease (a mutex) + its audit log.
RIG_ROOT="${RIG_ROOT:-$HOME/Code/wallace/.rig}"
LEASE_ENV="$RIG_ROOT/lease.env"      # a COMPLETE file; its atomic creation == the mutex
AUDIT_LOG="$RIG_ROOT/log"
RECOVERY_FLAG="$RIG_ROOT/NEEDS_RECOVERY"
# Durable, git-tracked: the ticket store (the backlog). One JSON file per ticket,
# offline and rig alike. This is NOT the lease — tickets are planned work you
# want versioned; the lease is runtime state you don't.
REPO_ROOT="${WALLACE_ROOT:-$HOME/Code/wallace}"
TICKETS_DIR="${RIG_TICKETS:-$REPO_ROOT/tickets}"
TICKETS_DONE="$TICKETS_DIR/done"
TTL="${RIG_LEASE_TTL:-3600}"         # seconds (60m); covers a boot cycle plus a
                                     # long analysis hold. Still release before
                                     # lengthy OFFLINE work — the lease is for
                                     # rig-touching, not for thinking. renew to extend.

now() { date +%s; }
mkdirs() { mkdir -p "$RIG_ROOT"; }
mktickets() { mkdir -p "$TICKETS_DIR" "$TICKETS_DONE"; }
audit() { mkdirs; printf '%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >>"$AUDIT_LOG"; }
# read one KEY from a key=value file (values may contain spaces)
getk() { [ -f "$1" ] && sed -n "s/^$2=//p" "$1" | head -1 || true; }
die() { echo "rig-lease: $1" >&2; exit "${2:-2}"; }

# --- ticket store helpers (JSON, one file per ticket; git-tracked) ---
# The `|| x=""` guards the bash 3.2 set -e quirk where a non-matching glob in
# $(...) aborts the script.
tk_need_jq() { command -v jq >/dev/null 2>&1 || die "the ticket queue needs jq on PATH (brew install jq)"; }
tk_file() {   # zero-padded seq -> ticket path ("" if none); checks active then done/
  local f; f="$(ls "$TICKETS_DIR/$1"-*.json 2>/dev/null | head -1)" || f=""
  [ -n "$f" ] || { f="$(ls "$TICKETS_DONE/$1"-*.json 2>/dev/null | head -1)" || f=""; }
  printf '%s' "$f"
}
tk_seqmax() {  # highest seq across active + done (so numbers are never reused)
  local m=0 f b n
  for f in "$TICKETS_DIR"/*.json "$TICKETS_DONE"/*.json; do
    [ -e "$f" ] || continue
    b="$(basename "$f")"; n=$((10#${b%%-*})); [ "$n" -gt "$m" ] && m=$n
  done
  echo "$m"
}

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
  # ticket summary (needs jq; skip quietly if absent so status still works)
  if command -v jq >/dev/null 2>&1 && ls "$TICKETS_DIR"/*.json >/dev/null 2>&1; then
    local rig_ready off_open f needs state
    rig_ready=0; off_open=0
    for f in "$TICKETS_DIR"/*.json; do
      [ -e "$f" ] || continue
      needs="$(jq -r '.needs' "$f")"; state="$(jq -r '.state' "$f")"
      [ "$needs" = rig ] && [ "$state" = approved ] && rig_ready=$((rig_ready + 1))
      [ "$needs" = offline ] && [ "$state" = open ] && off_open=$((off_open + 1))
    done
    echo "tickets: $rig_ready approved rig experiment(s), $off_open open offline task(s). 'rig-lease.sh queue list' for detail."
  else
    echo "tickets: (none, or jq missing). 'rig-lease.sh queue list' for detail."
  fi
}

# The ticket store: one git-tracked JSON file per ticket, offline and rig alike.
#   needs  = offline (grab and do, no approval) | rig (needs lease + approval)
#   state  = open (offline, actionable) | proposed (rig, awaiting CJ) |
#            approved (rig, ready to run) | done
cmd_queue() {
  tk_need_jq; mktickets
  local sub="${1:-list}"; shift || true
  case "$sub" in
    add)
      local agent="${1:-}" slug="${2:-}" desc="${3:-}"
      [ -n "$agent" ] && [ -n "$slug" ] && [ -n "$desc" ] || die "queue add <agent> <slug> \"<desc>\" [--needs rig|offline] [--track T] [--pri P1] [--dep NNN]... [--image H --dtb H --initramfs H]"
      shift 3
      local needs=offline track="" pri="" deps="[]" img="" dtb="" init=""
      while [ $# -gt 0 ]; do case "$1" in
        --needs) needs="${2:-}"; shift 2;;
        --track) track="${2:-}"; shift 2;;
        --pri|--priority) pri="${2:-}"; shift 2;;
        --dep) deps="$(printf '%s' "$deps" | jq -c --arg d "$(printf '%03d' "$((10#${2:-0}))")" '. + [$d]')"; shift 2;;
        --image) img="${2:-}"; shift 2;;
        --dtb) dtb="${2:-}"; shift 2;;
        --initramfs) init="${2:-}"; shift 2;;
        *) shift;;
      esac; done
      [ "$needs" = rig ] || [ "$needs" = offline ] || die "--needs must be rig|offline"
      local seq state; seq="$(printf '%03d' "$(( $(tk_seqmax) + 1 ))")"
      [ "$needs" = rig ] && state=proposed || state=open
      local f="$TICKETS_DIR/$seq-$slug.json"
      jq -n --arg seq "$seq" --arg slug "$slug" --arg needs "$needs" --arg state "$state" \
            --arg track "$track" --arg pri "$pri" --arg desc "$desc" --arg author "$agent" \
            --argjson deps "$deps" --arg img "$img" --arg dtb "$dtb" --arg init "$init" \
            --arg created "$(now)" '{
        seq:$seq, slug:$slug, needs:$needs, state:$state, track:$track, priority:$pri,
        desc:$desc, author:$author, deps:$deps,
        hashes: (if ($img=="" and $dtb=="" and $init=="") then null
                 else {image:$img, dtb:$dtb, initramfs:$init} end),
        created:($created|tonumber)}' > "$f"
      audit "TICKET-ADD seq=$seq slug=$slug needs=$needs author=$agent"
      if [ "$needs" = rig ]; then
        echo "added [$seq] $slug (rig, proposed) — approve with: rig-lease.sh queue approve $seq --by cj"
      else
        echo "added [$seq] $slug (offline, open) — any agent can pick it up."
      fi
      ;;
    approve)
      # Batch pre-approval of RIG tickets: <seq>, inclusive ranges <a>-<b>, or
      # "all". Offline tickets need no approval and are skipped with a note.
      # Space-joined specs keep bash 3.2 + set -u happy (no array expansion).
      local by="maintainer" specs=""
      while [ $# -gt 0 ]; do case "$1" in --by) by="${2:-}"; shift 2;; *) specs="$specs $1"; shift;; esac; done
      [ -n "$specs" ] || die "queue approve <seq|start-end|all> ... [--by <name>]"
      local n=0 miss="" skip=""
      _approve_one() {   # $1 = zero-padded seq
        local f; f="$(tk_file "$1")"
        [ -n "$f" ] || { miss="$miss $1"; return; }
        [ "$(jq -r '.needs' "$f")" = rig ] || { skip="$skip $1"; return; }
        local t="$f.tmp"
        jq --arg by "$by" --arg at "$(now)" '.state="approved" | .approved_by=$by | .approved_at=($at|tonumber)' "$f" >"$t" && mv "$t" "$f"
        audit "TICKET-APPROVE seq=$1 by=$by"; n=$((n + 1))
      }
      local s f
      for s in $specs; do
        if [ "$s" = all ]; then
          for f in "$TICKETS_DIR"/*.json; do [ -e "$f" ] || continue
            [ "$(jq -r '.needs' "$f")" = rig ] && [ "$(jq -r '.state' "$f")" = proposed ] && _approve_one "$(jq -r '.seq' "$f")"
          done
        elif printf '%s' "$s" | grep -qE '^[0-9]+-[0-9]+$'; then
          local lo hi i; lo=$((10#${s%-*})); hi=$((10#${s#*-})); i=$lo
          while [ "$i" -le "$hi" ]; do _approve_one "$(printf '%03d' "$i")"; i=$((i + 1)); done
        else
          _approve_one "$(printf '%03d' "$((10#$s))")"
        fi
      done
      echo "approved $n rig ticket$([ "$n" = 1 ] || echo s) by $by."
      [ -n "$miss" ] && echo "  (no such ticket:$miss)"
      [ -n "$skip" ] && echo "  (offline, no approval needed:$skip)"
      ;;
    next)
      # Default: the next approved RIG ticket (the lease-holder's schedule).
      # --offline: the next open OFFLINE task an idle agent can grab.
      local mode=rig want=approved
      while [ $# -gt 0 ]; do case "$1" in
        --rig) mode=rig; want=approved; shift;;
        --offline) mode=offline; want=open; shift;;
        *) shift;;
      esac; done
      local f
      for f in $(ls "$TICKETS_DIR"/*.json 2>/dev/null | sort); do
        if [ "$(jq -r '.needs' "$f")" = "$mode" ] && [ "$(jq -r '.state' "$f")" = "$want" ]; then
          local dep; dep="$(jq -r '.deps | join(" ")' "$f")"
          echo "next $mode: [$(jq -r '.seq' "$f")] $(jq -r '.slug' "$f")$(jq -r 'if .priority=="" then "" else " "+.priority end' "$f")"
          echo "  $(jq -r '.desc' "$f")"
          [ -n "$dep" ] && echo "  deps: $dep"
          return 0
        fi
      done
      echo "queue: no $mode work waiting."
      ;;
    list)
      local filt=all
      while [ $# -gt 0 ]; do case "$1" in --rig) filt=rig;; --offline) filt=offline;; --all) filt=all;; esac; shift; done
      printf '%-4s %-8s %-9s %-4s %-24s %s\n' SEQ NEEDS STATE PRI SLUG DESC
      local f needs
      for f in $(ls "$TICKETS_DIR"/*.json 2>/dev/null | sort); do
        needs="$(jq -r '.needs' "$f")"
        { [ "$filt" = all ] || [ "$filt" = "$needs" ]; } || continue
        printf '%-4s %-8s %-9s %-4s %-24s %s\n' \
          "$(jq -r '.seq' "$f")" "$needs" "$(jq -r '.state' "$f")" \
          "$(jq -r '.priority // "" | .[0:3]' "$f")" "$(jq -r '.slug' "$f")" "$(jq -r '.desc' "$f")"
      done
      ;;
    show)
      local seq="${1:-}"; [ -n "$seq" ] || die "queue show <seq>"
      seq="$(printf '%03d' "$((10#$seq))")"
      local f; f="$(tk_file "$seq")"; [ -n "$f" ] || die "no ticket $seq" 2
      jq . "$f"
      ;;
    done)
      local seq="${1:-}"; [ -n "$seq" ] || die "queue done <seq>"
      seq="$(printf '%03d' "$((10#$seq))")"
      local f; f="$(tk_file "$seq")"; [ -n "$f" ] || die "no ticket $seq" 2
      local t="$f.tmp"; jq --arg at "$(now)" '.state="done" | .done_at=($at|tonumber)' "$f" >"$t" && mv "$t" "$f"
      mv "$f" "$TICKETS_DONE/"
      audit "TICKET-DONE seq=$seq"
      echo "done [$seq] — moved to tickets/done/."
      ;;
    *) die "unknown queue subcommand: $sub (add|approve|next|list|show|done)" ;;
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
