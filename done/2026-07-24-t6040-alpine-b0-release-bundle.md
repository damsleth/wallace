# T6040 Alpine B0 release bundle

> **Final amendment:** independent review and ticket 100's tethered
> single-object run passed. Exact object `2371ee5d...` reached OpenRC default
> runlevel, panel shell, internal keyboard echo, watchdog, and empty
> partitions. Ticket 081 is done. Dual-mode enrollment candidate
> `46237ade...` subsequently received ticket 119's conditional independent
> PASS: exact post-prefix identity is proved, while version/Rust inputs must
> be pinned before claiming a fully reproducible m1n1 rebuild.

Date: 2026-07-24  
Tickets: 079, 081, and live proof 100 complete
Scope: offline build and verification only; no rig, USB, APFS, or enrollment

## Result

The diagnostic custom-`/init` image is now a reproducible Alpine 3.24.0
aarch64 RAM distro using normal BusyBox init and OpenRC runlevels. It has:

- sysinit `devfs`, `dmesg`, `procfs`, and `sysfs` ordering;
- boot `hostname` and `sysctl` ordering;
- default-runlevel hardware-watchdog and bounded health-report services;
- framebuffer `tty0` and delayed DockChannel `ttydc0` local consoles;
- a locked root password and an explicit passwordless local diagnostic shell;
- no enabled network service, resolver, interface configuration, block node,
  storage discovery service, persistent mount, or secret.

`ifupdown-ng` and `bridge` are installed only because pinned OpenRC declares
them as dependencies. `/etc/network` is absent, `/etc/apk/repositories` is
empty, and no network service is linked into any runlevel.

## Exact RAM distro

```text
initramfs-alpine-b0.cpio.gz
size       4,497,775 bytes
SHA-256    ddd981711e91c917b735d39df0e90dd50200c158e1ea54c7f2c171c8ad317024
expanded  13,628,972 bytes
entries             699
block nodes            0
```

Two complete builds from a fresh Alpine extraction byte-match. The first
attempt correctly failed this gate because `/var/log/apk.log` contained the
installation time; the final builder removes that non-runtime log. The strict
newc parser verifies the archive hash, required init/runlevel paths, locked
root, aarch64 APK identity, absent network configuration, and zero block
nodes.

The source minirootfs is fixed at
`4b8cd66a6688b2a87276c39843ed89c3a06d9534fc6a5823c586aff2696c1f2a`.
Every added APK is exact-version and SHA-pinned in
`scripts/t6040-build-alpine-b0.sh`. The generated `.packages`, `.contents`,
`.sizes`, and `.manifest` files record the complete installed package and
file surface.

## Exact self-contained object

The ticket-081 candidate packages the release RAM distro with the exact
ticket-078 live-proven HID-restored kernel and storage-disabled DTB behind the
PCIe-write-free m1n1 upper-guard binary:

```text
m1n1-b0-alpine-openrc.bin
size       22,183,563 bytes
SHA-256    2371ee5dfbfab591397fc333e7da212fb7582bfb2eaddaa6438005f5bb41759b
entry      0x800
```

| Component | SHA-256 |
|---|---|
| safe m1n1 | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| live-proven uncompressed kernel | `df7657c15ad73a486f5046bcc802f070d6b7ec071fb6bb70954fb8f222d4815a` |
| compressed kernel member | `d76463e51cf3fb61e0af93f9ea6f24562de32db78988eeaa98a031f0c336bcc5` |
| storage-disabled DTB | `2782b92237c35c8950212207391c3ae28c44b6b9c635b2e864c5748a77bb3cce` |
| Alpine/OpenRC initramfs | `ddd981711e91c917b735d39df0e90dd50200c158e1ea54c7f2c171c8ad317024` |

Command line:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/sbin/init
```

Strict record decode:

| Offset | Stored bytes | Role |
|---:|---:|---|
| `0x10c000` | 145 | `chosen.bootargs` |
| `0x10c091` | 16,536,252 | gzip kernel |
| `0x10d134d` | 51,659 | raw DTB |
| `0x10ddd18` | 4,497,775 | gzip initramfs |
| `0x1527e87` | 4 | zero terminator |

Two object builds byte-match. The verifier expands and byte-compares all
members, enforces record order and the 64 MiB complete-object ceiling, and
computes a conservative 67,911,671-byte runtime payload reserve. The observed
m1n1 heap is much larger; the per-component limits from ticket 080 all pass.

## Live boundary

This closed offline ticket 079. Independent review then reproduced the exact
object, and ticket 100 observed OpenRC, framebuffer shell, typed internal
keyboard input, watchdog, and empty partitions together. Tickets 081 and 100
are done. Ticket 089 remains the historical delivery-only control.
