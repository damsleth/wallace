#!/usr/bin/env bash
# Kill deviceinterfaced every 5 seconds until interrupted (Ctrl+C).
set -u

trap 'echo; echo "stopped"; exit 0' INT TERM

# Prime sudo once so the loop doesn't stall on a password prompt.
# sudo -v || exit 1

while true; do
  pids=$(pgrep -x deviceinterfaced)
  if [ -n "$pids" ]; then
    # shellcheck disable=SC2086
    kill -9 $pids && echo "$(date +%T) killed deviceinterfaced ($pids)"
  fi
  sleep 5
done
