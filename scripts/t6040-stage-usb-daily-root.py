#!/usr/bin/env python3
"""Stage a separate direct-ext4 daily-root candidate; never open a device.

The known WiFi/OBEX root supplies pinned Alpine/OpenRC/packages/BCM4388 data.
This source-only step emits a regular directory and manifest, not a flash or
enrollment action. The caller separately packages and qualifies its image.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess

REPO = Path(__file__).resolve().parent.parent
OUT = Path('/Users/damsleth/Code/linux-build-out')
BASE_SHA = 'b04ccc1e96dde2fcf6fb536a5cbd951045cac1069384cfb284eb295cd6936092'
MAP_SHA = '606ecd98f83b72983f3cd35976df939dc9c7187283703736a81e89b65aee85a8'
HID_SHA = 'a1f4131d0cb7caf6fa15b19f47725458a6d7b0e3a34f15169339d5541663d9e2'


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda: f.read(1024 * 1024), b''):
            h.update(b)
    return h.hexdigest()


def require_file(path, digest=None):
    if not stat.S_ISREG(path.lstat().st_mode):
        raise ValueError(f'not a regular file: {path}')
    if digest and sha(path) != digest:
        raise ValueError(f'input SHA256 mismatch: {path}')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', required=True, type=Path)
    p.add_argument('--manifest', required=True, type=Path)
    p.add_argument('--partuuid', required=True)
    p.add_argument('--base', type=Path, default=OUT/'initramfs-alpine-wifi-obex.v4build1.cpio.gz')
    p.add_argument('--keymap', type=Path, default=OUT/'no-latin1.bmap')
    p.add_argument('--trackpad-firmware', type=Path,
                   default=OUT/'t6040-paired-fw-25F84/vendorfw/apple/tpmtfw-j614s.bin')
    p.add_argument('--wpa-conf', type=Path, required=True)
    a = p.parse_args()
    if not re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', a.partuuid):
        p.error('canonical lowercase --partuuid required')
    root = a.root.absolute()
    if root.is_symlink() or not root.is_dir() or any(root.iterdir()):
        p.error('--root must be an existing empty directory, not a symlink')
    root = root.resolve()
    if root == Path('/') or root == Path.home() or root == REPO:
        p.error('unsafe staging directory')
    if a.manifest.exists() or a.manifest.is_symlink():
        p.error('refusing to overwrite manifest')
    for path, digest in [(a.base, BASE_SHA), (a.keymap, MAP_SHA),
                         (a.trackpad_firmware, HID_SHA), (a.wpa_conf, None)]:
        require_file(path, digest)
    # The private config is never printed or put in the repository manifest.
    wpa = a.wpa_conf.read_bytes()
    if b'network=' not in wpa and b'network =' not in wpa:
        p.error('WPA config needs at least one network block')
    subprocess.run(['bsdtar', '-xf', str(a.base.resolve()), '-C', str(root)], check=True)

    def dest(name):
        f = root/name
        for parent in reversed(f.parents):
            if parent == root or root not in parent.parents:
                continue
            if parent.is_symlink():
                raise ValueError(f'symlink parent in staging output: {name}')
        f.parent.mkdir(parents=True, exist_ok=True)
        if f.is_symlink():
            f.unlink()
        return f

    def write(name, content, mode=0o644):
        f = dest(name)
        f.write_bytes(content if isinstance(content, bytes) else content.encode())
        f.chmod(mode)

    def copy(source, name, mode=0o755):
        write(name, source.read_bytes(), mode)

    def link(name, target):
        f = dest(name)
        if f.exists():
            f.unlink()
        f.symlink_to(target)

    if (root/'etc/alpine-release').read_text().strip() != '3.24.0':
        raise ValueError('unexpected Alpine release')
    for f in ['bin/busybox', 'sbin/openrc', 'sbin/openrc-run', 'etc/init.d/mount-ro',
              'sbin/wpa_supplicant', 'sbin/dhcpcd', 'usr/bin/bluetoothctl',
              'usr/lib/bluetooth/obexd', 'usr/bin/dbus-daemon', 'usr/bin/gdbus',
              'usr/share/udhcpc/default.script']:
        if not (root/f).is_file() or not os.access(root/f, os.X_OK):
            raise ValueError(f'missing executable {f}')
    if (root/'sbin/init').readlink().as_posix() != '/bin/busybox':
        raise ValueError('unexpected PID1')
    # Drop the old RAM-root init and opt-in startup state. No network is started
    # while staging. No SD pivot or obsolete diagnostic-health policy is copied.
    for name in ['init', 'etc/machine-id', 'var/lib/dbus/machine-id']:
        dest(name).unlink(missing_ok=True)
    shutil.rmtree(root/'etc/runlevels')
    for level in ['sysinit', 'boot', 'default', 'shutdown']:
        (root/'etc/runlevels'/level).mkdir(parents=True)
    services = {
        'sysinit': ['devfs', 'dmesg', 'procfs', 'sysfs'],
        'boot': ['hostname', 'bootmisc', 'sysctl', 't6040-keymap'],
        'default': ['t6040-wifi-ready', 'wpa_supplicant', 'dhcpcd', 'dbus', 'bluetooth'],
        'shutdown': ['killprocs', 'mount-ro'],
    }
    for src, dst in [
        ('t6040-usb-root-keymap.initd', 'etc/init.d/t6040-keymap'),
        ('t6040-usb-root-wifi-ready.initd', 'etc/init.d/t6040-wifi-ready'),
        ('t6040-usb-root-openrc', 'usr/local/sbin/t6040-usb-root-openrc'),
        ('t6040-usb-root-autologin-daily', 'usr/local/sbin/t6040-b0-autologin'),
        ('t6040-b0-ttydc0-console', 'usr/local/sbin/t6040-b0-ttydc0-console'),
        ('t6040-bt-obex.sh', 'usr/local/sbin/t6040-bt-obex'),
    ]:
        copy(REPO/'scripts'/src, dst)
    for level, names in services.items():
        for name in names:
            if not (root/'etc/init.d'/name).is_file():
                raise ValueError(f'missing service {name}')
            link(f'etc/runlevels/{level}/{name}', f'/etc/init.d/{name}')
    copy(a.keymap, 'etc/wallace-no.bmap', 0o644)
    copy(a.trackpad_firmware, 'lib/firmware/apple/tpmtfw-j614s.bin', 0o644)
    write('etc/conf.d/keymaps', 'keymap="no"\n')
    write('etc/X11/xorg.conf.d/00-keyboard.conf',
          'Section "InputClass"\n    Identifier "Norwegian keyboard"\n'
          '    MatchIsKeyboard "on"\n    Option "XkbLayout" "no"\nEndSection\n')
    write('etc/profile.d/wallace-locale.sh', 'export LANG=nb_NO.UTF-8\nexport LC_CTYPE=nb_NO.UTF-8\n')
    link('etc/localtime', '/usr/share/zoneinfo/Europe/Oslo') if (root/'usr/share/zoneinfo/Europe/Oslo').is_file() else None
    write('etc/wallace-root-partuuid', a.partuuid+'\n')
    write('etc/wallace-root-profile', 'usb-daily-6005-v1\n')
    write('etc/hostname', 'wallace\n')
    write('etc/fstab', f'PARTUUID={a.partuuid} / ext4 defaults,noatime 0 0\n')
    # fsck is already performed read-only by the verified init before RW.
    write('etc/inittab', '::sysinit:/sbin/openrc sysinit\n::sysinit:/sbin/openrc boot\n'
          '::wait:/sbin/openrc default\n'
          '::shutdown:/usr/local/sbin/t6040-usb-root-openrc shutdown\n'
          'tty1::respawn:/sbin/getty -n -l /usr/local/sbin/t6040-b0-autologin 38400 tty1 linux\n'
          '::respawn:/usr/local/sbin/t6040-b0-ttydc0-console\n')
    write('etc/wpa_supplicant/wpa_supplicant.conf',
          b'ctrl_interface=/run/wpa_supplicant\np2p_disabled=1\n'+
          b'\n'.join(l for l in wpa.splitlines()
                     if not l.strip().startswith((b'ctrl_interface=', b'p2p_disabled=')))+b'\n', 0o600)
    write('etc/conf.d/wpa_supplicant', 'wpa_supplicant_if="wlan0"\n'
          'wpa_supplicant_dbus="no"\nrc_need="t6040-wifi-ready"\n')
    write('etc/conf.d/dhcpcd', 'command_args="wlan0"\nrc_need="wpa_supplicant"\n')
    write('etc/dhcpcd.conf', 'hostname\nclientid\npersistent\noption domain_name_servers, domain_name, domain_search\n'
          'option classless_static_routes\noption interface_mtu\nrequire dhcp_server_identifier\n'
          'allowinterfaces wlan0\nnoipv4ll\n')
    write('etc/network/interfaces', '# WiFi is owned only by wpa_supplicant + dhcpcd OpenRC services.\n')
    write('etc/motd', 'Wallace USB-root integration candidate; hardware acceptance pending.\n')
    files = {}
    for f in sorted(root.rglob('*')):
        rel = f.relative_to(root).as_posix()
        mode = f.lstat().st_mode
        if stat.S_ISBLK(mode) or stat.S_ISCHR(mode):
            raise ValueError(f'archive contains device node {rel}')
        if f.is_symlink():
            files[rel] = {'link': str(f.readlink())}
        elif f.is_file():
            files[rel] = {'mode': oct(stat.S_IMODE(mode)),
                          'sha256': 'PRIVATE_CONFIG_NOT_RECORDED' if rel == 'etc/wpa_supplicant/wpa_supplicant.conf' else sha(f)}
    a.manifest.parent.mkdir(parents=True, exist_ok=True)
    a.manifest.write_text(json.dumps({
        'format': 't6040-usb-daily-root-v1', 'runnable': False,
        'base_sha256': BASE_SHA, 'partuuid': a.partuuid,
        'keymap_sha256': MAP_SHA, 'trackpad_firmware_sha256': HID_SHA,
        'network_owner': 'OpenRC wpa_supplicant + dhcpcd; no networking service',
        'obex': 'helper installed; pairing/receive/send explicitly invoked later',
        'services': services, 'files': files,
        'limitations': ['No boot, shutdown, DHCP or OBEX hardware result.',
                        'Kernel/modules and reviewed physical stick identity must be paired separately.',
                        'Root-side shutdown wrapper needs contained real-filesystem validation.',
                        'No automatic desktop startup or claim of Xorg packages; layout config is staged.'],
    }, indent=2)+'\n')
    print(f'Staged candidate: {root}; manifest: {a.manifest}')


if __name__ == '__main__':
    main()
