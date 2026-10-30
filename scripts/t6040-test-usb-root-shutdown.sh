#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Real OpenRC/ext4 shutdown gate, confined to files/loops in the Podman VM.
# Root shell is PID1 in a fresh PID+mount namespace. No power action is sent.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
BASE=${OUT:-/Users/damsleth/code/linux-build-out}
ROOTFS=${USB_DAILY_ROOT:-$BASE/usb-root-6005/daily-root-stage1-20261024}
RES=${1:?usage: t6040-test-usb-root-shutdown.sh NEW_RESULT_DIR}
IMAGE=docker.io/library/alpine@sha256:2c9d26f410d032d5b1525aa8a873e238b05b90c4ae8618743d4311f0cc827e37
[ ! -e "$RES" ] || { echo "refusing to overwrite $RES" >&2; exit 1; }
[ -f "$ROOTFS/etc/wallace-root-profile" ] || { echo 'stage the candidate root first' >&2; exit 1; }
mkdir -p "$RES/in" "$RES/out"
cp "$REPO/scripts/t6040-test-usb-root-shutdown-ns.sh" "$RES/in/test.sh"
cp "$REPO/scripts/t6040-usb-root-openrc" "$RES/in/shutdown"
python3 - "$RES" "$ROOTFS" <<'PY'
import json,pathlib,sys
res=pathlib.Path(sys.argv[1]); root=pathlib.Path(sys.argv[2])
(res/'in/seccomp.json').write_text(json.dumps({'defaultAction':'SCMP_ACT_ALLOW',
    'syscalls':[{'names':['reboot'],'action':'SCMP_ACT_ERRNO','errnoRet':1}]}))
(res/'inputs.txt').write_text('root='+str(root)+'\n'+'test_scope=VM scratch loop files only\n')
PY
export USB_SHUTDOWN_RES=$RES USB_SHUTDOWN_IMAGE=$IMAGE USB_SHUTDOWN_ROOT=$ROOTFS
python3 - <<'PY'
import json,os,subprocess
res,image,root=(os.environ[x] for x in ['USB_SHUTDOWN_RES','USB_SHUTDOWN_IMAGE','USB_SHUTDOWN_ROOT'])
machines=json.loads(subprocess.check_output(['podman','machine','list','--format','json']))
if not any(x['Running'] for x in machines):
    subprocess.run(['podman','machine','start','podman-machine-default'],check=True)
cmd=['podman','machine','ssh','--','sudo','podman','run','--rm','--privileged',
     '--name','wallace-usb-root-shutdown-6005','--security-opt','seccomp='+res+'/in/seccomp.json',
     '-v',res+'/in:/in:ro','-v',res+'/out:/out','-v',root+':/candidate:ro',
     '--tmpfs','/work:rw,exec,dev,size=1g',image,'sh','/in/test.sh']
raise SystemExit(subprocess.run(cmd).returncode)
PY
