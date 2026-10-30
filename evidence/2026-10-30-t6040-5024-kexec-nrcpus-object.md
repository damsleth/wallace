# 5024: kexec-capable object, 5019 plus `nr_cpus=1` (claude, on the M4, 2026-10-30)

**Result:** `/mnt/sd/wallace-5024/wallace-5024.build1.bin`, sha256
`02da5165117d0c3a5b18e62a890ffc8ee7120ecb181ea3e2df5a32cfa0eb16a3`, 33,177,600 B (2025 pages).
Built twice byte-identical; `t6040-raw-object-verify.py --strict` PASS; `t6040-image-preflight.sh`
OK. Not enrolled or booted.

The only change from 5019 is the bootargs. Kernel, DTB, initramfs and m1n1 are the bytes
inside the enrolled 5019 object.

## Bootargs (verbatim, for 5021)

```
nr_cpus=1 maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel printk.devkmsg=on console=ttydc0 console=tty0 rdinit=/init
```

`maxcpus=1` stays so preflight's ticket-205 check passes. `nr_cpus=1` makes one CPU *possible*,
which is what arm64's kexec stuck-CPU check looks at. The kexec command line in 5021 must carry
the same string, or the second kernel can't kexec again.

## Method: rebuilt from the 5019 object, on the M4

This was built on the M4 rather than the Mac. Everything it needs is in the 5019 object, and
building it this way guarantees the payload is the enrolled one.
`scripts/t6040-rebootargs-object.py` (new) splits an object at the `chosen.bootargs=` variable
and at the known DTB and initramfs. It writes the m1n1 stage and the compressed kernel member,
then rebuilds with `t6040-build-raw-object.py`. It ran in the bookworm chroot (python3 3.11).

| piece | sha256 | matches |
|---|---|---|
| m1n1 (first `0x10c000` B) | `bf4b24627560759f…` | 5019 evidence "m1n1 (window-free, from 5014) `bf4b2462`" |
| kernel gzip member (25,081,828 B) | `2fcc01e14d841712…` | 5019 evidence "kernel gzip member `2fcc01e1`" |
| DTB | `1a49d19dd3778799…` | 5019 |
| initramfs | `82a86064b3d44058…` | 5014/5019 |

**Identity check first:** rebuilding with 5019's own bootargs gives
`28127903fb83ad4a235eb887964b21122e2b20d2492b819dd9883264e652631c`, which is exactly the enrolled
5019 object. The script refuses to finish if an unchanged-bootargs rebuild differs from its input.

The ticket asked for `t6040-build-masked-object.sh` to take bootargs as a parameter. That script
is the old B0 masked-object builder and is not what built 5014/5019. `t6040-build-raw-object.py`
already takes `--bootargs`, so nothing needed changing.

## Preflight fix found on the way

On the M4, preflight reported "keymap is never loaded -- no loadkmap call in ./init" for the
5019 initramfs too. That was false: `./init` line 117 runs `"$BB" loadkmap < /etc/wallace-no.bmap`.
The check extracts `./init` with `bsdtar`, which the bookworm chroot does not have, and it then
failed closed. Preflight now falls back to GNU `cpio --to-stdout` when `bsdtar` is missing (on
macOS the `bsdtar` path is unchanged, because bsdcpio's `--to-stdout` is the broken one). With
the fix, preflight is OK for both 5019 and 5024.

## Not done

- The enroll guard's allowlist (`scripts/t6040-enroll-guard.sh`) does not include `02da5165…`.
  Adding a hash there approves an enrollment, so it stays with CJ or a review.
- Enrolling and booting it is 5021 phase A.
