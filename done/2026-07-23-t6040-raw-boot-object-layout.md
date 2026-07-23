# T6040 raw m1n1 boot-object layout audit

Date: 2026-07-23  
Ticket: 080  
Scope: host-only; no APFS, Boot Policy, enrolled object, or rig access

## Decision

B0 uses a **direct raw m1n1 payload**, not U-Boot/FIT. The format already
supports the required kernel, J614s DTB, initramfs, and `/chosen` variables.
U-Boot remains the B1 standard-EFI path in ticket 025.

The raw object has no outer container, header, length table, or object magic.
It is byte concatenation:

```text
offset 0
  exact raw m1n1.bin
  chosen.bootargs=<ASCII command line>\n
  gzip or XZ Linux Image
  raw J614s FDT
  gzip or XZ newc initramfs
  at least four zero bytes
```

There is no required padding between payload records. The m1n1 prefix itself
is 16 KiB aligned and `_payload_start` is its exact file length.

## Entry, loading, and execution

`m1n1-raw.ld` is relocatable at virtual address zero. `_start` is at `0x800`;
the supported macOS 12.1+ enrollment command therefore uses:

```text
--raw --entry-point 2048 --lowest-virtual-address 0
```

No Mach-O or SPTM payload path participates. The 64 MiB `PYLD` segment in
`m1n1.ld` describes the Mach-O build only; `m1n1-raw.ld` has no corresponding
payload cap. Wallace nevertheless adopts a conservative **64 MiB complete raw
object policy** until the enrolled-path limit is measured separately.

m1n1 scans from `_payload_start` at boot. It copies an inline Linux Image to a
2 MiB-aligned heap allocation and reserves the Image header's `image_size`.
It also copies/decompresses the initramfs and grows the DT buffer by six 16 KiB
pages during kboot preparation. Current T6040 logs place the usable heap
between approximately `0x100047bc000` and `0x105ce79c000`, over 23 GiB, so the
B0 policy limits below are much smaller than the observed physical budget.

## Parser contract

- Kernel: gzip or XZ when followed by another payload. A raw kernel has no
  file-length field and stops scanning, so B0 rejects it.
- DTB: raw FDT is preferred. Its big-endian `totalsize` is the record length.
  A compressed FDT also works, but does not improve auditability here.
- Initramfs: gzip or XZ newc/crc cpio. An uncompressed cpio is accepted only
  when a preceding `m1n1_initramfs` plus little-endian 32-bit size wrapper
  supplies its length; B0 uses compression.
- Variables: ASCII `name=value\n`; m1n1 limits names to 64 and values to 1024
  bytes and carries at most 16 `chosen.*` entries.
- gzip and XZ decoders each advertise a 1 GiB destination ceiling.
- Four zero bytes terminate scanning. Wallace requires the remainder of the
  object to be zero so trailing corruption cannot be silently ignored.
- Autoboot requires both a compatible DTB and a kernel. `payload_run()` then
  prepares the DT and directly invokes `kboot_boot()`.

The first object keeps the record order exactly
`chosen.bootargs`, kernel, DTB, initramfs, terminator. Alternative orders that
m1n1 might accept are deliberately outside the B0 contract.

## Wallace size and expansion policy

| Item | B0 ceiling |
|---|---:|
| Complete raw object | 64 MiB |
| One compressed member's expansion | 1 GiB (m1n1 source limit) |
| Kernel header `image_size` reserve | 512 MiB |
| Expanded initramfs | 256 MiB |
| Raw DTB | 2 MiB |
| DTB runtime growth | raw size + 96 KiB |

The verifier sums kernel `image_size`, expanded initramfs bytes, and the
expanded DTB plus its 96 KiB growth. These are conservative policy checks, not
claims about an undocumented Apple raw-enrollment maximum.

## Host verifier

`scripts/t6040-raw-object-verify.py` validates:

- byte-identical m1n1 prefix, 16 KiB prefix alignment, and a nonzero entry at
  `0x800`;
- the exact B0 role count and order;
- gzip/XZ integrity, expanded type, FDT size, kernel reserve, and initramfs
  expansion;
- exact component bytes/hashes and expected command line in strict mode;
- the 64 MiB object policy and runtime-reserve policy;
- truncation, corruption, missing records, wrong ordering, and nonzero data
  after the terminator.

Typical release gate:

```sh
scripts/t6040-raw-object-verify.py \
  linux-build-out/m1n1-b0-alpine.bin \
  --m1n1 linux-build-out/m1n1-b0.bin \
  --kernel linux-build-out/Image-b0.gz \
  --dtb linux-build-out/t6040-j614s-b0.dtb \
  --initramfs linux-build-out/initramfs-alpine-b0.cpio.gz \
  --expect-bootargs 'maxcpus=1 idle=nop ... rdinit=/sbin/init' \
  --strict --json
```

Its built-in valid/corrupt/truncated/wrong-order/nonzero-tail tests pass.

## Concrete parser test vector

A complete object was assembled and parsed **in memory only** from the current
diagnostic components. It was not saved and is not a live candidate:

| Record | Offset | Stored bytes | Expanded/runtime bytes |
|---|---:|---:|---:|
| m1n1 prefix | `0x000000` | 1,097,728 | — |
| `chosen.bootargs` | `0x10c000` | 163 | — |
| gzip kernel | `0x10c0a3` | 16,536,017 | 53,303,808 / 54,132,736 |
| raw DTB | `0x10d1274` | 51,659 | 51,659 / 149,963 |
| gzip initramfs | `0x10ddc3f` | 4,043,233 | 8,768,512 |
| zero terminator | `0x14b8e20` | 4 | — |

The object is 21,728,804 bytes, its test-vector SHA-256 is
`16be13794d2dd97f66d173befa0155faa3b77641c3721806c4c70cfa07104224`,
and its total runtime payload reserve is 63,051,211 bytes.

This vector used the current local `m1n1/build/m1n1.bin`
(`3e0c90af77e1f13930e432f3ed124215d2ddeb6de050c8b29b90173a2818f31f`)
only to exercise parsing. That build identifies itself as
`16b1f61f-dirty` and contains the new T6040 PCIe operation-115 work. It is
**not approved for B0 or any rig run**.

The B0 object must instead use an independently reviewed, exact m1n1 artifact
with no unapproved PCIe writes. The current safe candidate is the live-proven
upper-guard binary:

```text
linux-build-out/m1n1-t6040-logbuf-upper-guard-dryrun.bin
SHA-256 1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b
embedded version v1.6.0-75-ga61fd099
```

Ticket 081 must re-run the verifier against the final exact B0 artifacts; the
test-vector hash above is documentation, not an artifact input.

## Autoboot and observational KIS

Normal developer builds have `EARLY_PROXY_TIMEOUT` disabled. A release
chainloading build enables a five-second early-proxy window only when the
incoming boot arguments report no display and `lp-sip0 == 127`. A normal
boot-picker cold boot with display does not enter that window.

For the ticket-081 tethered single-object proof, use a build without
`EARLY_PROXY_TIMEOUT`, or statically verify the condition cannot hold. After
chainload, do not reconnect proxyclient or send a proxy handshake. KIS may
capture console output, but B0 success must not depend on it.

## Remaining dependency

Ticket 080 is complete. Ticket 081 is still blocked by ticket 079, which in
turn awaits the approved ticket-076 trace and evidence-driven HID repair.
Nothing in this layout audit authorizes ticket 076, object enrollment, APFS or
Boot Policy changes, or a rig boot.
