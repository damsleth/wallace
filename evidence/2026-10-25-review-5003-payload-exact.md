# Exact-artifact review: 5003 NVMe exFAT write payload (ticket 211 stage 1) — PASS-with-notes

Date: 2026-10-25. Reviewer: claude (Mythos Wallace session). Offline,
host-only; no podman, no rig, nothing edited. Requested by Opus Wallace.
Payload: `~/code/linux-build-out/nvme-exfat-write-20261025/payload/`,
pins in `tickets/5003-nvme-exfat-write-test-payload.json` at `dec4a27`.

## Verdict

**PASS-with-notes.** Every pinned hash matches the file on disk and its
stated provenance; the initramfs `/init` is byte-identical to
`scripts/t6040-init-nvme-exfat-write` at HEAD; Sonnet's two must-fixes and
three should-fixes are all present in the shipped script and checker; and I
found no path by which the init can write outside `nvme0n1p3`. Three notes
below, one of which (the host deadline) should be settled in the run
procedure before the lease is taken.

## 1. Hashes and provenance

| File | sha256 | Matches |
|---|---|---|
| `Image` | `4fadb8d3…cfafcc` | `/out/Image-hid-type-fix-nbcon-nvmeexfat.build1` (the NVME_EXFAT build 1 whose config I passed in `2026-10-25-review-5003-nvmeexfat-kernel.md`); `strings` finds 67 `exfat` symbols/messages |
| `System.map` | `48f2d81d…` | SHA256SUMS and ticket |
| `config` | `1b19daba…` | the reviewed config (6001 config + `EXFAT_FS=y`, `EXFAT_DEFAULT_IOCHARSET="utf8"`) |
| `initramfs.cpio.gz` | `dccf3de9…` | SHA256SUMS and ticket |
| `m1n1.bin` | `7de07c71…` | 6001 run-3 payload `nvme-ioq-20261024b/payload/m1n1.bin` and the 5001 pin |
| `m1n1-raw.elf` | `5bee616c…` | 6001 run-3 payload |
| `t6040-nvme.dtb` | `a96d04a7…` | 6001 run-3 payload, ticket 6001 and 5001 pins |

`SHA256SUMS` lists all seven with the same values (its paths are relative
to the parent directory, so `shasum -c` must be run from
`linux-build-out/`). Bootargs in the ticket equal the preflight log's;
preflight `OK` (the proxy-m1n1 WARN is expected for a chainload object).

Initramfs contents (extracted): `/init` sha256 `7d2bbea4…` equals
`scripts/t6040-init-nvme-exfat-write` at HEAD (`git diff --quiet HEAD`
clean; `cmp` identical). `bin/busybox` `61781806…` and `sbin/fsck.exfat`
`d56b877d…` are the 5003-reviewed binaries. `sbin/nvme-readonly-test`
`aef24ab9…` is byte-identical to the one in the 6001 run-3 initramfs and is
never invoked by this init (note 3). Keymap `etc/wallace-no.bmap` present
and loaded before any console.

## 2. Sonnet's findings against `a845615` and `e893aa4`

| # | Finding (`2026-10-25-review-5003-exfat-write-init.md`) | Where it is now |
|---|---|---|
| must-fix 1 | kernel cannot mount exFAT | `Image` is the NVME_EXFAT build (config line 10919 `CONFIG_EXFAT_FS=y`); 67 exfat strings in the Image |
| must-fix 2 | no host stop / checker | checker `scripts/t6040-check-nvme-write-transcript.py` (`e893aa4`, extended in `a845615`): stop tokens incl. case-sensitive `SError`/`RTKit: Exception`/`NVME-WRITE STOP` and `Reset failure`/`ANS did not`; requires the pins line, mode line, exactly one PASS line, equal write/read-back hashes, three (write) or two (verify) clean `fsck.exfat -n`, and `sectors written: disk=N p3=N` equal. **Host deadline: see note 1** |
| should-fix 3 | out-of-partition writes undetected | init lines 105-107, 144-147: disk vs p3 write-sector delta must be equal or `STOP: writes outside p3 on nvme0n1`; checker line 21-23 enforces it on the transcript |
| should-fix 4 | pin the boot-sector hash in write mode | lines 92-96: `bb426fe0…` over the first 512 bytes of p3, write mode only |
| should-fix 5 | re-read from the device | lines 130-131: `sync` then `echo 3 > /proc/sys/vm/drop_caches` (stop on failure) before the ro mount |

