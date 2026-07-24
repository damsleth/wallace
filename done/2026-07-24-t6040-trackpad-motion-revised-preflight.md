# T6040 J614s revised trackpad-motion candidate

Date: 2026-07-24

Tickets: 125 (offline, complete after review), 126 (live, proposed and not
approved)

State: **offline candidate byte-reproduced and independently reviewed PASS**.
This does not approve a live run. Ticket 126 still requires fresh manual
approval, an explicit exception for the exact volatile runtime firmware upload,
and an attended finger-motion interval.

## Correction and exact delta

The retired ticket-004 Image could not register the trackpad: it omitted the
already-proven DockChannel `hid->type` assignment and built
`HID_MULTITOUCH=m` while its RAM root contained no modules. This replacement:

- applies `patches/t6040-dockchannel-hid-type.patch`;
- builds `CONFIG_HID_MULTITOUCH=y`; and
- otherwise retains the exact ticket-004 DTB, initramfs, paired J614s HIDF,
  reporter, and PCIe-write-free m1n1.

Independent comparison against `/build/linux-trackpad-004-codex` found exactly
the intended six-line HID-type source addition and the single config change
from `m` to `y`. The DTB and initramfs remain byte-identical.

## Exact artifacts

| Artifact | Size | SHA-256 |
|---|---:|---|
| `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | 1,097,728 | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `Image-trackpad-motion` | 53,303,808 | `446eeb2eb28d85ec29c327d52b55c223a928e4cccbd5fcc2d00ed70e98e3a490` |
| `System.map-trackpad-motion` | 10,008,784 | `82f71c0e311e9acd20394e6b2054443b2add6f6ce52a6ddc34e24295eb5e4e2a` |
| `config-trackpad-motion` | 322,007 | `0769da6d1f6145c236ffbe044480ce94a2b7c7fd7aa057be09e71da49012e5d3` |
| `t6040-j614s-dcuart-trackpad-motion.dtb` | 51,659 | `2782b92237c35c8950212207391c3ae28c44b6b9c635b2e864c5748a77bb3cce` |
| `initramfs-dcuart-trackpad-004.cpio.gz` | 1,047,577 | `3a47c95d629def71bedb3cdba4dbf3390575015b9f0d08d86154d2767d83d6ae` |
| embedded `apple/tpmtfw-j614s.bin` | 79,960 | `a1f4131d0cb7caf6fa15b19f47725458a6d7b0e3a34f15169339d5541663d9e2` |

Linux source is commit
`246843ff67a85b032a9da558770979b86b430945`. The applied working-tree diff
hashes to
`099fa5f890daff459991ecc1d4c663a9a862acd8f66d03c62f945458b46ee578`.

Relevant source identities:

| Source | SHA-256 |
|---|---|
| `scripts/t6040-kbuild.sh` | `d2cc6afbced04d235bce296cb2289c97052450794763acabfd777a3b0d65eeb6` |
| `patches/t6040-dockchannel-poll.patch` | `627d0805f103f56ad20cc24785d4e747740e774c1660604611298adf6bcd0e63` |
| `patches/t6040-dockchannel-fixes.patch` | `814d085f68d1fd5501abbb53e944b460bdda2dec51292cedca6fb66bdc364cd4` |
| `patches/t6040-dockchannel-hid-type.patch` | `8692c4554f2db232fa57ee4fbc2e3ac529b1a8d36c44629612a478c30d8a455c` |
| `patches/t6040-dockchannel-trackpad-fw.patch` | `f7a3eb883c0d393e899128c91740f7405b6e9626ac58746ae37562032732a779` |
| `scripts/t6040-init-trackpad-motion` | `400ab9bed41dd0e717c435e2d2211805196f68989942773adc3c837039c72676` |

## Reproducibility result

Two independently cleaned case-sensitive build directories,
`/build/linux-trackpad-motion-v2a` and `v2b`, used:

```text
DOCKCHANNEL=1 HID_TYPE_FIX=1 TRACKPAD_MOTION=1 \
BUILD_DIR=<independent-directory> /out/t6040-kbuild.sh image
```

The harness pins the source commit timestamp, build user/host/version, and
maps both C and assembly debug paths to `/build/linux`. The first diagnostic
pair exposed two directory-derived 20-byte build IDs; adding the assembly
prefix map rebuilt every assembly object and both final links. The final
Image, System.map, config, and DTB pass byte-for-byte `cmp` across the two
directories. The retained final copies are unambiguously named
`*-trackpad-motion-final-run1*` and `*-trackpad-motion-final-run2*`; the earlier
diagnostic pair is labeled `pre-kaflags` and is not a ticket artifact.

## Independent safety and functional review

The reviewer verified:

- the type patch assigns `SPI_MOUSE` to multi-touch and `SPI_KEYBOARD` to the
  keyboard before HID registration;
- DockChannel HID, input/evdev, `hid-multitouch`, and the reporter are built in
  and the reporter opens every event node for at most 12 seconds;
- the initramfs has 23 entries, no modules, device nodes, USB/storage/SPMI/
  GPIO/PMU payloads, and its `/init` and sole firmware match the pinned bytes;
- the DTB enables only the proven MTP/DART/DockChannel/HID path plus DCUART;
  all three USB/DWC3 paths and ANS/SART/NVMe are disabled;
- the paired firmware path validates the HIDF wrapper, payload bounds, and
  interface offset, copies only the exact 79,928-byte payload to coherent DMA,
  and sends the known bounded runtime firmware/interface-reset messages; and
- no GPIO, SMC/PMU, SPMI, NVRAM, flash, arbitrary-firmware, storage, or USB-host
  path is reachable.

The config retains generic defconfig USB/storage symbols, some as modules.
That is not a reachable live path: the initramfs has no modules and the exact
DTB disables every corresponding controller. Documentation therefore says
“no reachable path,” not “symbols absent.”

## Live gate

Ticket 126 remains **proposed and unapproved**. A future one-shot run must:

1. receive fresh manual ticket approval;
2. record an explicit exception for exactly the paired `a1f4131d...` volatile,
   non-persistent HIDF upload into coherent DMA and the known interface reset;
3. have the maintainer present to move a finger during the bounded interval;
4. use the exact artifacts above, the rig lease, and the healthy-proxy
   stop/recovery contract.

That exception would not authorize flash/NVM, arbitrary firmware, another
board blob, GPIO/PMU reset, SPMI, or any other write. Until all four gates are
met, preserve the healthy `Running proxy` state and do not run ticket 126.
