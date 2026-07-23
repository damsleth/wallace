# T6040 external USB rootfs population recipe (2026-07-23)

Ticket 060 (offline, P1, storage). This closes the recipe and host-verification
part of the external-root work without formatting, mounting, or populating a
real disk. The live USB gate remains closed: ticket 063 brought up the
right-port DART and xHCI root hubs, but no child device or `sd*` appeared.

## Deliverables

- `scripts/t6040-populate-usb-rootfs.sh` stages or deploys the root filesystem.
- `scripts/t6040-test-populate-usb-rootfs.sh` exercises the safe host path,
  pinned-input check, manifest, and refusal cases without touching a block
  device.

The rootfs is the official Alpine 3.24.0 aarch64 minirootfs, pinned to:

```text
alpine-minirootfs-3.24.0-aarch64.tar.gz
SHA-256 4b8cd66a6688b2a87276c39843ed89c3a06d9534fc6a5823c586aff2696c1f2a
```

The resulting layout is one GPT Linux-filesystem partition, ext4
`LABEL=t6040root`. A fresh disk GUID, partition GUID/PARTUUID, and filesystem
UUID are generated during deployment and recorded in a manifest. The boot
selector is the stable partition GUID:

```text
root=PARTUUID=<recorded-guid> rootfstype=ext4 rootwait
```

The script also installs an input modules tree under `/lib/modules` and an input
Asahi firmware corpus under `/lib/firmware`. The full corpus stays on the
persistent root, not in the boot-critical initramfs.

## Safety boundary

There are two deliberately different modes:

1. `stage` extracts into an explicitly named, existing, empty directory. It
   refuses a non-empty directory, the filesystem root, and broad home
   directories. This is the mode tested now.
2. `device` is the eventual deployment path. It is Linux-only and requires
   root, a whole block device reported removable by `lsblk`, no mounted child,
   and the literal confirmation `--confirm ERASE:/dev/sdX`. It then uses
   `wipefs`, `sgdisk`, and `mkfs.ext4`.

No broad path, implicit “last attached disk,” glob, or unstable `/dev/sdX`
value is used for boot. The operator must resolve and review the exact device
immediately before the destructive command.

## Host verification

The host test used the pinned Alpine archive plus tiny synthetic module and
firmware trees. It verified:

- the archive SHA before extraction;
- aarch64 BusyBox and `/sbin/init`;
- the exact `PARTUUID` fstab and bootarg;
- module and firmware file hashes in the manifest;
- refusal of a non-empty staging directory without modifying its file;
- refusal of a bad Alpine hash before extraction;
- refusal of `device` mode on this macOS host.

Result:

```text
USB rootfs host tests: PASS
```

File hashes at completion:

| File | SHA-256 |
|---|---|
| `scripts/t6040-populate-usb-rootfs.sh` | `73e54977ecc777aed8c484796efee1400e66962c98b482974554da94a07172a2` |
| `scripts/t6040-test-populate-usb-rootfs.sh` | `6b040c5abe8a915bd3f102c4a09516e5f1b35166cc75d9ee51439f6488b87d13` |

## Eventual deployment inputs

Do not run this section until the USB-host smoke gate passes.

The modules input must be built from the exact ROOT-mode kernel tree. The
currently preserved `/build/linux-usb-host4` tree reports
`7.1.3-g96ac043df12f-dirty`; it has `CONFIG_MODULES=y`, but its modules have not
been built or installed. After the gate, rebuild the final kernel and stage the
matching tree with:

```sh
make modules
make modules_install INSTALL_MOD_PATH=/out/t6040-usb-root-modules
```

Pass the resulting
`/out/t6040-usb-root-modules/lib/modules/<kernel-release>` directory as
`--modules`. Pass the root-ready contents destined below `/lib/firmware` as
`--firmware`. Ticket 030 still owns the complete J614s paired-firmware corpus;
the host currently has only proven WiFi/BT and multitouch slices, not the full
daily-driver corpus.

Safe staging example:

```sh
mkdir /tmp/t6040-root-stage
scripts/t6040-populate-usb-rootfs.sh stage \
    --root /tmp/t6040-root-stage \
    --partuuid 11111111-2222-3333-4444-555555555555 \
    --alpine ~/Code/linux-build-out/alpine-minirootfs-3.24.0-aarch64.tar.gz \
    --modules /path/to/lib/modules \
    --firmware /path/to/lib/firmware \
    --manifest /tmp/t6040-root-stage.manifest
```

The UUID in this example is a host-test fixture, never a deployment value.

## Remaining live gate

Do **not** format or mount the connected USB stick yet. Resume deployment only
after a separately reviewed host-mode artifact shows a child device and `sd*`
persisting for at least ten seconds. That currently requires either a
self-powered/powered USB fixture or reviewed T6040 HPM/ATC support. Once that
gate clears, resolve the exact removable disk, run `device` mode, record its
manifest, and create a separate reviewed ROOT-mode boot proposal.

No rig, block-device write, filesystem mount, or persistent image creation
occurred for ticket 060.