## 3. Can anything write outside p3?

Walked every command in the init. Writers, in order:

- `blockdev --setro` on p1, p2, p4, n2, n3 (lines 65-68) — an ioctl, no
  media write; runs before any pin read or mount, so a wrong-disk boot
  stops at the next gate with those nodes already read-only.
- `mount -t exfat -o rw /dev/nvme0n1p3` (line 114), the 1 GiB `dd` into
  the mount, the hash file, `sync`, `umount` — all through p3's block
  device. The exfat driver has no path to another bdev. No `discard`.
- `fsck.exfat -n` three times — read-only mode, on `$DEV` only, never
  while mounted (before: unmounted; after-write and final: after `umount`).
- `/proc/sys/vm/drop_caches` — kernel memory only.

Everything that touches `/dev/nvme0n1` (GPT entry reads, lines 85-87) and
`$DEV` outside the mount (lines 88-95) is `dd if=`, read-only. There is no
nvme admin tooling in the initramfs, no `/dev/nvme0` char-device use, no
`blockdev --setrw`, no mkfs, no partition tool. The whole-disk node stays
writable by design (a read-only disk would make p3 read-only too); the
only writer through it is the exfat driver via p3's own bdev.

Detection on top of prevention: `others()` hashes the full stat lines of
p1/p2/p4/n2/n3 before and after (any read or write there stops the run,
which is conservative in the right direction), and the disk-vs-p3
written-sector equality catches any write that bypassed p3. In `verify`
mode both deltas must be zero, which the ro mount satisfies.

Pins: the GPT entry offset `2*4096 + 2*128 = 8448` (slot 2 = p3, 4 KiB
LBS asserted first), type/unique/LBA bytes, exFAT signature, serial, root
label and the write-mode boot-sector hash are the values Sonnet
recomputed from the 5001 raw transcript; I did not re-derive them, I
confirmed the shipped script carries exactly those bytes.

## Notes

1. **Host deadline is a note, not a mechanism.** The ticket says "Host
   deadline 180 s", but nothing in `scripts/` enforces it; the in-image
   `watchdog` keeps petting while a hung `dd` blocks (Sonnet's point).
   Before the lease: state in the run procedure who stops the run at
   T+180 s without a `PASS` line, or wrap the console capture in a
   `timeout`. Not a payload defect; a procedure gap.
2. **Single build at pin time.** `Image` is build 1; the byte-identical
   build 2 is still compiling. Per the two-build rule the payload is
   "ready" only once build 2's Image/System.map/config hashes equal
   `4fadb8d3…`/`48f2d81d…`/`1b19daba…`.
3. **Leftover binary.** `sbin/nvme-readonly-test` from the 6001 image is
   carried but unused. Harmless (identical to the reviewed 6001 copy, never
   executed); drop it from the next initramfs so the image contains only
   what the run uses.
4. Verify mode skips the boot-sector pin by design (the driver updates
   VolumeFlags/PercentInUse on the first rw mount), and refuses a second
   `write` while `wallace-write-test/` exists. Both behaviours are correct.

## Commands run

```text
shasum -a 256 payload/*; diff against SHA256SUMS and the ticket "hashes"
gzip -dc initramfs.cpio.gz | cpio -idm; cmp ./init scripts/t6040-init-nvme-exfat-write
shasum -a 256 ./init bin/busybox sbin/fsck.exfat sbin/nvme-readonly-test (and the 6001 initramfs copy)
shasum -a 256 /out/Image-hid-type-fix-nbcon-nvmeexfat.build1 nvme-ioq-20261024b/payload/{m1n1.bin,m1n1-raw.elf,t6040-nvme.dtb}
strings -n 5 payload/Image | grep -ci exfat
git show a845615 e893aa4; cat -n scripts/t6040-init-nvme-exfat-write scripts/t6040-check-nvme-write-transcript.py
```
