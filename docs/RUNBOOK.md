# t6040 RUNBOOK — the commands, in one place

Every operational one-liner for the M4 Pro rig. Copy-paste ready. **zsh is the maintainer's shell**,
so globs use zsh's `(N)` qualifier where needed — see [zsh vs bash](#zsh-vs-bash-gotchas).

Background and history live in [DEVLOG.md](DEVLOG.md); the work queue in
[NEXT_STEPS.md](NEXT_STEPS.md). This file is only *how to run things*.

---

## 1. The tether: reboot into m1n1 and attach the console

```bash
bash scripts/t6040-debugusb-console.sh reboot
```

Does `macvdmtool reboot debugusb`, waits for the target, attaches `kisd`, and symlinks
`/tmp/m1n1 → /dev/ttysNNN`. Needs passwordless sudo (`sudo -n`); if it complains, run `sudo -v` first.

> **This is required before EVERY chainload, not just after a failure.** A successful chainload boots
> Linux, which *destroys the m1n1 proxy it needed*. Skipping this is what produced three silent
> 5-minute hangs on 2026-07-26.

Is anything actually behind the pty?

```bash
~/Code/m1n1/venv/bin/python scripts/t6040-proxy-alive.py --device /tmp/m1n1 --timeout 5
```

---

## 2. Chainload one raw object (tethered smoke)

```bash
bash scripts/t6040-boot-raw-object.sh <object.bin> <sha256>
```

No default object, by design — both arguments are required. The positional form is preferred because it
survives being pasted with `;` between values, which env-var assignments do not.

Watch it live (the log is unbuffered):

```bash
tail -f ~/Code/linux-build-out/raw-object-chainload.log
```

Is the upload healthy? Pin the pid — `pgrep | tail -1` silently switches processes and once made CPU
time appear to run *backwards*:

```bash
P=$(pgrep -f 'proxyclient/tools/chainload.py' | tail -1); echo "watching $P"; while kill -0 $P 2>/dev/null; do ps -o etime,time,%cpu -p $P | tail -1; sleep 5; done; echo exited
```

> **Diagnostic tell:** CPU time must climb past ~5 s within the first 10 s (connect + ADT fetch +
> transfer start). Pinned at `0:00.09` / 0.0% means **nothing is behind the pty** — re-run §1.
> Rate is ~0.7 MB/s, so a 28 MB object takes ~40 s and an 83 MB one ~2 min.

---

## 3. Take control during the dual-mode debug window

The enrolled daily driver waits **10 s** for a host, then boots dwm. The window exits on
`iodev_can_write()`, which for the USB gadget means the host asserted **DTR** — i.e. a program must
*open* the port. **Plugging the cable in is not enough**; the node appears on enumeration but macOS
does not assert DTR until something opens it.

Start this **before** rebooting so it is already polling:

```bash
while :; do d=(/dev/cu.usbmodem*(N)); [ -n "$d" ] && break; sleep 0.2; done; echo "found $d"; M1N1DEVICE=$d ~/Code/m1n1/venv/bin/python ~/Code/m1n1/proxyclient/tools/shell.py
```

The window uses m1n1's **USB gadget** on the DFU port, which is mutually exclusive with DebugUSB/KIS —
so `M1N1DEVICE=/dev/cu.usbmodem*`, **not** `/tmp/m1n1`.

If `shell.py` dies with `OSError: [Errno 22]` in `read_history_file`: macOS Python's readline is
**libedit**, which rejects a GNU-format history file, and `shell.py` catches only `FileNotFoundError`
and `PermissionError`. Fix once:

```bash
{ echo "_HiStOrY_V2_"; cat ~/.m1n1-history; } > /tmp/h && mv /tmp/h ~/.m1n1-history
```

---

## 4. Enrollment (1TR only, maintainer only)

**No `sudo`** — 1TR is already root and sudo is unavailable there.
The object does **not** need to be on the m1n1 volume: `-c` takes any readable path.

```bash
kmutil configure-boot -c /Volumes/S128/m1n1-b0-dwm-dualmode.bin --raw --entry-point 2048 --lowest-virtual-address 0 -v /Volumes/m1n1
```

Rollback to tethered development:

