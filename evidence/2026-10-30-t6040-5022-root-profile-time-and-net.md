# 5022: on-device root changes folded into the nvmeroot recipe (claude, 2026-10-30)

**Result:** `scripts/t6040-build-nvmeroot-image.sh` now reproduces the live standalone root's
time, network and shell setup. The profile marker moves to `nvmeroot-5005-v3`. No root was
rebuilt. The harness check passed for the profile section; the package step is untested
until the next Mac build.

## What changed in the recipe

| Live change (2026-10-25..30) | Recipe |
|---|---|
| `boot: swclock` (no `/dev/rtc`: the macsmc RTC never binds) | added to the runlevel list |
| seed `/var/lib/misc/openrc-shutdowntime` | created with a fixed mtime, 2026-10-30T00:00Z, so swclock never starts in 1970 |
| `default: chronyd`, busybox ntpd gone | chronyd linked if present; the recipe never linked ntpd |
| `chrony.conf` `rtcsync` commented out | same sed, same comment text as live |
| `default: sshd` | **changed on purpose:** enabled only when `AUTHORIZED_KEYS=<pubkey>` is given, root key-only (`prohibit-password`, no password or keyboard-interactive auth, via `sshd_config.d/10-wallace.conf`) |
| iwd out of all runlevels | never linked; comment records why (no AF_ALG hash/skcipher or KEY_DH_OPERATIONS in the kernel) |
| `/etc/profile.d/local-bin.sh` | written byte-identical to live |
| packages chrony, openssh-server, jq, perl, kexec-tools | `EXTRA_APKS`, pinned to the live versions and installed with the root's own apk in a chroot; `NO_EXTRA_APKS=1` skips them |

Left out on purpose: `debootstrap` (only used for an on-device kernel build that was abandoned)
and `llvm18` (large; installed for wallace-rex reading, not part of the desktop).

**sshd on the live root (not changed):** it listens on 0.0.0.0:22 and :::22 with
`PermitRootLogin yes`, root has a password, and there is no `authorized_keys`, so it accepts
password logins as root from the network. The recipe does not copy that. Changing the live root
is CJ's call.

## t6040-net-up

inittab's `::once:… t6040-sdroot-openrc net` runs `/usr/local/sbin/t6040-net-up`, which the
nvmeroot initramfs does not ship (WiFi comes from `t6040-sdroot-net`). `t6040-sdroot-openrc` now
exits 0 when the helper is missing. That takes effect only with the next initramfs build;
the running initramfs `82a86064` is unchanged.

## Harness check

The changed section of the container script (from `rm -rf etc/runlevels` to the profile marker)
ran with busybox sh against a stub root with every referenced init script and a chrony.conf
containing `rtcsync`:

```
sysinit: devfs dmesg procfs sysfs
boot: bootmisc hostname swclock t6040-keymap
default: bluetooth chronyd dbus sshd
shutdown: killprocs mount-ro
# rtcsync  (disabled: no RTC on this machine; swclock restores time at boot)
var/lib/misc/openrc-shutdowntime  2026-10-30 00:00 UTC
sshd_config.d/10-wallace.conf: PermitRootLogin prohibit-password / PasswordAuthentication no / KbdInteractiveAuthentication no
root/.ssh 700, authorized_keys 600
profile marker: nvmeroot-5005-v3
```

The runlevels equal the live root's exactly. `bash -n` passes for the builder, and `sh -n`
passes for `t6040-sdroot-openrc` and the generated `local-bin.sh`. Not tested here: the
`chroot . /sbin/apk add` step (no podman on the M4), which runs on the next Mac build.
