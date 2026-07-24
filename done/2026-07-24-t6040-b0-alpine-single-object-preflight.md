# T6040 Alpine single-object control preflight

> **Final amendment:** ticket 089 passed this delivery control. The release
> object was subsequently reviewed and passed live under ticket 100.

Date: 2026-07-24  
Scope: historical preflight; live control completed under ticket 089

## Purpose

This control isolates the raw-object/autoboot boundary. It packages the exact
ticket-078 live-proven HID-restored Alpine kernel, storage-disabled DTB, and
automatic TX reporter behind the exact safe m1n1 prefix. A live run uploads
this one object with `chainload.py -r`; it must not invoke `linux.py` or upload
a second payload.

This is already a bootable Alpine diagnostic image with a registered internal
keyboard. It is not yet the release-like OpenRC B0 image owned by ticket 079.

## Exact artifact

```text
m1n1-b0-alpine-hid-restored.bin
SHA-256 b50f52ab1fac473db2e9257c5363ef7905e4d1da5c8535fbf417209b09319172
size 21,729,039 bytes
raw entry 0x800
```

Inputs:

| Component | SHA-256 |
|---|---|
| safe m1n1 prefix | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| uncompressed live-proven `Image-hid-type-fix` | `df7657c15ad73a486f5046bcc802f070d6b7ec071fb6bb70954fb8f222d4815a` |
| exact gzip kernel member | `d76463e51cf3fb61e0af93f9ea6f24562de32db78988eeaa98a031f0c336bcc5` |
| storage-disabled DCUART/HID DTB | `2782b92237c35c8950212207391c3ae28c44b6b9c635b2e864c5748a77bb3cce` |
| ticket-076 Alpine reporter initramfs | `d5b790c63276816a3d69071797da459918717924885174d2a8b84225c6b24093` |

Embedded command line:

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel t6040.hid_trace_auto=1 rdinit=/init
```

Strict parser result:

| Offset | Size | Role |
|---:|---:|---|
| `0x10c000` | 163 | `chosen.bootargs` |
| `0x10c0a3` | 16,536,252 | gzip kernel |
| `0x10d135f` | 51,659 | raw DTB |
| `0x10ddd2a` | 4,043,233 | gzip initramfs |
| `0x14b8f0b` | 4 | zero terminator |

The verifier expands and byte-compares every member. Runtime reserve is
63,051,211 bytes and the complete object is below the 64 MiB policy. Two
independent builds byte-match. `scripts/t6040-raw-object-verify.py --self-test`
also passes.

## Safety and delivery audit

- The m1n1 prefix is the PCIe-write-free, live-proven upper-guard artifact. Its
  binary lacks the `Waiting for proxy connection` string compiled with
  `EARLY_PROXY_TIMEOUT`.
- Kernel, DTB, and initramfs are the exact ticket-078 components that registered
  `Apple DockChannel Keyboard` as `input0/event0`. USB, USB DART, ANS, SART,
  and NVMe remain disabled; no `root=` is present.
- Compression and concatenation do not alter expanded component bytes.
- `scripts/t6040-boot-raw-object.sh` enforces the rig lease and exact object
  hash, stops the competing PTY reader, invokes `chainload.py -r` exactly once,
  and immediately reattaches a raw reader. It contains no `linux.py` call.
- `chainload.py` appends four additional zero bytes after the object. This only
  extends the already valid zero terminator and cannot form another record.
- The right-port stick cannot be discovered by this DT and is not mounted or
  written. This experiment does not claim external USB-root progress.

## Proposed one-shot result contract

Start from stable `Running proxy`, hold the lease, and run only:

```sh
RIG_AGENT=codex scripts/t6040-boot-raw-object.sh
```

Send no target command. Pass requires:

1. the single upload completes and m1n1 reports embedded payload discovery;
2. Alpine 3.24.0/aarch64 reaches the existing ttydc0 TX path;
3. the complete automatic report reaches its end marker;
4. keyboard `05ac:0359` and `/dev/input/event0` remain present;
5. `/proc/partitions` remains empty and no second payload upload occurs.

Stop and recover on any hash mismatch, SError, reset loop, DART fault,
unexpected USB/storage probe, missing report end marker, or lost TX. The live
step still needs independent exact-artifact review and explicit maintainer
approval. No APFS, Boot Policy, or enrollment action is part of this control.

## Independent cross-review — claude, 2026-07-24 (author = codex/sol)

Per COORDINATION.md the non-author reviews the manifest before boot. Verdict:
**PASS — cleared to boot.**

- **Object identity exact:** `linux-build-out/m1n1-b0-alpine-hid-restored.bin`
  is 21,729,039 bytes, SHA-256 `b50f52ab…9172` — matches the ticket/preflight.
- **Strict verifier re-run independently** (`t6040-raw-object-verify.py --strict`
  with each pinned component + `--expect-bootargs`): PASS. Every member offset,
  size, and hash reproduces the manifest — bootargs `b2db0cbb…`, kernel gzip
  `d76463e5…`, DTB `2782b922…`, initramfs `d5b790c6…`, zero terminator, entry
  `0x800`, reserve 63,051,211 B < 64 MiB. `--self-test` PASS.
- **Every component resolves by content-hash to a live-proven artifact:** m1n1
  `1394c345…` (PCIe-write-free upper-guard), kernel `df7657c1…` (the 078
  HID-type-fix Image that registered event0), DTB `2782b922…` (storage-disabled
  DCUART/HID), initramfs `d5b790c6…` (076 Alpine auto-reporter). No new artifact.
- **Boot-script contract holds** (`t6040-boot-raw-object.sh`): sources
  `rig-guard.sh` (lease-enforced), re-checks the exact object SHA and aborts on
  mismatch, stops the competing PTY reader, runs `chainload.py -r` exactly once,
  contains no `linux.py` and sends no target command (so no MMIO/PMU/SPMI/storage
  op is reachable), reattaches a raw console reader. The `timeout 300` wraps only
  the chainload child, not kisd — no KEEPALIVE-kill hazard.
- **No forbidden boundary:** RAM-root only, storage-disabled DTB, no `root=`, no
  USB/ATC/SPMI, no APFS/Boot-Policy/enrollment. Same risk class as the proven
  dcuart Alpine boots, only repackaged as one self-contained object.

Standing stop conditions (SError/reset/DART/USB or storage probe/lost TX/missing
end marker) unchanged. Cleared for one boot under the maintainer approval already
recorded in the ticket store.
