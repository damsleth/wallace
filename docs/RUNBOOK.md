# T6040 runbook

Current as of 2026-08-03. This file contains operational commands only.
Read [COORDINATION.md](COORDINATION.md) before a rig run and
[DEVLOG.md](DEVLOG.md) for failure history.

## 1. Select a ticket and acquire the rig

    scripts/rig-lease.sh queue next --rig
    scripts/rig-lease.sh status
    scripts/rig-lease.sh acquire <agent> "<ticket and task>" <m1n1-sha>
    export RIG_AGENT=<agent>

The ticket must already be approved and ready. Do not use the lease for builds,
reviews, or documentation.

## 2. Recover and attach DebugUSB

Every successful Linux chainload consumes the current proxy. Before each new
chainload:

    RIG_AGENT=$RIG_AGENT bash scripts/t6040-debugusb-console.sh reboot

The helper enters DebugUSB, starts kisd, places the PTY in raw mode, and waits
for `Running proxy`. Confirm the proxy:

    ~/Code/m1n1/venv/bin/python scripts/t6040-proxy-alive.py \
        --device /tmp/m1n1 --timeout 5

Do not leave a manual `cat /tmp/m1n1` running while proxyclient owns the PTY;
it will steal reply bytes.

## 3. Chainload

For a ticket-specific raw object:

    RIG_AGENT=$RIG_AGENT bash scripts/t6040-boot-raw-object.sh \
        <object.bin> <full-sha256>

For the standard DockChannel kernel/initramfs loop:

    RIG_AGENT=$RIG_AGENT bash scripts/t6040-boot-dcuart.sh

Logs:

    tail -f ~/Code/linux-build-out/raw-object-chainload.log
    tail -f ~/Code/linux-build-out/dcuart-console.log

Send a command to the Linux tty:

    printf 'uname -a\n' > /tmp/m1n1

Use `scripts/t6040-bootcap-fb.sh <dtb> <initramfs>` only when the ticket
specifically requires panel-only observation.

## 4. Preserve evidence

The standard console log is rotating scratch space. For a result:

1. start a uniquely named transcript before boot;
2. stop capture only after the pass/fail boundary;
3. hash it before reboot;
4. record the exact command, object, member hashes, and first divergence.

Never infer a kernel hang from an empty ttydc0 log until a fresh reader and
proxy control prove the observation channel works.

## 5. Release

Return the target to a quiescent proxy, then:

    scripts/rig-lease.sh release $RIG_AGENT --state healthy

If the link is unhealthy or uncertain:

    scripts/rig-lease.sh release $RIG_AGENT --state wedged

Do not silently hand off a wedged KIS link.

## 5b. Verify the kernel before you boot it

`$OUT/Image` is what `t6040-boot-dcuart.sh` boots, and the per-build
`Image-<config>` artifacts do **not** update it. Check before blaming hardware:

    command ls -l $OUT/Image                       # date must match the build
    strings -a $OUT/Image | grep -m1 'Linux version'
    strings -a $OUT/Image | grep -c pcie-apple     # 0 == no PCIe driver
    strings -a $OUT/Image | grep -c macsmc         # 0 == no SMC driver

`boot-dcuart.sh` enforces this and refuses a kernel missing either marker;
`BOOT_SKIP_IMAGE_CHECK=1` overrides for a deliberately minimal kernel. `ls` is
aliased to `eza` here, so use `command ls -t` for real mtime ordering.

An entire missing subsystem is never a hardware fault. Empty
`/sys/bus/pci/devices`, no `mmcblk0`, no `wlan0` and no `/dev/input` all at once
means the wrong kernel, and a sub-second failure timestamp means a startup race
or a wrong artifact — not a power rail.

## 6. Build a kernel

