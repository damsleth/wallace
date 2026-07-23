# T6040 J614s trackpad firmware provisioning

Date: 2026-07-23  
Offline ticket: 016  
Result: **complete; paired HIDF blob staged host-locally**

## Source and identity

The target ESP corpus was not mounted, but the canonical paired Apple restore
image used by ticket 014 contains an exact J614s customer identity:

- product: macOS 26.5.2, build 25F84;
- device class: `j614sap` (Mac16,8 / J614s);
- IPSW size: 19,769,902,281 bytes;
- `BuildManifest.plist` SHA-256:
  `a6e764ca158e10ea2ace9b74701f445eefbf012c9cdb5aaa616aa10a0b5197ef`;
- manifest key: `Multitouch`;
- member: `Firmware/J614s_Multitouch.im4p`;
- flags: FUD firmware, not loaded by iBoot or iBoot stage 1.

The extraction therefore uses the board-specific J614s payload. No firmware
from another machine or board was substituted.

## Reproducible extraction

`scripts/t6040-extract-trackpad-firmware.py` pins the Apple IPSW URL, byte
size, product/build, manifest hash, device class, and member path. It uses
asahi-installer commit `c53d66dc71937efa2530d4323c81addaebb5a09b` for
`URLCache` ranged ZIP access and the unmodified `MultitouchFWCollection`
conversion.

The script:

1. downloads only ZIP ranges needed for the manifest and 110,787-byte member;
2. lets `zipfile` verify the member CRC;
3. selects exactly one J614s customer/erase identity;
4. converts `Multitouch.im4p` to `apple/tpmtfw-j614s.bin`;
5. validates HIDF magic, version, header/payload bounds, and interface offset;
6. atomically stages the raw member, output, and JSON provenance under
   `/private/tmp/t6040-vendorfw/`.

Invocation:

```sh
scripts/t6040-extract-trackpad-firmware.py \
    --asahi-installer-src /private/tmp/asahi-installer/src
```

Two independent invocations produced the same output.

## Exact host-local artifacts

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `scripts/t6040-extract-trackpad-firmware.py` | — | `c73dcb1b1c5fe318a6785364d072d4fcca636c2eb35b36b837fee23a6fee0d63` |
| `raw-fud/J614s_Multitouch.im4p` | 110,787 | `4f06afea3e412010fc56ed7dc1214d62fa48b400dbf4f75e261f14e8afe00bf4` |
| `vendorfw/apple/tpmtfw-j614s.bin` | 79,960 | `a1f4131d0cb7caf6fa15b19f47725458a6d7b0e3a34f15169339d5541663d9e2` |

HIDF metadata:

```text
version=1
header_size=32
data_size=79928
interface_offset=79465
```

The proprietary `.im4p` and `.bin` remain host-local and are not committed.
Their durable Git record is the pinned extractor, provenance, sizes, and
hashes.

## Initramfs integration check

The existing guarded packer accepted the blob:

```sh
TRACKPAD_FIRMWARE=/private/tmp/t6040-vendorfw/vendorfw/apple/tpmtfw-j614s.bin \
DEST=/Users/damsleth/Code/linux-build-out/initramfs-dcuart-trackpad.cpio.gz \
    scripts/t6040-make-initramfs.sh
```

The resulting integration-test initramfs is 1,047,502 bytes with SHA-256
`6d1fa398eb46ac63719873f5855963939cb5e7fd740a49d0e1bfd62c47084498`.
The embedded `/lib/firmware/apple/tpmtfw-j614s.bin` byte-matches
`a1f4131d...`; `gzip -t` passes.

This integration-test archive is not yet ticket 004's live artifact. Ticket
004 still needs the exact trackpad-loader kernel/DT rebuilt and hashed, a
firmware-bearing initramfs packaged against that manifest, independent review,
and an updated no-PMU-write preflight before it becomes runnable.
