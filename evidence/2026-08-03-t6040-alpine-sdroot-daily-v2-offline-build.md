# T6040 Alpine SD-root daily v2 — offline build

Date: 2026-08-03

Rig use: **none**. Claude held the rig lease while this object was built. This
work compiled ordinary files in the build container and did not mount or write
the SD card, alter a boot partition, or enroll a boot object.

## Outcome

`m1n1-alpine-sdroot-daily-v2.bin` is a reproducible one-core Alpine SD-root
boot object for the existing `SD64/wallace-root.img` installation. Two
independent kernel builds and two independent object compositions are
byte-identical, and both complete objects pass the strict raw-object verifier.

The canonical host artifact is:

```text
bdd8cc865081a2041e587d1bb30495ca0bb65da305552dd4b6679cba66c5f5a5  /Users/damsleth/Code/linux-build-out/m1n1-alpine-sdroot-daily-v2.bin
```

This object has not been booted. Ticket 215 must repair and prove the nested
filesystems clean before ticket 216 may test it. The maintainer will separately
create the third boot partition and install the reviewed object.

## Reproducible kernel and DTB

Both kernel builds used Linux `wallace/t6040-bringup` at
`1c1acd21b13a`, the immutable build-script snapshot
`dae0ae220f36b2bfb8bcd502411aafd6f590d73794d49ee8ae4bf9272c04a489`,
and this feature set:

```text
DOCKCHANNEL=1 DOCKCHANNEL_NBCON=1 MACSMC=1 HID_TYPE_FIX=1
T6040_PPP=1 WIFI=1 PCIE=1 CPUFREQ=1
```

No threaded-NVMe, trackpad-firmware, AF/dirty-bit, or TLB-range experiment was
selected. The resulting `nvme-apple` source calls `devm_request_irq`, not
`devm_request_threaded_irq`. The config has normal `ARM64_HW_AFDBM=y` and
`ARM64_TLB_RANGE=y`; `HID_MAGICMOUSE` is disabled so the rejected trackpad
upload is not attempted automatically.

```text
3e129466d612d176b0d52ddd2a004ed89a920b8e2f3a38f39504cda4059d04f2  Image-alpine-sdroot-daily-v2.build1
3e129466d612d176b0d52ddd2a004ed89a920b8e2f3a38f39504cda4059d04f2  Image-alpine-sdroot-daily-v2.build2
3045396bd8ac86ff9c4073496818f74dfe1cdc4939a31cf963aff52112fc7fa6  System.map-alpine-sdroot-daily-v2.build1
3045396bd8ac86ff9c4073496818f74dfe1cdc4939a31cf963aff52112fc7fa6  System.map-alpine-sdroot-daily-v2.build2
251f19e8d01e07ba0a11f3db370df7760ce00cc686e0227268b94bbc5b660125  config-alpine-sdroot-daily-v2.build1
251f19e8d01e07ba0a11f3db370df7760ce00cc686e0227268b94bbc5b660125  config-alpine-sdroot-daily-v2.build2
c5c3b4c38b24748f95e06fd3cc39b348326783a58feb7029d9273a5b23dd7e72  t6040-j614s-dcuart-wifi-cpufreq-sdroot.build1.dtb
c5c3b4c38b24748f95e06fd3cc39b348326783a58feb7029d9273a5b23dd7e72  t6040-j614s-dcuart-wifi-cpufreq-sdroot.build2.dtb
0706d4222baa65584fd7a719be69c2f3f35c31b903226434e9ab4836f1b3d29d  dts/t6040-j614s-dcuart-wifi-cpufreq-sdroot.dts
```

The compiled DTB retains the proven panel, keyboard, DockChannel console,
Wi-Fi/BT, GL9755 SD reader, cpufreq, and SMC GPIO endpoints. The ANS mailbox,
SART, and NVMe nodes are disabled so the known first-I/O-CQ-wrap assert cannot
take down every SD-root boot.