The host Linux tree is on a case-sensitive volume. Code changes are supplied
as patches; the build uses committed kernel state plus copied T6040 DT files.

    cp scripts/t6040-kbuild.sh patches/*.patch ~/Code/linux-build-out/
    podman exec -e DOCKCHANNEL=1 -e BUILD_DIR=/build/linux-keyboard \
        kbuild bash /out/t6040-kbuild.sh image

Use only switches implemented by `scripts/t6040-kbuild.sh`. Relevant profiles
include `MACSMC=1`, `WIFI=1`, `PCIE=1`, `CPUFREQ=1`, and
`SD_GL9755=1`. The script must assert every required built-in symbol after
`olddefconfig`.

Fast DT-only rebuild:

    podman exec kbuild bash -c \
      'cd /build/linux-keyboard && make ARCH=arm64 apple/<name>.dtb && cp arch/arm64/boot/dts/apple/<name>.dtb /out/'

Run two clean builds before claiming byte reproducibility.

## 7. Build and verify a raw object

    python3 scripts/t6040-build-raw-object.py \
      --m1n1 <m1n1.bin> --kernel <Image.xz> --dtb <board.dtb> \
      --initramfs <initramfs.cpio.xz> --bootargs '<args>' <out.bin>

    python3 scripts/t6040-raw-object-verify.py --strict \
      --m1n1 <m1n1.bin> --kernel <Image.xz> --dtb <board.dtb> \
      --initramfs <initramfs.cpio.xz> --expect-bootargs '<args>' <out.bin>

If you pass an *uncompressed* `Image`, the packer compresses it internally and
the verifier will then fail on the kernel hash — it is comparing your raw file
against a compressed member. Use `--kernel-output` to save the exact member the
packer embedded and verify against that:

    python3 scripts/t6040-build-raw-object.py --kernel $OUT/Image \
      --kernel-output $OUT/<name>.kernel.gz … <out.bin>
    python3 scripts/t6040-raw-object-verify.py --strict \
      --kernel $OUT/<name>.kernel.gz … <out.bin>

Choose the m1n1 deliberately: an object built with a **window-free** m1n1 boots
straight through, while an always-proxy build waits for a host. Check with
`strings -a <m1n1.bin> | grep -c 'Waiting for proxy connection'` — `0` means
window-free. Confirm the check itself works by also matching a control string
such as `Boot policy: sip0`, or a false `0` will read as good news.

Put `console=tty0` **last** in the bootargs. Every `console=` receives printk,
but the last becomes `/dev/console`, which is what init's shell reads; with
`ttydc0` last the panel shows a shell that ignores the keyboard.

Required properties:

- total object size is a multiple of 16 KiB;
- entry point remains `0x800`;
- XZ members are one stream, one block, CRC32, and no BCJ;
- expanded initramfs stays below 128 MiB unless a separately reviewed policy
  change says otherwise;
- the ticket pins every member and bootarg hash.

Create compatible XZ:

    xz -9e --check=crc32 -T1 < in > out.xz
    xz -lvv out.xz

## 8. Build userspace

Proven RAM-root builders:

    bash scripts/t6040-build-alpine-b0.sh
    DEST=~/Code/linux-build-out/initramfs-dwm.cpio.xz \
      bash scripts/t6040-build-alpine-dwm.sh

The persistent root uses `scripts/t6040-sdroot-init`. Its filesystems are
currently dirty; do not mount them read/write outside approved ticket 215.
Build the pinned repair and hardened images with:

    scripts/t6040-build-sdroot-fsck-initramfs.sh
    scripts/t6040-build-sdroot-initramfs.sh

Ticket 215 must pass before ticket 216 applies `scripts/t6040-sdroot-apply`.
Normal reboot and poweroff must resolve to `t6040-sdroot-powerctl`; direct
BusyBox reboot bypasses the clean loop/exFAT teardown.

## 9. Dual-mode debug window

An enrolled dual-mode loader waits about ten seconds for a host to open its USB
serial interface. Merely connecting the cable does not assert DTR.

Start before reboot:

    while :; do
      d=(/dev/cu.usbmodem*(N))
      [ -n "$d" ] && break
      sleep 0.2
    done
    M1N1DEVICE=$d ~/Code/m1n1/venv/bin/python \
      ~/Code/m1n1/proxyclient/tools/shell.py

The m1n1 USB gadget and DebugUSB/KIS are mutually exclusive. Use
`/dev/cu.usbmodem*` for the dual-mode window and `/tmp/m1n1` for KIS.

## 10. Enrollment

Enrollment is maintainer-only from 1TR and requires a separately approved,
allowlisted object. Verify the target volume:

    diskutil info /Volumes/m1n1 | grep -E 'Volume Name|Volume UUID'

Expected dedicated volume UUID:

    B7FB1EC3-1BA0-4DCB-B57D-C8E9A0AE1E63

Hash-gated wrapper:

    bash scripts/t6040-enroll-guard.sh <object.bin>

It prints the command and runs only with its explicit confirmation option.
Rollback object:

    rollback-m1n1-1394c345.bin

Do not copy an enrollment command from an old result document; use the current
allowlist and verify the post-copy SHA-256.

## 11. Inspect the running machine

    cat /proc/cmdline
    dmesg
    cat /proc/partitions
    findmnt
    cat /proc/mtd
    dd if=/dev/mtd0 bs=1k count=16 2>/dev/null | strings
    cat /var/log/xorg-startx.log
    pgrep -a Xorg
    ls -l /dev/input

For graphical or early-console failures, preserve a panel photograph when the
ticket requires it. ttydc0 availability depends on the candidate driver and
boot stage; it is not a substitute for the panel in every experiment.

## Shell notes

| Problem | Correct form |
|---|---|
| zsh errors on an unmatched USB glob | `/dev/cu.usbmodem*(N)` |
| serial open waits for carrier | use `/dev/cu.*`, not `/dev/tty.*` |
| environment assignment was separated by semicolons | put assignments on the same command |
| 1TR has no sudo | run the command directly |
