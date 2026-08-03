# T6040 NVMe — paired ANS firmware assert 7454 reverse engineering

Date: 2026-08-03

Rig use: **none**. This is static analysis of the Apple restore image paired
with the firmware already in use on J614s. No hardware, storage, SPMI, PMU,
SMC, NVRAM, or external-posting action was taken.

## Outcome

Assert 7454 is the T604x ANS runtime firmware's reporter for hardware error
status bit 2. It does **not** arise from a firmware comparison between the
host's software CQ head and an expected head. The reporter reads five raw
hardware values and formats them:

| printed field | firmware source |
|---|---|
| `status_reg` | 32-bit read from error block `+0x00` |
| `valid_status` | 32-bit read from error block `+0x08` |
| `err_info_0` | 32-bit read from error block `+0x14` |
| `err_info_1` | 32-bit read from error block `+0x18` |
| `head` for Host I/O | controller register `+0x900c`, masked to 16 bits |

The error block is mapped from physical `0x4dcf4000`, length `0x44`. The
controller block is mapped from physical `0x4dcc0000`, length `0x9400`, so the
printed I/O head comes from physical `0x4dcc900c`.

The firmware finds the least-significant set bit of `status_reg` with
`rbit`/`clz`. Bit 2 selects the CQ-doorbell branch. The field values seen in
the preserved Linux runs therefore mean:

```text
status_reg 0x4       hardware error source bit 2 only
valid_status 0x4     validity bit 2 only
head 15/61/63        low 16 bits of the hardware I/O-CQ register
err_info_0/1         raw hardware error-detail registers
```

The firmware reporter does not further mask or decode `err_info_0` or
`err_info_1`; it loads the full 32-bit registers and passes them to the assert
formatter. Their bit-level meaning is consequently not recoverable from this
handler alone. In particular, the observed pairs `1/0x20000` and
`3/0x40000` must not yet be labelled as queue index, delta, or cause.

This kills one tempting interpretation of the transcript: `head 63` is not a
software value supplied by Linux, and assert 7454 is not itself an off-by-one
comparison in CoastGuard. It is the firmware report of an error already
latched by the ANS hardware block. The host completion/doorbell experiment is
still useful, but it is discriminating what makes hardware latch bit 2 rather
than bypassing a firmware-side head check.

## Exact paired payload

The restore source is the already-pinned Mac16,8 25F84 image:

```text
UniversalMac_26.5.2_25F84_Restore.ipsw
Firmware/ansf.t604x.release.im4p
```

Payload metadata reported by `ipsw img4 im4p info`:

```text
Type:         ansf
Version:      AppleStorageFirmware-2973.120.4~247
Compression:  LZFSE
Uncompressed: 9500384 bytes
```

Hashes:

```text
d8ec13867b531d71fa6f1ea289a7ee36e51b4cad33d082c27ef0b5c69924977a  ansf.t604x.release.im4p
629dd45b16879e817c037a7d823b30c0ad7749b9a576285264ce945a89c4bf67  ansf.t604x.release.bin
```

The extracted payload is a 64-bit arm64e `MH_PRELOAD` Mach-O. All addresses
below are VM/file addresses in that decompressed image.

## Assert path

The exact format string is at `0x2198f1`:

```text
CQ (Host %s) DB error, status_reg: 0x%llx, head: %d, valid_status: 0x%x, err_info_0: 0x%x, err_info_1: 0x%x
```

`0x219e21` is the string `I/O`. The reporter begins at `0x3329c`. Its entry
sequence proves the status selection:

```asm
0x332ac  adrp x8, 0x3bc000
0x332b0  ldr  x9, [x8, 0x3d8]   // mapped error block
0x332b4  ldr  w8, [x9]          // status_reg
0x332b8  ldr  w2, [x9, 8]       // valid_status
0x332bc  rbit w10, w8
0x332c4  clz  w10, w10          // least-significant set-bit index
...
0x33328  cmp  w10, 2
0x3332c  b.eq 0x333a0           // status bit 2: CQ DB error
```

The Host I/O branch at `0x333a0` supplies the five printed values:

```asm
0x333a4  ldr  w10, [x9, 0x14]   // err_info_0
0x333a8  mov  w12, 0x900c       // I/O CQ-head register offset
0x333b0  ldr  w9,  [x9, 0x18]   // err_info_1
0x333b8  ldr  x11, [x11, 0x5f8] // mapped controller base
0x333bc  ldr  w11, [x11, x12]
0x333c4  and  w3, w11, 0xffff   // printed head
0x333cc  mov  w0, 0x1d1e        // 7454, source/assert line
0x333dc  add  x4, x4, 0x8f1     // format string at 0x2198f1
0x333e0  bl   0x23530            // assert/log formatter
```

There is no compare against `w3`, `w10`, or `w9` in this branch. They are
formatter arguments only.

## Register-map provenance

The controller mapping is constructed at `0x2aedc`:

```asm
0x2aee0  mov  x1, 0x0dcc0000
0x2aef0  movk x1, 4, lsl 32      // x1 = 0x4dcc0000
0x2aef8  mov  w2, 0x9400
0x2af00  bl   0xe970             // mapping-wrapper construction
0x2af08  bl   0xe910             // map/activate
```

The wrapper starts at global `0x3bc5f0`; its mapped pointer is the `+8` member
read by the reporter at global `0x3bc5f8`.

Before the error mapping, `x19` is constructed as `0x4dcf4000` at
`0x2ae9c..0x2aeb4`. The wrapper at global `0x3bc3d0` then maps it:

```asm
0x2b10c  adrp x20, 0x3bc000
0x2b110  mov  x1, x19            // 0x4dcf4000
0x2b114  mov  w2, 0x44
0x2b118  add  x20, x20, 0x3d0
0x2b120  bl   0xe970
0x2b128  bl   0xe910
```

The reporter's global `0x3bc3d8` is this wrapper's mapped-pointer member.

## Reproduction commands

These commands download only matching files from the pinned restore rather
than materialising the full IPSW:

```sh
ipsw download ipsw --device Mac16,8 --build 25F84 --macos \
  --pattern '(?i)(ans|nvme|coastguard)' --output /private/tmp/wallace-offline-25F84
ipsw img4 im4p info Firmware/ansf.t604x.release.im4p
ipsw img4 im4p extract --output ansf.t604x.release.bin \
  Firmware/ansf.t604x.release.im4p
shasum -a 256 Firmware/ansf.t604x.release.im4p ansf.t604x.release.bin
r2 -q -a arm -b 64 -m 0 ansf.t604x.release.bin
```

Inside radare2, `psz @ 0x2198f1`, `pd 92 @ 0x3329c`, `pd 24 @ 0x2ae98`, and
`pd 12 @ 0x2b10c` reproduce the strings, branch, and mappings above.

## Consequences and next discriminator

1. Preserve the existing threaded-IRQ experiment as a discriminator, not a
   proposed fix. A pass can implicate execution context, interrupt masking,
   or the additional scheduling delay; it cannot choose among them.
2. Capture all five raw fields on every run. `head` alone is insufficient,
   and a single clean run remains meaningless.
3. If a future hardware transcript can capture the error block before reset,
   preserve the complete `0x44` bytes, not just the three printed registers.
   That requires a separately reviewed rig ticket; this analysis authorises
   no new MMIO read.
4. Search a hardware-register description or another first-party consumer for
   the `+0x14/+0x18` bitfields. The paired runtime firmware treats them as
   opaque, so inventing names from the two observed value pairs would be
   overfitting.