The inherited Wi-Fi DT enabled `nub-spmi0` for RTC/reboot nvmem. Current
`docs/SPMI_SAFETY.md` excludes the system PMU buses, so this daily overlay also
disables `nub_spmi0`, `smc_rtc`, and `smc_reboot`. SMC remains enabled only for
the already-approved `gP13` and `gP19` endpoint-power GPIOs. Consequently the
PID-1 shutdown path can cleanly unmount ext4 and exFAT, but its final hardware
reboot/poweroff is expected to remain a no-op until a separately reviewed
reboot DT resolves that policy boundary.

## Early firmware and initramfs identity gates

The first hardened rebuild accidentally used the 966 KiB console-only base and
omitted Wi-Fi/BT firmware. That artifact is withdrawn. The corrected builder
pins the proven SD-root firmware base and verifies the paired 25F84 Wi-Fi and
Bluetooth blobs before packing. This matters because both drivers request
firmware before `switch_root`; files only on the Alpine root arrive too late.

```text
59764944c4aad38189df5ee05a190c5ce60fd44727482105e4f20df7d8c7edc1  initramfs-sdroot-wifi-base-59764944.cpio.gz
6b00789cd75c87a19504ac62006151ab5dea1637d01e6cb3bf8b819efe7e5773  scripts/t6040-build-sdroot-initramfs.sh
d0f55c5635ab8e65b25e64773223a2c6bc0923cca13bd88b2f4f4136da5092ff  scripts/t6040-sdroot-init
afb2433edf6c81de760e625c3a4132a3e2b82fd258aa3ce79398b66cbd13ee2f  scripts/t6040-sdroot-shutdown
7fe674e28a152ef0abda86525487c271b7bea7d8a9b481baba5faeb7f2175ec3  initramfs-sdroot-daily-v2.build1.cpio.gz
7fe674e28a152ef0abda86525487c271b7bea7d8a9b481baba5faeb7f2175ec3  initramfs-sdroot-daily-v2.build2.cpio.gz
```

Before any writable mount, `/init` proves the exact GL9755 PCI identity,
`sdhci-pci` binding and IOMMU group, `mmcblk0` ancestry, `SD64` label and exFAT
type, clean exFAT volume flag, exact 6 GiB image size, ext4 UUID, and clean ext4
superblock state through a read-only attachment. Only then does it reopen the
same objects read-write and switch to Alpine.

## Complete object verification

The exact boot arguments are:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel console=ttydc0 rdinit=/init
```

```text
97a304880e35e268e846273c23ed38bddf1a837ca431590a855e03e56d5e8c9f  m1n1-sdroot-hardened.bin
b5d33b3335475e36ac14158fc01514e506956fb1448c2296cf84890f5d8b7b27  Image-alpine-sdroot-daily-v2.raw-object.build1.gz
b5d33b3335475e36ac14158fc01514e506956fb1448c2296cf84890f5d8b7b27  Image-alpine-sdroot-daily-v2.raw-object.build2.gz
bdd8cc865081a2041e587d1bb30495ca0bb65da305552dd4b6679cba66c5f5a5  m1n1-alpine-sdroot-daily-v2.build1.bin
bdd8cc865081a2041e587d1bb30495ca0bb65da305552dd4b6679cba66c5f5a5  m1n1-alpine-sdroot-daily-v2.build2.bin
```

Strict-verifier facts: 24,084,480 bytes (1,470 × 16 KiB), raw entry `0x800`,
16 KiB kernel pages, exact bootargs, exact component bytes, zero-only
terminator/remainder, and runtime payload reserve 66,832,697 bytes.

## Remaining gate

Do not install or boot this object until ticket 215 has repaired the existing
dirty filesystems and an independent reviewer has checked the DTB status gates,
firmware manifest, init/shutdown mount topology, complete-object hash, and
strict-verifier result. Ticket 216 remains non-runnable.
