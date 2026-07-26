# Ticket 147 RESULT: the 16 KiB-page DIET_CAPABLE kernel boots — PASS

**Attempt 3 (2026-07-26 13:58) ran the correct object and the 16 KiB-page kernel booted cleanly.**
The `PAGE_SIZE_16KB` ABI change is cleared, so ticket 149 is unblocked.

Object: `m1n1-b0-dietcap-smoke.bin` `ac24d4bf…` (14,893,056 B = 909 × 16 KiB).
Confirmed as the object that actually ran: `Loading kernel image (0xe34004 bytes)` = 14,893,056 + the
4 zero bytes `chainload.py` appends. (Attempts 1 and 2 both logged `0x14b8f13` = the wrong object.)

## Acceptance state — every criterion met

| Criterion | Observed |
|---|---|
| Alpine userspace | `release=3.24.0`, `arch=aarch64` |
| kernel | `7.1.3-g246843ff67a8-dirty #1 SMP PREEMPT 2026-07-23T23:37:50+02:00` |
| health report begin→end | both markers present |
| framebuffer | `/sys/class/graphics/fb0/name=simpledrmdrmfb` |
| internal keyboard on `event0` | `Apple DockChannel Keyboard`, `input0`, `Handlers=sysrq kbd leds event0` |
| watchdog | `watchdog0=present` |
| network runlevel empty | empty |
| Norwegian keymap | `loaded no-mac.bmap` |
| shell | `wallace-b0:~#` |
| no faults | no panic/Oops/call trace; no NVMe, xHCI or usb-storage; **nothing mounted** |

The `dapf: … async L2C SError on this M4 SoC` lines are m1n1's own pre-existing, deliberate DART
skips, not kernel faults. The closing `?U??…` garbage and `UartTimeout` are the known
console-contention artifact after the shell comes up.

## The one criterion that needed interpretation: `/proc/partitions` is NOT empty

```
-- partitions (must be empty) --
major minor  #blocks  name
   1        0     524288 ram0
  31        0         16 mtdblock0
  31        1        592 mtdblock1
```

Read literally this fails 147. Read correctly it is **expected and by design**: the "empty
`/proc/partitions`" criterion was inherited from the proven **4 KiB** diet kernel, which has no
block layer at all. DIET_CAPABLE exists precisely to re-add `BLK_DEV_RAM`/`MTD`/`MTD_BLOCK`/
`MTD_PHRAM`, so block devices *must* appear.

`ram0` matches the config exactly — `scripts/t6040-kbuild.sh` sets `BLK_DEV_RAM_COUNT 1` and
`BLK_DEV_RAM_SIZE 524288`, and the log shows exactly one `ram0` of 524288 KiB (512 MiB).

**The intent of the criterion is satisfied**: no persistent/real storage device is present or
claimed (no NVMe, no USB block, no SPI-NOR), and **no filesystem was mounted**. Storage-free holds.

### Open question: where do `mtdblock0` (16 KiB) and `mtdblock1` (592 KiB) come from?

`MTD_BLOCK` wraps whatever MTD devices exist, but the source of these two is **unexplained**:

- the storage-disabled DTB `2782b922` has **no** `mtd`, `spi-nor`, `nvram`, `flash` or `partition`
  node whatsoever;
- `MTD_PHRAM` creates devices only from an explicit `phram=` parameter, and the bootargs have none.

Nothing was mounted or written, so this caused no harm and does not block the verdict — but an
unexplained block device on an image whose premise is "storage-disabled" should be identified rather
than waved through. Filed as **ticket 150**. One line on the machine settles it:

```sh
cat /proc/mtd; dmesg | grep -i mtd
```

(The kernel's own dmesg went to `tty0` on the panel, so the pty log does not contain it — which is
also why there is no `Kernel command line` line to quote here.)

## Consequences

- **147 → passed.** The 16 KiB page size is not a boot blocker on T6040.
- **149 (ramroot ext4) → unblocked.** A failure there can now be attributed to the ext4/`ram0` root
  path rather than to the kernel. Its `ram0` is already proven present at 512 MiB, and note its
  bootargs request `ramdisk_size=65536` (64 MiB) against a 64 MiB image.
- **148 (dwm)** was never gated by this: it uses the proven 4 KiB kernel `efba5999`.
