# Independent review: ticket 215 SD repair object v4

Reviewer: independent (non-builder) offline review, 2026-10-24. No rig, lease,
card, enrollment or boot.

**Verdict: PASS.** v4 is v3 with the bootargs record corrected; ready for CJ's
hash acknowledgement (the earlier approval covered `bf395c6e…`).

## Findings

- `m1n1-sdroot-repair-v4.build1.bin` = `build2.bin` = `6ae7244e0dba…a187b`
  (36,945,920 B). v3 `build1/2` = `bf395c6e…`, same size.
- `cmp -l` v3 vs v4, both builds: exactly 61 differing bytes, all in offsets
  1,097,806–1,097,867, i.e. inside the 155-byte `chosen.bootargs` record
  (the record starts at offset 1,097,728 = `0x10c000`, so the changed window is record bytes 78–139). Nothing else
  differs: kernel, DTB, initramfs, terminator and padding are byte-identical.
  Old: `… console=tty0 fbcon=… ignore_loglevel console=ttydc0 rdinit=/init`.
  New: `… fbcon=font:TER16x32 ignore_loglevel console=ttydc0 console=tty0 rdinit=/init`
  (same 155-byte length, so no later offset moves).
- Strict verifier (my own invocation with `--m1n1 m1n1-sdroot-hardened.bin`
  `97a30488…`, kernel member `Image-sd-gl9755.repair-v4.raw-object.buildN.gz`
  `8fa32648…`, DTB `t6040-j614s-dcuart-sd-v2.buildN.dtb` `4e482173…`, initramfs
  `initramfs-bootstrap-sdroot-fsck-v3.buildN.cpio.gz` `901ad007…`, and the new
  bootargs): PASS on both builds, entry `0x800`.
- Preflight (`--object`, `--bootargs`, `--m1n1 m1n1-sdroot-hardened.bin`): OK.
  Only warning: `./sbin/fsck.exfat` not embedded. `fsck.exfat` is in the
  initramfs at `/usr/sbin/fsck.exfat`, and `/usr/local/sbin/t6040-sdroot-fsck`
  calls it by that absolute path, so the warning is a path-convention artefact.
  (With `--stage2-loader` the preflight FAILs on stage-2 markers; that mode is
  for stage-2 loaders, not this object, and the author's own output matches the
  default mode.)
- Embedded `/init` = `8fcd4f1d…`; `t6040-sdroot-fsck` = `f6192dbe…` (both match 215's pins).
  `/init` waits for `/dev/ttydc0`, dup's it to fd 9 and redirects all repair I/O there,
  so moving `console=tty0` last does not change the observation channel.

## How it could be wrong

- *Console reorder breaks the transcript.* Ruled out: init writes to
  `/dev/ttydc0` explicitly. Only the keymap line uses `/dev/console` (panel).
- *Shared members hide a v3 defect.* Members were re-hashed against the pins, not
  re-reviewed line-by-line beyond `/init` and a read of `t6040-sdroot-fsck`'s
  command set (`fsck.exfat -n/-p`, `e2fsck -f -n/-p`; no mkfs/resize/dd paths).

## Notes

- The final `exec sh -i` runs on the ttydc0 tty, so the panel keyboard cannot be
  used for the recovery shell; the host console is the recovery path. Pre-existing.
- 215's remaining gates (CJ ack; rollback enrolled; attended; lease) are unchanged.

## Commands run

```text
shasum -a 256 m1n1-sdroot-repair-v{3,4}.build{1,2}.bin Image-sd-gl9755.repair-v4.raw-object.build{1,2}.gz
cmp -l v3.buildN v4.buildN | …; dd/xxd of the bootargs record in both
python3 scripts/t6040-raw-object-verify.py --strict --m1n1 … --kernel … --dtb … --initramfs … --expect-bootargs '…' <object>   # x2
scripts/t6040-image-preflight.sh --kernel Image-sd-gl9755 --initramfs … --object … --bootargs '…' --m1n1 m1n1-sdroot-hardened.bin
gunzip -c initramfs-bootstrap-sdroot-fsck-v3.build1.cpio.gz | cpio -idm; shasum -a 256 init usr/local/sbin/t6040-sdroot-fsck
```