```bash
kmutil configure-boot -c /Volumes/S128/rollback-m1n1-1394c345.bin --raw --entry-point 2048 --lowest-virtual-address 0 -v /Volumes/m1n1
```

The one argument worth double-checking is `-v`, the target volume:

```bash
diskutil info /Volumes/m1n1 | grep -E "Volume Name|Volume UUID"
```

Expect `m1n1` and `B7FB1EC3-1BA0-4DCB-B57D-C8E9A0AE1E63`.

Optional hash-gated wrapper (validates, prints the command, only runs with `--confirm-enroll`):

```bash
bash scripts/t6040-enroll-guard.sh <object.bin>
```

**An enrolled object's total size must be a whole multiple of 16 KiB** or iBoot never enters m1n1 —
the builder pads and the verifier enforces it. Keep this distinct from the *kernel* page size.

---

## 5. Build and verify a boot object

```bash
python3 scripts/t6040-build-raw-object.py --m1n1 <m1n1.bin> --kernel <Image.xz> --dtb <board.dtb> --initramfs <initramfs.cpio.xz> --bootargs '<args>' <out.bin>
```

```bash
python3 scripts/t6040-raw-object-verify.py --strict --m1n1 <m1n1.bin> --kernel <Image.xz> --dtb <board.dtb> --initramfs <initramfs.cpio.xz> --expect-bootargs '<args>' <out.bin>
```

`--strict` pins every member by hash and the embedded bootargs; the output also reports the kernel's
`pages=4K`/`pages=16K`. Add `--initrd-fs-image` for a `root=/dev/ram0` filesystem payload, and
`--max-object-size` to raise the 256 MiB policy ceiling.

The proven B0 bootargs, whose hash is `3659a0da253c7059…` as
`sha256("chosen.bootargs=" + args + "\n")`:

```
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/sbin/init
```

xz members must be minilzlib-safe — single stream, single block, CRC32, no BCJ:

```bash
xz -9e --check=crc32 -T1 < in > out.xz && xz -lvv out.xz | grep -E "Streams|Blocks|Check"
```

**The expanded initramfs must stay under 128 MiB.** 13.1/50.8/60.5/97.3 MiB decode; 278.9 MiB makes
m1n1 print `XZ decode failed`, pass no initrd, and the kernel dies with `rdinit=/sbin/init failed: -2`.

---

## 6. Build a kernel

```bash
cp scripts/t6040-kbuild.sh patches/*.patch ~/Code/linux-build-out/
```

```bash
podman exec -e DOCKCHANNEL=1 -e BUILD_DIR=/build/linux-keyboard kbuild bash /out/t6040-kbuild.sh image
```

Useful switches: `DIET=1` (minimal, 4 KiB pages), `DIET_CAPABLE=1` (adds NET/WLAN/PCIE_APPLE, forces
**16 KiB pages**), `USB_HOST=1` with `USB_HOST_PORT=all|left-front|right`, `KBUILD_OVERWRITE=1` to
replace an existing artifact deliberately.

The page size is asserted from the built Image header before the artifact is published. **Never infer
page size from `strings`** — a 16 KiB Image contains a literal `4K pages` message. To check by hand:

```bash
python3 -c "import struct,sys;b=open(sys.argv[1],'rb').read(64);f=struct.unpack_from('<Q',b,24)[0];print({0:'unspec',1:'4K',2:'16K',3:'64K'}[(f>>1)&3])" <Image>
```

---

## 7. Build a root filesystem image

```bash
bash scripts/t6040-build-alpine-b0.sh                       # the proven B0 Alpine RAM root
DEST=~/Code/linux-build-out/initramfs-x.cpio.xz bash scripts/t6040-build-alpine-dwm.sh   # Xorg + dwm
```

`FAT=1` keeps llvmpipe/GL and the full font set — but the result expands past the 128 MiB initramfs
limit and **will not boot**. `T6040_DPI` (default 192) and `T6040_ST_PIXELSIZE` (default 28) tune the
HiDPI font sizes at boot; the panel's true DPI is ~254.

---

## 8. Rig lease and ticket queue

```bash
RIG_AGENT=claude bash scripts/rig-lease.sh acquire      # claim the singleton rig
RIG_AGENT=claude bash scripts/rig-lease.sh status
RIG_AGENT=claude bash scripts/rig-lease.sh release
```

