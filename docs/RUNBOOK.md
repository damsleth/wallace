# T6040 runbook

Current as of 2026-10-30. This file contains operational commands only.
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

    ~/code/m1n1/venv/bin/python scripts/t6040-proxy-alive.py \
        --device /tmp/m1n1 --timeout 5

Do not leave a manual `cat /tmp/m1n1` running while proxyclient owns the PTY;
it will steal reply bytes.

**Host prerequisite (macOS 15.8.1, 2026-10-24).** `deviceinterfaced` can claim
the M4's "Debug USB" device (`05ac:1881`). Symptom: kisd repeats
`could not open device for exclusive access (error 0xe00002c5)`, no proxy
reply, and `ioreg` shows `IOUserClientCreator = "pid …, deviceinterfaced"` on
`Debug USB`. Workaround, **run by CJ, not an agent**: start kisd first and
leave it retrying, then

    sudo kill -9 $(pgrep -x deviceinterfaced)

kisd then takes the device, and the respawned daemon does not reclaim it while
kisd holds it. `launchctl kill` is refused under SIP. If a recovery reboot
fails with `Failed to send VDM`, stop VDM attempts; the next step is a
physical power cycle of the M4.
[Evidence](../evidence/2026-10-24-t6040-305-attempt-kis-blocked-by-deviceinterfaced.md).

The daemon can take the device again on **every** re-enumeration, including
after a recovery or watchdog reboot, so check `ioreg` after each reboot
(2026-10-25).

**Manual recovery when the M4 shows `Running proxy` but the link is silent**
(worked on 2026-10-25 after three failed reboots). Order matters: kisd
attached and a console reader running *before* the reboot.

    # kisd running and holding Debug USB; then, in its own shell:
    cat /tmp/m1n1                         # reader, left running
    sudo -n /usr/local/bin/macvdmtool reboot debugusb
    # wait for "Running proxy" in the reader, then stop only that reader:
    pkill -f '^cat /tmp/m1n1$'
    ~/code/m1n1/venv/bin/python scripts/t6040-proxy-alive.py \
        --device /tmp/m1n1 --timeout 5

Keep the `pkill` pattern anchored so it cannot match another process. Use this
only between runs; `boot-dcuart.sh` manages its own reader during a boot.

## 3. Chainload

For a ticket-specific raw object:

    RIG_AGENT=$RIG_AGENT bash scripts/t6040-boot-raw-object.sh \
        <object.bin> <full-sha256>

For the standard DockChannel kernel/initramfs loop:

    RIG_AGENT=$RIG_AGENT bash scripts/t6040-boot-dcuart.sh

Logs:

    tail -f ~/code/linux-build-out/raw-object-chainload.log
    tail -f ~/code/linux-build-out/dcuart-console.log

Send a command to the Linux tty:

    printf 'uname -a\n' > /tmp/m1n1

Use `scripts/t6040-bootcap-fb.sh <dtb> <initramfs>` only when the ticket
specifically requires panel-only observation.

## 3a. NVMe launchers (tickets 5006, 211/5003, 5008)

Each launcher checks the payload's `SHA256SUMS` (or the pinned m1n1 hash),
refuses to reuse an existing run directory, and boots through the lease
checks. They hardcode `RIG_AGENT=claude` / the `claude` lease; use them under
another handle only after changing that deliberately.

    # 5006: chainload the NVMe-fixed m1n1 7de07c71 over the rollback, then the
    # m1n1 proxy Flush probe (no data writes). Never nvme_init on the rollback.
    scripts/t6040-run-nvme-flush-probe.sh <run-dir>

    # 211/5003: exFAT write test; enforced 300 s host deadline after handoff.
    PAYLOAD=nvme-exfat-write-20261025c/payload \
      WRITE_ARGS='nvmewritedir=TAG nvmewc=through [nvmeend=reboot]' \
      scripts/t6040-run-nvme-write.sh write|verify <run-dir>

    # 5008: the NVMe daily-root steps (payloads nvmeroot-20261025/payload-*).
    # A = 6001 read tester on the new kernel; B = root installer (15 min
    # deadline); C = NVMe-root boot, console capture only.
    scripts/t6040-run-nvmeroot-step.sh A|B|C <run-dir>

Use the same `TAG` for a write and its verify. `macvdmtool reboot` is a hard
reset with no NVMe controller shutdown, which is what a verify boot tests.

**Rule for any system that mounts the internal SSD read/write:** set
`echo "write through" > /sys/block/nvme0n1/queue/write_cache` before the
mount (ANS2 rejects Flush), and end with `reboot`/`poweroff` so that
`device_shutdown` runs the NVMe controller shutdown. A crash or hard reset
loses the most recent writes. Writes stay confined to the label- and
GPT-type-verified exFAT `linux` partition.

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

Cleaner than copying over `$OUT/Image`: pass the pinned artifact directly with
`IMAGE=Image-<name>` (relative to `$OUT`) —

    RIG_AGENT=$RIG_AGENT IMAGE=Image-trackpad-reset-contract \
        bash scripts/t6040-boot-dcuart.sh <dtb> <initramfs>

The kernel marker check runs against whatever `IMAGE=` names, and `$OUT/Image`
never silently shadows the intended build (proven in the 230 and 108 runs).

An entire missing subsystem is never a hardware fault. Empty
`/sys/bus/pci/devices`, no `mmcblk0`, no `wlan0` and no `/dev/input` all at once
means the wrong kernel, and a sub-second failure timestamp means a startup race
or a wrong artifact — not a power rail.

## 6. Build a kernel

