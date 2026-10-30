#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Run the actual USB /init as PID1 in a contained fake-device fixture.
# All mount/fsck/metadata/switch_root operations are intercepted; no block I/O.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE_OUT=${OUT:-/Users/damsleth/code/linux-build-out}
RES=${1:-$BASE_OUT/usb-root-6005/startup-$(date +%Y%m%dT%H%M%S)}
IMAGE=docker.io/library/alpine@sha256:2c9d26f410d032d5b1525aa8a873e238b05b90c4ae8618743d4311f0cc827e37
[ ! -e "$RES" ] || { echo "refusing to overwrite $RES" >&2; exit 1; }
mkdir -p "$RES/in" "$RES/out"
cp "$ROOT/scripts/t6040-init-usb-root-verified" "$RES/in/init"
cp "$ROOT/scripts/t6040-usb-root-select.sh" "$RES/in/select"
cp "$ROOT/scripts/t6040-test-usb-root-startup-ns.sh" "$RES/in/test.sh"
cp "$BASE_OUT/no-latin1.bmap" "$RES/in/keymap"
printf '%s  %s\n' 606ecd98f83b72983f3cd35976df939dc9c7187283703736a81e89b65aee85a8 \
    "$RES/in/keymap" | shasum -a 256 -c -
(cd "$RES/in" && shasum -a 256 init select test.sh keymap) >"$RES/source-hashes.txt"
export USB_STARTUP_RES=$RES USB_STARTUP_IMAGE=$IMAGE
# Keep this parent alive through startup+test: a VM launched in a short-lived
# tool session can lose its API forwarding before the next command runs.
python3 - <<'PY'
import json, os, subprocess
res, image = os.environ['USB_STARTUP_RES'], os.environ['USB_STARTUP_IMAGE']
machines = json.loads(subprocess.check_output(['podman','machine','list','--format','json']))
if not any(x['Running'] for x in machines):
    subprocess.run(['podman','machine','start','podman-machine-default'],check=True)
cmd = ['podman','machine','ssh','--','sudo','podman','run','--rm','--privileged',
       '--name','wallace-usb-root-startup-6005','-v',res+'/in:/in:ro','-v',res+'/out:/out',
       '--tmpfs','/work:rw,exec,dev,size=512m',image,'sh','/in/test.sh']
raise SystemExit(subprocess.run(cmd).returncode)
PY
echo "Startup control-flow results: $RES/out"