Approve rig tickets (rig tickets only):

```bash
bash scripts/rig-lease.sh queue approve all --by maintainer
bash scripts/rig-lease.sh queue approve 149 --by maintainer
bash scripts/rig-lease.sh queue approve 160-169 --by maintainer
```

```bash
bash scripts/rig-lease.sh queue next --rig        # next approved+ready rig ticket
bash scripts/rig-lease.sh queue next --offline    # next open offline ticket
```

Every rig-touching script sources `rig-guard.sh`. With `RIG_AGENT` **unset** it warns and proceeds
(human at the keyboard); an *identified agent* without a live lease is refused.

---

## 9. Object-size probes

```bash
python3 scripts/t6040-build-graded-probe.py --m1n1 <loader.bin> --mib 512 <probe.bin>
```

```bash
PROBE_LIMIT_MIB=512 M1N1DEVICE=/dev/cu.usbmodemXXXX ~/Code/m1n1/venv/bin/python scripts/t6040-probe-load-extent.py
```

No ceiling was found to 256 MiB. **512 MiB has never been established** — it is untested, not proven.

---

## 10. Reading the machine's own state

Over the tether:

```bash
M1N1DEVICE=/dev/cu.usbmodemXXXX ~/Code/m1n1/venv/bin/python ~/Code/m1n1/proxyclient/tools/shell.py
```

On the booted machine — m1n1 exposes its own runtime as MTD devices, readable with no tether at all:

```bash
cat /proc/mtd                                          # mtd0 m1n1_stage2.log, mtd1 adt
dd if=/dev/mtd0 bs=1k count=16 2>/dev/null | strings   # m1n1's stage2 log
dd if=/dev/mtd1 of=/tmp/adt.bin bs=1k count=592        # the full ADT (0x94000)
```

Graphical diagnostics (the image ships them):

```bash
cat /var/log/xorg-startx.log; pgrep -a Xorg; pgrep -a dwm; ls -l /dev/input
```

> **The panel is the only source of kernel dmesg.** `console=ttydc0` is inert — the shipping
> DockChannel driver is a TTY only and registers no console — so a screenshot is necessary evidence
> for anything graphical.

---

## 11. Moving objects to the USB stick

```bash
cp ~/Code/linux-build-out/<object>.bin /Volumes/S128/ && shasum -a 256 /Volumes/S128/<object>.bin
```

```bash
sync && ls -la /Volumes/S128/*.bin
```

Always compare the post-copy hash: a truncated copy looks exactly like a mysterious boot failure later.

---

## zsh vs bash gotchas

| Symptom | Cause | Fix |
|---|---|---|
| `zsh: no matches found: /dev/cu.usbmodem*` | zsh `nomatch` errors on an unmatched glob instead of passing it through | `/dev/cu.usbmodem*(N)` |
| Env vars ignored by a script | `VAR=x; VAR=y; cmd` is **four commands** — the assignments are shell-local and never reach the child | space-separated on **one** command, or use the positional form |
| Opening a serial port hangs forever | `/dev/tty.*` blocks waiting for carrier | use `/dev/cu.*` |
| `sudo` does nothing | 1TR is already root; sudo is unavailable there | drop it |

---

## Current objects

| Object | Hash | What |
|---|---|---|
| `m1n1-b0-dwm-dualmode.bin` | `3aabde2d` | **enrolled daily driver** — 10 s window, else dwm |
| `m1n1-b0-dwm-hidpi.bin` | `59622e78` | same payload, window-free (tethered smokes) |
| `m1n1-b0-dwm-udev.bin` | `3ec81ef3` | first working dwm + keyboard, pre-HiDPI |
| `m1n1-b0-diet-aligned.bin` | `f290833c` | the B0 milestone (Alpine, untethered) |
| `rollback-m1n1-1394c345.bin` | `1394c345` | payload-free proxy loader — restores tethered dev |
| `m1n1-b0-ramroot-ext4.bin` | `ec111c6d` | `root=/dev/ram0` ext4 rehearsal (staged) |
| `m1n1-b0-dwm-fat.bin` | `c5438779` | **DOES NOT BOOT** — initramfs over the decode limit |
