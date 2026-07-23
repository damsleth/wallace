# T6040 asahi-installer requirements

Date: 2026-07-23  
Ticket: 026  
Scope: upstream requirements only; no APFS, Boot Policy, enrollment, or rig work

## Baseline inspected

| Repository | Commit |
|---|---|
| `AsahiLinux/asahi-installer` | `c53d66dc71937efa2530d4323c81addaebb5a09b` |
| `AsahiLinux/asahi-installer-data` | `072a48f02bc85f5d1894237b703fd9bab98b38a5` |

These were the public branch tips on 2026-07-23. The local J614s evidence uses
the canonical Mac16,8 macOS 26.5.2 / 25F84 restore identity documented in the
trackpad and BCM4388 firmware reports.

## Correction: raw enrollment already exists

The installer does not need a new M4-specific `kmutil` mode. Its current
`src/step2/step2.sh` already runs:

```sh
kmutil configure-boot -c boot.bin --raw --entry-point 2048 \
    --lowest-virtual-address 0 -v "$system_dir"
```

It also runs `bputil -nc` against the new volume group and explains that the
security change is per OS. This matches ticket 080's raw entry and load-address
contract. The missing work is admission, object semantics, and 26.x firmware.

## Requirement 1: admit J614s/T6040 conservatively

The current hard gates stop at M2:

- `CHIP_MIN_VER` has no `0x6040`;
- `DEVICES` has no `j614sap`;
- installer-data offers only firmware versions 12.3, 12.3.1, and 13.5 and has
  no Mac16/T6040-specific package.

The first upstream-shaped change should add:

```text
chip-id     0x6040
device      j614sap
marketing   MacBook Pro (14-inch, M4 Pro, 2024), Mac16,8
minimum OS  26.x, matching the supported restore/stub identity
status      expert-only until the B0 artifact and rollback flow pass
```

Do not imply full distro support merely by adding the map. The package selected
for J614s must be explicitly T6040-safe: board DT, single-core command line,
storage-disabled policy, and no unsupported U-Boot/EFI assumption for B0.

## Requirement 2: model a complete raw boot object

The installer currently assumes `boot_object` is only the m1n1 prefix:

1. `src/osinstall.py` appends `chosen.*` and `chainload=` variables;
2. `src/m1n1.py` appends a four-zero terminator;
3. upgrade extracts variables by splitting after `STACKBOT` and decoding
   everything before the first zero;
4. upgrade then replaces the installed object with the new prefix plus those
   variables.

A B0 object instead contains variables, compressed Linux, FDT, and initramfs.
The current `extract_vars()` will encounter binary payload data and fail ASCII
decode; if it did not, the upgrade path would still discard the Linux payload.

Add an explicit template/object mode, for example
`boot_object_format: raw-m1n1-payload`, with these invariants:

- a fully assembled object is copied byte-for-byte; generic EFI/chainload
  variables are not appended after its terminator;
- its expected SHA-256, `0x800` entry, prefix, records, component hashes,
  expansion bounds, and embedded command line are verified before step 2;
- upgrades either replace the whole signed/versioned artifact atomically or
  refuse with a clear message; they never replace only its m1n1 prefix;
- repair uses the exact staged artifact and checks its hash before enrollment;
- legacy stage1-plus-variable objects retain their present behavior;
- version display may still use `##m1n1_ver##`, but format detection must not
  rely on `STACKBOT` plus ASCII-to-NUL for a complete payload stream.

Wallace's `scripts/t6040-raw-object-verify.py` and ticket-080 byte contract are
a reference implementation for host validation, not a mandatory installer
dependency.

## Requirement 3: support macOS 26.x recovery firmware

The 25F84 J614s fixture exposes several independent changes:

1. The restore manifest's BaseSystem member is `.dmg.aea`. The current stub
   copies/compresses it as `arm64eBaseSystem.dmg`, then later asks `hdiutil` to
   attach it. AEA must first be authenticated/decrypted using a maintained,
   auditable mechanism and the Apple-published key. Renaming or compression is
   not decryption.
2. Real Wi-Fi payloads moved from
   `usr/share/firmware/wifi` into
   `com.apple.DriverKit-AppleBCMWLAN.dext/Firmware`; the old location contains
   dangling compatibility symlinks. Collection must select the real tree and
   resolve/reject symlinks safely.
3. `WiFiFWCollection` does not understand the new `F-` dimension,
   `*_gen*.clmb`, `.pcfb`, or `.man` forms. Add grammar/tests without allowing
   an unknown dimension to abort the entire corpus. Only emit file types with
   a defined Linux consumer; preserve unsupported metadata separately if
   useful.
4. `BluetoothFWCollection.VENDORMAP` lacks `AMKOR`, and the tree also contains
   MediaTek firmware. Add the fitted vendor mapping once its Linux filename
   contract is agreed; unrelated chips must be skipped without losing the
   valid USI mriya pair.
5. Multitouch needs no J614s special case. Its generic collector already turns
   `Firmware/J614s_Multitouch.im4p` into
   `apple/tpmtfw-j614s.bin`. Preserve that behavior and add the known 25F84
   output as a regression fixture.

Known fixture outputs:

| Output | SHA-256 |
|---|---|
| `apple/tpmtfw-j614s.bin` | `a1f4131d0cb7caf6fa15b19f47725458a6d7b0e3a34f15169339d5541663d9e2` |
| current 480-file BCM collector inventory | `e97ba4868845b855e45a7ada9d4702e4a15e597324a0d15688a508be571c7c78` |

The BCM inventory includes broad firmware and is a regression reference, not a
claim that every emitted file is needed by J614s.

## Requirement 4: validation and safety gates

Before offering J614s even in expert mode:

- unit-test legacy stage1 objects and complete raw-payload objects separately;
- prove install, repair, and upgrade preserve the complete object's exact hash;
- reject wrong entry, wrong m1n1 prefix, missing payload, binary truncation,
  command-line mismatch, or expansion over policy;
- fixture-test `j614sap` / `0x6040` identity selection against 25F84;
- fixture-test AEA failure, authentication failure, moved Wi-Fi tree, new
  filenames, AMKOR, and J614s multitouch output;
- make package metadata distinguish B0 direct-m1n1 from B1 EFI chainload;
- keep actual `bputil`, `kmutil`, partitioning, and enrollment out of unit
  tests and behind the normal interactive second-stage confirmation.

## Upstream patch split

A reviewable series should be split as:

1. complete raw-object format/parser and upgrade semantics, with synthetic
   tests;
2. macOS 26 AEA/recovery mounting support;
3. 26.x Wi-Fi/Bluetooth collector grammar and fixtures;
4. T6040/J614s expert-only maps;
5. installer-data B0 package metadata only after the exact B0 object is proven.

No external issue, patch, or pull request was posted. Ticket 026 is complete as
a requirements artifact; implementation remains upstream work and is not a B0
manual-enrollment dependency.
