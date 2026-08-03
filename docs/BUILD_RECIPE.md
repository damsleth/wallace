# Build recipe — every T6040 image and boot object

**This document is maintained, not archival.** When a build property turns out
to matter, it is added here *and* to `scripts/t6040-image-preflight.sh` in the
same change. A checklist that has to be remembered fails the same way the memory
it replaces fails — so the enforceable rules live in the script, and this file
explains why each one exists.

    scripts/t6040-image-preflight.sh \
        --kernel     $OUT/Image \
        --initramfs  $OUT/initramfs-sdroot-hardened.cpio.gz \
        --m1n1       ~/Code/m1n1/build/m1n1.bin \
        --object     $OUT/<name>.raw-object.bin \
        --bootargs   '<the exact bootargs>'

Exit 0 means every applicable invariant holds. **Nothing gets enrolled, handed
to CJ, or booted on the rig until this passes.**

## Why this file exists

Three properties have each been forgotten or mis-set at real cost:

| what | cost |
|---|---|
| Norwegian keyboard layout | forgotten **three times**; a US map makes `\|`, `\`, `@`, `$`, `[]`, `{}` and `æøå` wrong or unreachable, so a shell is unusable for real work |
| a driver-complete kernel | a ten-day-stale `$OUT/Image` with no PCIe and no SMC driver faked an entire evening of hardware faults and caused two needless physical interventions |
| `console=` ordering | `ttydc0` last makes `/dev/console` the serial port, so the panel shows a shell that ignores the keyboard |

## Mandatory properties

### 1. Norwegian keyboard layout — every image, no exceptions

Including throwaway diagnostic images, rescue shells, and initramfs-only boots.
Three independent layers, because each covers a different consumer:

- **console / initramfs.** Ship a binary `bkeymap` at `etc/wallace-no.bmap` and
  load it with busybox `loadkmap` *before any shell can be spawned* — including
  the rescue path. busybox has `loadkmap` (binary keymap on stdin), **not** kbd's
  `loadkeys`, and ships no applet symlink for it, so invoke it as
  `busybox loadkmap < file`.
  The keymap is kernel state on the VT, so loading it in the initramfs also
  covers the console after `switch_root`.
- **Alpine / OpenRC root.** `keymap="no"` plus the console keymap service.
- **Xorg.** `XkbLayout "no"` via `/etc/X11/xorg.conf.d/00-keyboard.conf`. Set it
  by **config**, not only by running `setxkbmap` — a silenced `setxkbmap`
  (`2>/dev/null`) leaves the layout US when the binary is absent, invisibly.
  The console keymap does **not** cover X.

Prefer the `nb_NO` locale as well.

Regenerating the keymap (Debian ships no Mac-Norwegian variant, so this is the
PC `no` layout; it is correct for `æøå` and the symbol keys):

    podman exec kbuild sh -c 'apt-get install -y -qq kbd console-data &&
      loadkeys --bkeymap /usr/share/keymaps/i386/qwerty/no-latin1.kmap.gz' \
      > $OUT/no-latin1.bmap

It is hash-pinned in `scripts/t6040-build-sdroot-initramfs.sh`; update the pin
when regenerating.

### 2. A driver-complete kernel

`$OUT/Image` is what `t6040-boot-dcuart.sh` boots, and the per-build
`Image-<config>` artifacts **do not update it** — it can silently be weeks old.
Required markers: `pcie-apple`, `macsmc`, `dockchannel-hid`.

A whole missing *subsystem* is never a hardware fault. Empty
`/sys/bus/pci/devices`, no `mmcblk0`, no `wlan0` and no `/dev/input` all at once
means the wrong kernel. A sub-second failure timestamp means a startup race or a
wrong artifact — not a power rail.

`boot-dcuart.sh` refuses a kernel missing `pcie-apple` or `macsmc`;
`BOOT_SKIP_IMAGE_CHECK=1` overrides for a deliberately minimal kernel.

### 3. Bootargs

- `console=tty0` **last**. Every `console=` receives printk, but the last becomes
  `/dev/console`, which is what init's shell opens for stdin.
- `console=ttydc0` earlier, so serial logging still works.
- `maxcpus=1` until ticket 205 is resolved. The bug is fail-stop — it kills
  processes rather than corrupting data — but it still kills them.
- `rdinit=/init` for the switch-root initramfs.

### 4. Objects

- Size a whole multiple of **16 KiB**, or iBoot never runs it.
- Entry point `0x800`.
- **Window-free m1n1** for anything CJ enrolls as a daily driver
  (`strings -a m1n1.bin | grep -c 'Waiting for proxy connection'` → `0`).
  An always-proxy build is correct *only* for the rollback object.
- Verify with `t6040-raw-object-verify.py --strict`. If you pass an
  uncompressed `Image`, use `--kernel-output` and verify against that member —
  the packer compresses internally, so verifying against the raw file fails on
  the kernel hash.

### 5. Initramfs contents

- `init`, `bin/busybox`, `etc/wallace-no.bmap`.
- `sbin/fsck.exfat`, statically linked — the initramfs carries no libc and no
  dynamic loader. Build with `make LDFLAGS=-all-static`: libtool ignores a plain
  `-static` in `LDFLAGS`, and a PIE default silently defeats it. Confirm with
  `file` reporting *statically linked*.
- BCM4388 WiFi and BT firmware, because `brcmfmac` and `hci_bcm4377` probe
  before `switch_root`.

## Verification discipline

Two habits that have each produced a wrong conclusion here:

- **Confirm the check works before trusting a negative.** `strings … | head -1`
  once hid the very line that disproved a theory, and a `grep -c` for the wrong
  driver name returned a confident `0` for a kernel that had the driver. Always
  match a control string too — the preflight does this deliberately.
- **`grep -q` in a pipeline under `set -o pipefail` reports false failures**: it
  exits early, the upstream `gzip` takes `EPIPE`, and the pipeline status is
  non-zero. Count matches instead. This bug was in the first version of the
  preflight script and would have condemned good images.