The host Linux tree is on a case-sensitive volume. Code changes are supplied
as patches; the build uses committed kernel state plus copied T6040 DT files.

    cp scripts/t6040-kbuild.sh patches/*.patch ~/code/linux-build-out/
    podman exec -e DOCKCHANNEL=1 -e BUILD_DIR=/build/linux-keyboard \
        kbuild bash /out/t6040-kbuild.sh image

Use only switches implemented by `scripts/t6040-kbuild.sh`. Relevant profiles
include `MACSMC=1`, `WIFI=1`, `PCIE=1`, `CPUFREQ=1`, and
`SD_GL9755=1`; for NVMe, `NVME=1 NVME_IOQ_SIZE=1` plus `NVME_EXFAT=1`
(requires `NVME_IOQ_SIZE=1`). Daily images add `NO_KVM=1` (ticket 5007).
`NVME_FLUSH_TCB=1` exists but is unused (5006 refuted it). The script must
assert every required built-in symbol after `olddefconfig`.

A clone from the build VM's local mirror is much faster than from `/src`:

    podman exec -e KBUILD_CLONE_SRC=/build/linux-mirror.git … kbuild \
        bash /out/t6040-kbuild.sh image

The build stops if the mirror's branch head differs from `/src`.

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
    DEST=~/code/linux-build-out/initramfs-dwm.cpio.xz \
      bash scripts/t6040-build-alpine-dwm.sh

The persistent root uses `scripts/t6040-sdroot-init`. Its filesystems are
currently dirty; do not mount them read/write outside approved ticket 215.
Build the pinned repair and hardened images with:

    scripts/t6040-build-sdroot-fsck-initramfs.sh
    scripts/t6040-build-sdroot-initramfs.sh

Ticket 215 must pass before ticket 216 applies `scripts/t6040-sdroot-apply`.

The NVMe daily root (5005) uses `scripts/t6040-build-nvmeroot-image.sh` (the
16 GiB ext4 root image), `scripts/t6040-build-nvme-root-install-initramfs.sh`
(the one-shot installer), and `scripts/t6040-gen-nvmeroot-init.py`, which
generates `scripts/t6040-nvmeroot-init` from the sdroot init plus the NVMe p3
pins and write-through.
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
    M1N1DEVICE=$d ~/code/m1n1/venv/bin/python \
      ~/code/m1n1/proxyclient/tools/shell.py

The m1n1 USB gadget and DebugUSB/KIS are mutually exclusive. Use
`/dev/cu.usbmodem*` for the dual-mode window and `/tmp/m1n1` for KIS.

## 10. Enrollment

Enrollment is maintainer-only from 1TR and requires a separately approved,
allowlisted object. Verify the target volume:

    diskutil info /Volumes/m1n1 | grep -E 'Volume Name|Volume UUID'

Expected dedicated volume UUID:

    B7FB1EC3-1BA0-4DCB-B57D-C8E9A0AE1E63

Hash-gated wrapper (the target is mandatory; each volume has its own allowlist):

    TARGET=/Volumes/m1n1 bash scripts/t6040-enroll-guard.sh <object.bin>

It prints the command and runs only with its explicit confirmation option.
`/Volumes/wallace` is the third startup entry for the standalone NVMe desktop
(ticket 5014). The guard refuses it until its Volume UUID and the 5014 object
hash are both pinned.
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

## 12. On the machine itself (standalone M4)

Agents may run on the M4 (COORDINATION.md on-device mode). The repo is at
`/mnt/sd/code/wallace` on the exFAT `linux` partition.

    export WALLACE_ROOT=/mnt/sd/code/wallace     # rig-lease.sh otherwise writes to $HOME/code/wallace
    cat /sys/block/nvme0n1/queue/write_cache       # must say: write through
    reboot                                         # clean path; never busybox reboot or reboot -f

Read-only inspection that needs no rig action:

    cat /sys/devices/system/cpu/possible /sys/devices/system/cpu/online
    cat /proc/iomem; ls /proc/device-tree/reserved-memory
    cp /sys/firmware/fdt /tmp/fdt                  # /memreserve/ entries are in the header
    zcat /proc/config.gz | grep CONFIG_
    ls /sys/fs/pstore                              # crash log from the previous boot

Tracing on the 5019 kernel (remove probes afterwards):

    cd /sys/kernel/tracing
    echo 'p:probe1 do_sys_openat2' >> kprobe_events; echo 1 > events/kprobes/probe1/enable
    echo 0 > events/kprobes/probe1/enable; echo '-:probe1' >> kprobe_events

Warm-reboot crash-log check (5020): `scripts/t6040-onboard-pstore-reboot.sh`,
then the same script with `check` after the reboot. The root filesystem is
16 GB: never fetch full kernel history onto it; use a depth-1 fetch into tmpfs.

## Shell notes

| Problem | Correct form |
|---|---|
| zsh errors on an unmatched USB glob | `/dev/cu.usbmodem*(N)` |
| serial open waits for carrier | use `/dev/cu.*`, not `/dev/tty.*` |
| environment assignment was separated by semicolons | put assignments on the same command |
| 1TR has no sudo | run the command directly |

## October refresh and tracing boundary

The next prepared storage run is ticket 5008 step C (first NVMe-root boot).
6001's read result stands. Ticket 6002 plans an isolated upstream integration candidate;
6003 plans a separate M4 Pro SPTM/emulation tracing environment. Neither is a
live procedure. Reconfirm fixture/boot-volume firmware before a later run;
September's unchanged-fixture statement is historical.

Use matched host proxyclient/target revisions, retain the enrolled rollback,
and include the chainload signature repair when refreshing m1n1. Login-screen
tracing can be useful despite post-login hangs; AMCC suppression is not a
validated cache fix. No commands from IRC supersede the lease, exact review,
or SPMI/SMC scope. See [the review](../evidence/2026-10-24-asahi-dev-review.md).
