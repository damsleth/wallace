# Independent re-review: ticket 5001 probe v2 (`2060376`)

Reviewer: sonnet, offline, 2026-10-25. No rig, lease, boot or build. Nothing
reviewed was edited. Supersedes the FAIL in
`2026-10-24-review-5001-nvme-p3-identity.md`.

**Verdict: PASS-with-notes.** Both must-fix items from the first review are
fixed and I reproduced the fix myself. One should-fix (label scan window) is
worth doing before spending a rig cycle.

## Artifacts (recomputed)

```text
432dee490a5f6351e49699397044f002abb60916bd9cc97d280364c2130496d2  scripts/t6040-init-nvme-p3-identity (= /init in the initramfs)
b29b7a83b09833c8d2d6af423cd9d0a669c931adde881321fa66b4aed1fa8d85  nvme-p3id-20261024/initramfs-p3id-{a,b}.cpio.gz = payload/initramfs.cpio.gz
61781806ad3650b0b9d2b3fc6971e2bffdca967af1a95375abd0578bafff14fb  embedded bin/busybox
6eef9eef…  payload/Image;  a96d04a7…  payload/t6040-nvme.dtb;  7de07c71…  payload/m1n1.bin
```

All match the ticket's pins and `initramfs-p3id-a.cpio.json`. Preflight on the
payload (`--proxy-payload`, ticket bootargs incl. `printk.devkmsg=on`): OK.

## First-review items

1. `blkid`: gone. The exFAT partitions are found by OEM string `EXFAT   ` at
   offset 3, and the label by reading the root directory from boot-sector
   geometry. **Fixed.**
2. Oversize kmsg line: gone. Longest record in my runs is 297 bytes (limit 1024).
   **Fixed.**
3. p3 absence: no partition number is assumed any more; `STOP: no exFAT partition
   found` + `park` if none. **Fixed.**
4. transport/model gate: back (`apple-nvme:APPLE*`). **Fixed.**
5. No checker: **still open** (see notes).

## How I tested it

The author's `run.sh` sources `/t/parse.sh`, which is not in the repo, and no
output was saved, so I could not reproduce it. I built my own harness instead
(`evidence/2026-10-25-review-5001-probe-v2-test/`): it extracts the probe section
of the committed script unchanged, points it at a loop device, and runs it under
the initramfs's own BusyBox 1.35 on real GPT + exFAT images (sgdisk,
mkfs.exfat). Cases:

| Case | Result |
|---|---|
| decoy partition (AF0A) + exFAT labelled `linux` | decoy "not exFAT"; `linux` found; geometry `heap=4096 rootcluster=4 spcshift=6`; root dir shows `83 05 'l' 'i' 'n' 'u' 'x'` |
| exFAT, no label | records `83 00 …` (empty label entry); still IDENTITY-DONE |
| ext4 only | `STOP: no exFAT partition found` then `park` |
| two exFAT (`other`, `linux`) | both recorded; `exfat-partitions=2`; labels distinguishable |

Boot-sector field offsets used (88 heap, 96 root cluster, 106 flags, 108/109
shifts) are the exFAT spec offsets, and the computed root-directory offset
landed exactly on the label entry in every case. GPT header (92 bytes) and the
first 8 entries (128 bytes each) print correctly with the type GUID and name.

## Notes

- **Should-fix: label window.** Only the first 8 root-directory entries are
  dumped. `mkfs.exfat` puts the label first, but other formatters may not, and
  if no `0x83` entry is in those 256 bytes nothing says so (the run still ends
  `IDENTITY-DONE`). Dump 512 bytes (4 lines) or the whole first cluster in
  chunks, and `say 'WARN: no label entry in first N entries'` when absent.
  Cheap to fix and saves a rig round trip.
- **Open: no transcript checker.** The ticket's PASS is "IDENTITY-DONE with zero
  write counters", checked by eye. Because 211 will pin what this prints, add a
  small checker (identity line, topology, `stats before`/`after` write, discard
  and flush fields equal, at least one `exfat … label` record, no `STOP`).
- **Low: arithmetic on a failed read.** If a `dd` for geometry fails, `u32`
  returns empty and the `$(( … ))` is a syntax error, which exits the shell, i.e.
  init, giving a kernel panic after the devices are already read-only. Harmless
  to data; the transcript tail would be lost.
- The write counters in my test output include sgdisk/mkfs writes from the
  harness; they say nothing about the probe, which has no write path (every
  access is `dd if=`/`cat`, devices set read-only first).
- Partitions are listed by sysfs; the 6001 run-3 log shows `nvme0n1: p1 p2 p3` at
  0.313 s, before the init's gate, so the glob is populated in time. Whole-disk
  read-only covers all partitions regardless.

## Commands run

```text
git show 2060376 --stat; git diff 662e08b 2060376 -- scripts/
shasum -a 256 scripts/t6040-init-nvme-p3-identity; extract initramfs-p3id-a.cpio.gz and cmp init to the script
scripts/t6040-image-preflight.sh --kernel payload/Image --initramfs payload/initramfs.cpio.gz --bootargs '<ticket>' --m1n1 payload/m1n1.bin --proxy-payload
podman machine ssh "sudo podman run --rm --privileged --platform linux/arm64 … sh /t/t_run.sh"   # four loop-image cases
grep -n 'nvme0n1: p' <6001 run-3 console log>
```
