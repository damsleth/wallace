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

### Resolved: `mtdblock0`/`mtdblock1` are m1n1's own debug nodes

`cat /proc/mtd` on the running machine:

```
dev:    size   erasesize  name
mtd0: 00004000 00004000 "m1n1_stage2.log"
mtd1: 00094000 00004000 "adt"
```

Not flash, not storage — **m1n1's stage2 log buffer (16 KiB) and a copy of the Apple Device Tree
(0x94000 = 592 KiB)**, RAM-backed and read-only. Sizes match `/proc/partitions` exactly (16 and 592
1-KiB blocks), and `0x94000` is precisely the ADT size the proxy reports (`Fetching ADT (0x00094000
bytes)`). `erasesize` is `0x4000` — the 16 KiB native page size.

This also explains the apparent contradiction with the DTB: **m1n1 patches these nodes into the DTB
at boot**, so they exist only in the live tree, never in the on-disk `2782b922`. They were invisible
on the proven 4 KiB diet kernel simply because it has no MTD subsystem to expose them — DIET_CAPABLE
enabling `MTD`/`MTD_BLOCK` is what made them appear.

**The storage-disabled premise is intact**: no persistent storage is present, claimed, or touched.
Ticket 150 closed as benign; `MTD_BLOCK` is worth keeping, since it makes the m1n1 stage2 log
readable from Linux userspace.

## Consequences

- **147 → passed.** The 16 KiB page size is not a boot blocker on T6040.
- **149 (ramroot ext4) → unblocked.** A failure there can now be attributed to the ext4/`ram0` root
  path rather than to the kernel. Its `ram0` is already proven present at 512 MiB, and note its
  bootargs request `ramdisk_size=65536` (64 MiB) against a 64 MiB image.
- **148 (dwm)** was never gated by this: it uses the proven 4 KiB kernel `efba5999`.

## Two independent 16 KiB facts — do not conflate

Both involve 16 KiB because 16 KiB is the Apple Silicon native page size. That shared cause is the
*only* thing they share; they constrain different things and neither supersedes the other.

| | What it constrains | Status |
|---|---|---|
| **Enrolled object size alignment** (root-caused 2026-07-25) | the **total byte length of an enrolled raw boot object** must be a whole multiple of 16 KiB (`0x4000`), or iBoot never enters m1n1 and the machine resets ~5 s × 5 | **STILL REQUIRED — unchanged by 147** |
| **Kernel page size** (ticket 147) | whether the kernel is built `ARM64_4K_PAGES` or `ARM64_16K_PAGES` (the MMU granule; `PCIE_APPLE` forces 16 KiB) | 16 KiB now proven to boot |

147 says nothing about the alignment rule, and could not: it was a **tethered chainload**, which
hands the object to `chainload.py` and **bypasses iBoot entirely** — the alignment requirement is an
iBoot load-path constraint that only applies to *enrolled* objects. The smoke object happens to be
aligned anyway (909 × 16 KiB), so it is enrollment-ready as-is.

`scripts/t6040-build-raw-object.py` pads to alignment automatically and
`scripts/t6040-raw-object-verify.py` hard-fails on a misaligned total, so the rule is enforced
mechanically rather than remembered.
