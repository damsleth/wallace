# T6040 SD root repair v2 — offline rebuild and fail-closed review

Date: 2026-08-03

Rig use: **none**. This review rebuilt ordinary initramfs files on the host. It
did not open a block device, mount the SD card, acquire the rig lease, or issue
an SMC, SPMI, PMU, MMIO, storage, firmware, NVRAM, or external-posting action.

## Outcome

The former ticket-215 artifact is withdrawn. It was not safe to run as pinned:

1. its inherited `/init` started WiFi, DHCP, SSH, and a watchdog before the
   repair command, outside the storage-repair scope;
2. the first mutating `fsck.exfat` was gated by partition name, label, and
   filesystem type, but the nested ext4 UUID was not proved until after that
   write; and
3. its DTB had SMC disabled and no `gP19` `pwren-gpios`, so it could not power
   the GL9755 SD-reader endpoint after a cold boot.

The replacement fixes all three issues and the complete boot object is
reproducible. The ticket remains non-runnable pending independent exact review.

## First-write boundary

`scripts/t6040-sdroot-fsck.sh` now refuses to mutate storage until all of the
following have succeeded:

- no SError, DART/IOMMU fault, internal error, or kernel panic is present;
- PCI device `0000:02:00.0` exists with vendor/device `17a0:9755`;
- it is bound to `sdhci-pci` and has an IOMMU group;
- `/dev/mmcblk0` resolves under that exact PCI device in sysfs;
- partition 1 has label `SD64` and filesystem type `exfat`;
- `fsck.exfat -n` returns only clean or errors-found;
- exFAT mounts read-only and `wallace-root.img` is exactly 6,442,450,944 bytes;
- a read-only loop attachment has ext4 UUID
  `4c41b99c-7747-4688-85a5-397bc5d784a2` and type `ext4`; and
- `e2fsck -f -n` returns only clean or errors-left-uncorrected.

Only then may automatic `fsck.exfat -p` and `e2fsck -f -p` run. There is no
force-repair, formatter, partition editor, resize, discard, raw-write, or
arbitrary target option. Post-repair read-only checks, loop detach, exFAT
unmount, a final exFAT check, and the fault gate are mandatory for PASS.

## Minimal init

`scripts/t6040-sdroot-fsck-init` mounts only proc, sysfs, devtmpfs, `/tmp`, and
`/run`; opens the proven DockChannel console; runs the exact approved repair
command once; synchronizes; and leaves a recovery shell. It does not start
OpenRC, networking, DHCP, SSH, automount, or a background process.

The builder replaces the inherited `/init`, removes WiFi configuration, SSH
keys, and SSH host keys, and removes the out-of-scope storage mutation tools.
Archive inspection found none of the forbidden paths. The embedded `/init` and
repair-script hashes equal their source hashes.

## Reproducible artifacts

Two independent builds are byte-identical:

```text
f32adbe6683cf438a34311f659ec50c96b0d93afee33dc912cab173879e9afda  initramfs-bootstrap-sdroot-fsck-v2.build1.cpio.gz
f32adbe6683cf438a34311f659ec50c96b0d93afee33dc912cab173879e9afda  initramfs-bootstrap-sdroot-fsck-v2.build2.cpio.gz
```

Sources:

```text
a304a869dc3c6046383b87bf1077285db5f845969cdf49e77bbfea1620853e5f  scripts/t6040-build-sdroot-fsck-initramfs.sh
376792502a038f67cb477da267fee419e2842462253d60ae08c4416afb535b30  scripts/t6040-sdroot-fsck-init
f6192dbea2d89a72ad4ddbeccc1a3978680be8c07b01485f4d1673955a243c14  scripts/t6040-sdroot-fsck.sh
434d1baa4d58ae4a7d5b61de3e24a371c38735a46ec999c2d047a011fd0a2e64  exfatprogs-1.4.1-r0.apk
```

## SD-only DTB and complete object

The SD overlay now explicitly disables port 0 (WiFi/BT). Its compiled DTB
keeps all ANS/NVMe nodes disabled, keeps SPMI disabled, enables the SMC needed
for endpoint power, and gives only port 1 the already-approved
`pwren-gpios = <&smc_gpio 0x19 GPIO_ACTIVE_HIGH>` property. Two builds are
byte-identical:

```text
b6d4effbe506c5818f3e0fcc6e6de1ed6e1ac400b50304007a61102ef84acc05  dts/t6040-j614s-dcuart-sd.dts
4e482173d1ebf6e52dc127a04b78a7a3c8a90b4bb5e8c3adbd5a162bf4b85a82  t6040-j614s-dcuart-sd-v2.build1.dtb
4e482173d1ebf6e52dc127a04b78a7a3c8a90b4bb5e8c3adbd5a162bf4b85a82  t6040-j614s-dcuart-sd-v2.build2.dtb
```

The raw object uses the two-build-identical SD diagnostic kernel/config/map
already produced by the fail-closed `SD_GL9755=1` profile, the proven PCIe m1n1
prefix, the corrected DTB, and repair initramfs v2. Two independent compositions
are byte-identical and strict verification passes:

```text
97a304880e35e268e846273c23ed38bddf1a837ca431590a855e03e56d5e8c9f  m1n1-sdroot-hardened.bin
bd3dd526446b90697e6e2f5bc832bd839521aa89e4d820d49ae5914e0af9dc0d  Image-sd-gl9755
3ba5ba3af18a623a00980c853a69515d3f01d34c541fc9799e49cf2ac95f5509  System.map-sd-gl9755
5b1ced2f0b3d61e9ef4841fcad691db42c1ee0f63fef366231cbb12b2e3bf918  config-sd-gl9755
8fa32648489aeb4dac97e39dcf932121706b05b264bffd58bac26511059a9648  Image-sd-gl9755.raw-object.gz
a013b220f350691ff5f8307280001f1e443c59c001f372f57d6062d7d220561c  m1n1-sdroot-repair-v2.build1.bin
a013b220f350691ff5f8307280001f1e443c59c001f372f57d6062d7d220561c  m1n1-sdroot-repair-v2.build2.bin
```

Strict-verifier facts: 36,945,920 bytes (2,255 × 16 KiB), entry `0x800`,
16 KiB kernel pages, exact bootargs, zero-only terminator/remainder, and runtime
payload reserve 106,289,142 bytes.

## Remaining gate

Do not run ticket 215 from the old hashes. Independently review the v2 sources,
DTB decompilation, member hashes, strict-verifier output, and automatic-only
repair boundary before setting `runnable=true`. The existing CJ approval covers
the repair objective, but the corrected artifact hash must be acknowledged at
queue approval/run time.
