# J614s paired firmware corpus

Date: 2026-07-24
Ticket: 030
Scope: host-only restore extraction; no rig, target write, or proprietary Git data

## Result

The complete **restore-recoverable** Mac16,8/J614s firmware slice from the
paired macOS 26.5.2 build 25F84 is staged outside Git at:

```text
/private/tmp/t6040-paired-fw-25F84/
```

It contains:

- 22 Linux-ready `vendorfw/` files: 14 BCM4388 `apple,mriya` WiFi/BT files,
  the J614s trackpad HIDF blob, six ISP setfiles, and the kernel-embedded
  ASMedia ASM2214A firmware;
- the five J614s FUD objects that the upstream installer contract selects
  because they are not loaded by iBoot: DCP, SPTM, TXM, InputDevice, and
  Multitouch;
- all 72 raw C0/C2 `mriya` WiFi inputs, including `.pcfb` and `.man` files;
- both USI and AMKOR raw Bluetooth pairs;
- the exact `appleh13camerad` and J614s kernelcache IM4P used for extraction;
- `provenance.json`, a complete `SHA256SUMS`, and one deterministic read-only
  raw-input archive.

| Artifact | Size | SHA-256 |
|---|---:|---|
| `j614s-25F84-raw-firmware.tar.gz` | 50,598,890 | `cb7a4ee2e3a7660c9745b3daff6cdd1da4f1875109d5bc170591fe272b1e639a` |
| `SHA256SUMS` | 12,381 | `b137dcdaf4b5238e6bb4d692b03a3a799597f1ffd536f1f986fdc0963b387cd8` |

The archive is mode `0444`. A second clean build produced the identical
archive hash and `cmp` passed. `shasum -a 256 -c SHA256SUMS` passed for every
raw input, generated output, archive, and provenance record. The builder also
refuses an existing output directory.

No proprietary bytes are present in this repository.

## Pinned provenance

| Input | Identity |
|---|---|
| Restore | `UniversalMac_26.5.2_25F84_Restore.ipsw`, 19,769,902,281 bytes |
| BuildManifest | `a6e764ca158e10ea2ace9b74701f445eefbf012c9cdb5aaa616aa10a0b5197ef` |
| Device identity | `j614sap`, `Erase`, `macOS Customer` |
| BaseSystem AEA | `fe56fcb5a0aa2e0214dbe69f108ed35670bf33d32fdc346c6efb1784cf7705cd` |
| Decrypted BaseSystem | `48067a9bfc7714bde6e61223399bff2aa7bd1fe1b2c1f24c86d455ea801b1301` |
| Kernelcache IM4P | `4cc018b4ab925d879a0f039bf1f83cdbd11dc0bd906910afd1f9d15befabad1b` |
| asahi-installer | `c53d66dc71937efa2530d4323c81addaebb5a09b` |

The script range-reads only the five required FUD members from the pinned
IPSW. It requires and hashes the already authenticated/decrypted BaseSystem
and exact kernelcache, validates the restore identity, and aborts if the
manifest-selected FUD set changes.

## Exact non-iBoot FUD set

| Manifest key | Member | SHA-256 |
|---|---|---|
| `Ap,DCP2` | `Firmware/dcp/t604xdcp.im4p` | `2cf904473f6b1a165d7ec7e57845f3c96ac1ac690411c860e031d9c3143361b2` |
| `Ap,SecurePageTableMonitor` | `Firmware/sptm.t6041.release.im4p` | `f78979b6cd9d7c0c5d13abf58229ec1ffc489751324708e1536cfba399ea4938` |
| `Ap,TrustedExecutionMonitor` | `Firmware/txm.macosx.release.im4p` | `6d26ef9195becf28c6a0eed7ee35cf214de45807e5fefcb5ad0c1ab441d0995b` |
| `InputDevice` | `Firmware/J614S_InputDevice.im4p` | `e62bd25ed8d61d282a758d34211ca9fa1a0e9c56010ae6fbb6862e1b43d081e0` |
| `Multitouch` | `Firmware/J614s_Multitouch.im4p` | `4f06afea3e412010fc56ed7dc1214d62fa48b400dbf4f75e261f14e8afe00bf4` |

iBoot-loaded ANE, AOP, AVE, PMC, GFX, ISP, MTP, PMP, and SIO payloads are
intentionally excluded. That matches upstream `collect_firmware()`: these
payloads are supplied by the boot firmware rather than an
`all_firmware.tar.gz` fallback. DCP, SPTM, TXM, and InputDevice are preserved
raw because current `asahi_firmware` has no Linux `vendorfw` conversion for
them.

## Linux-ready output

The unmodified collectors generate exactly:

- 12 WiFi files for BCM4388 C0/C2;
- two USI Bluetooth files for BCM4388 C2;
- `apple/tpmtfw-j614s.bin`
  (`a1f4131d0cb7caf6fa15b19f47725458a6d7b0e3a34f15169339d5541663d9e2`);
- all six known ISP setfiles from the 25F84 `appleh13camerad`;
- `asmedia/asm2214a-apple.bin`
  (`691bb72aa21fe609fa7565c7f4478b078bb8c4161edd441326ce0c008e5f74bd`).

The script asserts the exact path/hash map for all 22 files. Current
`asahi_firmware` still cannot name AMKOR Bluetooth output and does not consume
WiFi `.pcfb`/`.man`; those inputs remain in the canonical raw archive.

Use the direct tree with existing builders:

```sh
VENDORFW_DIR=/private/tmp/t6040-paired-fw-25F84/vendorfw \
    scripts/t6040-make-initramfs.sh
```

The Alpine USB-root image does not need this tree for its built-in boot path,
but it can be supplied to a later rootfs build with
`--firmware /private/tmp/t6040-paired-fw-25F84/vendorfw`.

## Rebuild

With the pinned BaseSystem mounted read-only:

```sh
scripts/t6040-build-paired-firmware-corpus.py \
  --base-system /private/tmp/t6040-basesystem-mnt \
  --base-system-aea /private/tmp/t6040-ipsw/022-21678-099.dmg.aea \
  --base-system-dmg /private/tmp/t6040-ipsw/022-21678-099.dmg \
  --kernelcache /private/tmp/kernelcache.release.mac16j.im4p \
  --asahi-installer /private/tmp/asahi-installer \
  --output /private/tmp/t6040-paired-fw-25F84
```

## Deliberate split: machine-private ALS

Ambient-light calibration is not recoverable from the restore image. The
installer reads `CalibrationData` from the live machine's `ioreg` and copies
`HmCA*` FactoryData from that same installation. Running the collector on this
M1 would create the wrong machine's blob.

Ticket 087 therefore owns a read-only J614s macOS capture of
`apple/aop-als-cal.bin` plus matching `HmCA*` data. ALS is not a boot, input,
display-console, USB-root, or B0 dependency, so this split does not reduce the
bootable corpus above.
