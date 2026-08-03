# T6040 J614s trackpad motion preflight

Date: 2026-07-24

Rig ticket: 004

State: **retired unrun after independent functional NO-GO**. This document
preserves the exact historical bytes and procedure; replacement work is
tickets 125/126. Offline 125 is now complete and reviewed; live 126 remains
proposed and unapproved. See
`evidence/2026-07-24-t6040-trackpad-motion-crossreview.md` and
`evidence/2026-07-24-t6040-trackpad-motion-revised-preflight.md`.

## Purpose

Retest the J614s internal trackpad with its exact paired 25F84 HIDF firmware.
The initramfs opens every registered input event node for a bounded 12 seconds,
asks the maintainer to move a finger on the trackpad, and emits registration,
event-byte, and relevant dmesg evidence over ttydc0 TX. It does not depend on
ttydc0 RX.

This is not a GPIO-reset experiment. The kernel patch contains no GPIO proxy
path and therefore cannot issue the legacy `gp1c` SMC/PMU pulse. Any indication
that the device requires that reset is a stop result, not authorization to add
or exercise it.

## Exact artifacts

| Artifact | Size | SHA-256 |
|---|---:|---|
| `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | 1,097,728 | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `Image-trackpad-004` | 53,303,808 | `86e031dba708ad21d1a393e0cc4da97ddb3110f9bfd28cdc86398c859d441112` |
| `System.map-trackpad-004` | 10,002,321 | `76bd9cb69e89967344de01e04fc9507fa40b947b81b3d8299fb8b690c2fc86fc` |
| `t6040-j614s-dcuart-trackpad-004.dtb` | 51,659 | `2782b92237c35c8950212207391c3ae28c44b6b9c635b2e864c5748a77bb3cce` |
| `config-trackpad-004` | 322,007 | `27c615803298a366e93c1858caaf4ad6ce95db7dfcbff51ecd404d980f6f4228` |
| `initramfs-dcuart-trackpad-004.cpio.gz` | 1,047,577 | `3a47c95d629def71bedb3cdba4dbf3390575015b9f0d08d86154d2767d83d6ae` |
| embedded `apple/tpmtfw-j614s.bin` | 79,960 | `a1f4131d0cb7caf6fa15b19f47725458a6d7b0e3a34f15169339d5541663d9e2` |

The m1n1 binary is the pinned PCIe-write-free upper-guard build, not the local
op-115 candidate.

## Build and host verification

The kernel was built twice from a fresh, case-sensitive container clone of
Linux commit `246843ff67a85b032a9da558770979b86b430945` with:

```text
DOCKCHANNEL=1 /out/t6040-kbuild.sh image
```

Both builds produced byte-identical Image and DTB artifacts. The build imports
the pinned DockChannel series, applies the normal poll-mode transport patch and
the bounded HIDF firmware loader, and does not enable the RX-rearm, HID trace,
USB-host, NVMe, PCIe, gadget, SMP-test, or cpufreq-test modes.

Relevant source identities:

| Source | SHA-256 |
|---|---|
| `scripts/t6040-kbuild.sh` | `7f938980410f65a4d22293d3dbd97e6227858d6b7370a790f8384564f37d94e4` |
| `patches/t6040-dockchannel-poll.patch` | `627d0805f103f56ad20cc24785d4e747740e774c1660604611298adf6bcd0e63` |
| `patches/t6040-dockchannel-fixes.patch` | `814d085f68d1fd5501abbb53e944b460bdda2dec51292cedca6fb66bdc364cd4` |
| `patches/t6040-dockchannel-trackpad-fw.patch` | `f7a3eb883c0d393e899128c91740f7405b6e9626ac58746ae37562032732a779` |
| `scripts/t6040-init-trackpad-motion` | `400ab9bed41dd0e717c435e2d2211805196f68989942773adc3c837039c72676` |
| `scripts/t6040-make-initramfs.sh` | `e6b1b9c00146364cb715e755e29f6a5c14b1e81729215ac0b1a365309b5cac98` |
| `scripts/reproducible-newc.py` | `b0143bc003c1f8da90908d8d1a3ce7346a99d9441f6011424ce2e799a766a77f` |

The initramfs was built twice in fresh temporary trees, two seconds apart, and
the gzip files byte-match. Its archive passes `gzip -t` and `bsdtar` extraction;
`/init` and the embedded firmware byte-match their pinned sources. The base
archive has no hardlinked regular files or special nodes, so replacing BSD
cpio's nondeterministic host-inode output with the project newc writer changes
neither required link identity nor device-node semantics.

Static DT verification establishes:

- MTP ASC, DART, DockChannel, and HID are enabled on the already-proven path;
- `multi-touch` names exactly `apple/tpmtfw-j614s.bin`;
- all three USB controllers and their DARTs are disabled;
- ANS, SART, and NVMe are disabled;
- the DTB byte-matches the storage-disabled ticket-071/074 DTB.

The initramfs mounts only proc, sysfs, and devtmpfs; starts the watchdog; waits
at most 20 seconds for input registration; prints input inventory; reads at
most 32 24-byte chunks per event node for at most 12 seconds; prints at most
the last 120 matching dmesg lines; then emits an end marker and starts the
existing diagnostic shells. It loads no modules and performs no storage,
network, USB, SPMI, PMU, charger, NVRAM, or Boot Policy access.

## Proposed one-shot procedure

Do not run until another onboarded reviewer has checked these exact bytes
against `~/Code/m1n1/AGENTS.md` and recorded PASS. The existing ticket approval
explicitly retained this review gate.

```sh
scripts/rig-lease.sh acquire codex \
    "ticket 004 J614s trackpad motion retest" 1394c345
RIG_AGENT=codex bash scripts/t6040-debugusb-console.sh reboot
RIG_AGENT=codex \
M1N1_BIN=/Users/damsleth/Code/linux-build-out/m1n1-t6040-logbuf-upper-guard-dryrun.bin \
M1N1DEVICE=/tmp/m1n1 IMAGE=Image-trackpad-004 BOOT_WAIT=55 \
KERNEL_LOG_ARGS=ignore_loglevel \
bash scripts/t6040-boot-dcuart.sh \
    t6040-j614s-dcuart-trackpad-004.dtb \
    initramfs-dcuart-trackpad-004.cpio.gz
```

Exact boot arguments:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/init
```

There is no `root=`. The physically attached USB stick remains inert because
every USB controller/DART is disabled, but any USB or storage probe is still an
immediate stop.

When this marker appears on the panel or ttydc0:

```text
TOUCH_TRACKPAD_NOW_FOR_12_SECONDS
```

move one finger across the trackpad until the bounded interval ends. Send no
host command during the capture. Record output from:

```text
=== T6040 TRACKPAD MOTION REPORT START ===
```

through:

```text
=== T6040 TRACKPAD MOTION REPORT END ===
```

Then recover to a stable `Running proxy...`; do not iterate within the lease.

## Pass and stop conditions

Pass requires the paired firmware to load, the multi-touch interface to become
ready, an event node to identify as the DockChannel multi-touch device, and
non-empty bounded event bytes while the finger moves. Keyboard registration,
watchdog, framebuffer, and ttydc0 TX must remain healthy.

Stop immediately on any reset-GPIO request/requirement, SMC/PMU indication,
async SError, DART fault, reset/watchdog loop, USB/ANS/NVMe probe, unexpected
block device, missing report end marker, lost ttydc0 TX, or kernel oops. A
GPIO-reset outcome is recorded as a hard blocker; it must not be followed by a
proxy implementation or PMU write.
