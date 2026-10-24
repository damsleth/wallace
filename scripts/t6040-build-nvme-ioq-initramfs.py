#!/usr/bin/env python3
"""Build the RAM-only, Norwegian-keyboard NVMe read-only test archive."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--base', type=Path, required=True)
p.add_argument('--tester', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--init', type=Path, default=None,
               help='init script (default: scripts/t6040-init-nvme-ioq-readonly)')
a = p.parse_args()
script_dir = Path(__file__).resolve().parent
root = a.output.with_suffix('.root')
if a.output.exists() or root.exists():
    raise SystemExit('Refusing to overwrite an existing archive or staging root')
root.mkdir(parents=True)
# Explicit allow-list: no old init, startup scripts, root images or credentials.
subprocess.run(['bsdtar', '-xzf', str(a.base.resolve()), '-C', str(root),
                './bin/busybox', './etc/wallace-no.bmap', './sbin/fsck.exfat',
                './lib/firmware/brcm'], check=True)
for directory in ('proc', 'sys', 'dev', 'run', 'tmp', 'sbin'):
    (root / directory).mkdir(exist_ok=True)
for name in ('sh', 'cat', 'echo', 'ls', 'dmesg', 'sleep', 'uname', 'grep', 'blockdev'):
    (root / 'bin' / name).symlink_to('busybox')
shutil.copyfile(a.init or script_dir / 't6040-init-nvme-ioq-readonly', root / 'init')
shutil.copyfile(a.tester, root / 'sbin/nvme-readonly-test')
(root / 'init').chmod(0o755)
(root / 'sbin/nvme-readonly-test').chmod(0o755)
for file in (root / 'bin/busybox', root / 'sbin/fsck.exfat', root / 'sbin/nvme-readonly-test'):
    info = subprocess.check_output(['file', str(file)], text=True)
    if 'statically linked' not in info or 'aarch64' not in info:
        raise SystemExit('Wrong architecture or dynamic executable: ' + info)
raw = subprocess.check_output(['python3', str(script_dir / 'reproducible-newc.py'), str(root)])
a.output.write_bytes(gzip.compress(raw, mtime=0))
hashfile = lambda f: hashlib.sha256(f.read_bytes()).hexdigest()
manifest = {'base': str(a.base.resolve()), 'base_sha256': hashfile(a.base),
            'tester_sha256': hashfile(a.tester), 'init_sha256': hashfile(root/'init'),
            'archive_sha256': hashfile(a.output)}
a.output.with_suffix('.json').write_text(json.dumps(manifest, indent=2)+'\n')
print(json.dumps(manifest, indent=2))
