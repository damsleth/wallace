#!/usr/bin/env python3
"""Verify a pinned IOQ payload; --run requires CJ readiness and a held rig lease."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('manifest', type=Path)
p.add_argument('--run', action='store_true', help='Only after CJ says M4 is waiting for payload')
a = p.parse_args()
m = json.loads(a.manifest.read_text())
for entry in m['files']:
    f = Path(entry['path'])
    digest = hashlib.sha256(f.read_bytes()).hexdigest()
    if digest != entry['sha256']:
        raise SystemExit('STOP: hash mismatch: ' + str(f))
# Keep this assembly identical to the existing boot harness.
bootargs = ('maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused '
            'console=tty0 fbcon=font:TER16x32 ignore_loglevel '
            'console=ttydc0 console=tty0 rdinit=/init')
if m['bootargs'] != bootargs:
    raise SystemExit('STOP: unexpected bootargs')
root = Path(__file__).resolve().parent.parent
payload = Path(m['payload_directory'])
subprocess.run(['bash', str(root/'scripts/t6040-image-preflight.sh'),
                '--kernel', str(payload/'Image'), '--initramfs', str(payload/'initramfs.cpio.gz'),
                '--m1n1', str(payload/'m1n1.bin'), '--proxy-payload', '--bootargs', bootargs], check=True)
if not a.run:
    print('Verified pinned files and preflight. No rig access. Run awaits CJ readiness.')
    raise SystemExit(0)
ticket_path = root / 'tickets/6001-nvme-ans2-ioq-size-readonly-run.json'
ticket = json.loads(ticket_path.read_text())
if ticket.get('state') != 'approved' or ticket.get('runnable') is not True:
    raise SystemExit('STOP: ticket 6001 is not approved and independently ready')
for field, file in [('image', 'Image'), ('dtb', 't6040-nvme.dtb'), ('initramfs', 'initramfs.cpio.gz')]:
    if ticket['hashes'][field] != hashlib.sha256((payload/file).read_bytes()).hexdigest():
        raise SystemExit('STOP: ticket payload mismatch: ' + field)
# Boot harness performs the lease guard before touching the serial link.
run_dir = a.manifest.resolve().parent / 'runs' / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
run_dir.mkdir(parents=True, exist_ok=False)
env = os.environ.copy()
# Remove overrides that could invalidate the exact reviewed command line/link.
for key in ('EXTRA_BOOTARGS', 'BOOT_SKIP_IMAGE_CHECK', 'RIG_BYPASS', 'RIG_ROOT', 'RIG_ALLOW_RECOVERY'):
    env.pop(key, None)
out = Path('/Users/damsleth/Code/linux-build-out')
rel = str(payload.relative_to(out))
env.update(RIG_AGENT='astra', RIG_ENFORCE='1', M1N1DEVICE='/tmp/m1n1',
           M1N1_BIN=str(payload/'m1n1.bin'), IMAGE=rel+'/Image', BOOT_MAXCPUS='1',
           BOOT_IDLE='nop', KERNEL_LOG_ARGS='ignore_loglevel console=ttydc0 console=tty0',
           LOG_DIR=str(run_dir), CHAINLOAD_ATTEMPTS='1', BOOT_WAIT='30', T6040_KEEPALIVE='0')
print('Unique transcript directory:', run_dir, flush=True)
# This is a single run. No boot/read-test retries on failure.
result = subprocess.run(['bash', str(root/'scripts/t6040-boot-dcuart.sh'),
                         rel+'/t6040-nvme.dtb', rel+'/initramfs.cpio.gz'], env=env)
print('Preserve the entire transcript; host must stop/recover if no completed test within 240s of START.')
print('No pass is inferred from upload success. Run the transcript checker and inspect full kernel log.')
raise SystemExit(result.returncode)
