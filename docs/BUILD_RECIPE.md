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

## Maintenance rule

**Every error, quirk, one-off, or surprise hit during a build goes in the section
below, in the same change that hit it.** Not in a commit message, not only in
`DEVLOG.md`, not in agent memory — here, where the next build reads it. If it
cost more than a minute to work out, it belongs here. If it can be checked
mechanically, it also belongs in `t6040-image-preflight.sh`.

## Build quirks and one-offs

Each entry is *symptom → cause → fix*, so it can be recognised before it is
understood.

### Host shell (zsh on macOS)

- **`ls -t` fails: `invalid value '<file>' for '--time'`.** `ls` is aliased to
  `eza`, which has a different `-t`. Use `command ls -t` for real mtime ordering,
  and `command ls -l` when parsing size/date fields. `eza`'s long format also
  prints permissions as `.rw-r--r--`, which does not match scripts expecting
  `-rw-r--r--`.
- **A list in a variable expands as ONE argument**: `git add -- $FILES` fails
  with `pathspec '... ...' did not match any files`. zsh does not word-split
  unquoted parameters. Loop instead:
  `for f in $(...); do git add -- "$f"; done`.
- **`pgrep -c <pattern>`** needs the pattern as an operand; `pgrep -cf x` is
  fine but `pgrep -c` alone prints usage. Prefer
  `ps -ax | grep -c '[c]at /tmp/m1n1'`.
- **Piping a script to `sh -s` while it also reads stdin** silently produces
  0-byte files, then `Exec format error`. Pass the script as an argument:
  `ssh host "$(cat script.sh)"`.
- **`sleep` in the foreground is blocked by the harness.** Use an until-loop on
  the actual condition, and never background a rig command to work around it.

### Git

- **`core.fileMode=true` here, and several scripts were committed `0644`**, so
  `./scripts/t6040-boot-dcuart.sh` fails with *permission denied* (exit 126) on a
  fresh clone. Fix a mode-only change with `git add --chmod=+x -- <path>`.
  Check with `git diff --summary` (mode changes show as
  `mode change 100644 => 100755`).
- **`git reset --hard` orphans patch-created files**; follow with
  `git clean -qfd` or a later build asserts on a stale tree.

### Container, apt, and compiling

- **`deb-src` lives in `/etc/apt/sources.list.d/debian.sources`** on bookworm
  (deb822 format), not `sources.list`. Enable with
  `sed -i 's/^Types: deb$/Types: deb deb-src/'`.
- **`apt-get source` warns** `Download is performed unsandboxed as root … (13:
  Permission denied)`. Benign — the source still unpacks.
- **libtool silently ignores a plain `-static` in `LDFLAGS`, and a PIE default
  defeats it too.** `./configure LDFLAGS="-static"` produced a *dynamically
  linked* binary; `CFLAGS="-no-pie" LDFLAGS="-static -no-pie"` produced a 68 KiB
  binary still linked against libc. The flag that works is
  `make LDFLAGS="-all-static"` (732 KiB). **Always confirm with `file`** —
  it must say *statically linked* — and with `ldd` reporting
  *not a dynamic executable*.
- **Debian has no Mac-Norwegian keymap**; `/usr/share/keymaps/mac/` carries only
  German variants. Use `i386/qwerty/no-latin1.kmap.gz`.
- **The kbuild container clone must be synced** (`git fetch`, `reset --hard`,
  `clean -qfd`) or cherry-picks never reach the binary. Assert the driver is
  actually present in the built Image afterwards.

### Initramfs and busybox

- **cpio member paths are `./init`, not `init`.** `cpio -i --to-stdout init`
  extracts nothing and looks like a missing file; `grep -qx "./$item"` is the
  correct membership test.
- **busybox provides `loadkmap`, not kbd's `loadkeys`**, and ships **no applet
  symlinks** in this image — invoke everything as `busybox <applet>`. A bare
  `mkdir` or `switch_root` exits 127 and the kernel reports
  *Attempted to kill init*.
- **The builder writes `initramfs-sdroot-hardened.cpio.gz`**, not
  `initramfs-sdroot.cpio.gz`. Booting the latter silently uses an older image.
- **`t6040-make-initramfs.sh` installs `EXTRA_FILES` with mode 0644**, so a
  helper script shipped that way is not executable. Invoke it as
  `busybox sh /bin/<script>` (the ticket-230 fixture does this for
  `t6040-input-report`), or install it via a proper builder that sets 0755.
- **`mount --move` can fail silently**, leaving `/newroot/dev` empty. Mount
  devtmpfs explicitly.
- **Alpine has no `/sbin/agetty`**, and busybox `init` does no shell quoting in
  `inittab` — redirections arrive as literal argv. Use the inittab id field as
  the tty.
- **A shell with inherited stdin has no controlling terminal**: busybox prints
  `can't access tty: job control turned off` and ignores every keypress. Rescue
  shells need `setsid -c` on a real VT, and the console loglevel dropped first,
  or `apple-pmgr-pwrstate sync_state()` scrolls the prompt away and a working
  shell looks dead.

### Object packing and verification

- **The packer compresses an uncompressed `Image` internally**, so
  `raw-object-verify.py --strict` then fails with
  `kernel bytes/hash do not match supplied artifact`. Use `--kernel-output` and
  verify against the saved member.
- **Object size must be a whole multiple of 16 KiB** or iBoot never runs it. The
  packer pads and reports `-> 16 KiB-aligned object (N pages)`.
- **Pick the m1n1 deliberately.** Window-free boots straight through;
  always-proxy waits for a host and is correct *only* for the rollback object.
- **Check what the object CONTAINS, not a file next to it.** Verifying a
  standalone initramfs proves nothing about the object — the two can diverge.
  `t6040-image-preflight.sh --object` now carves the embedded initramfs out and
  inspects its members directly. CJ caught this gap by asking the obvious
  question "does the object actually have fsck.exfat in it?".
- **Member offsets AND sizes shift whenever any member changes size.** Reusing
  an offset/length pair noted from a previous build truncates the stream and
  yields `EOFError: Compressed file ended before the end-of-stream marker`, plus a
  hash mismatch that looks like a corrupted object. Re-read them from
  `raw-object-verify.py` output each time.
- **When scanning a blob for the embedded cpio, require the `newc` magic
  `070701` at offset 0.** A false `\x1f\x8b\x08` inside another member can
  decompress to data that merely *contains* `TRAILER!!!`; `cpio -t` then returns
  an empty listing and every member check reports a confident false failure.
  Also note `gzip.decompress()` rejects trailing data, so fall back to
  `zlib.decompressobj(MAX_WBITS | 16)` when carving a member out of a larger file.

### Rig invocation

- **`t6040-boot-dcuart.sh` takes filenames relative to `$OUT`.** Passing an
  absolute path yields a doubled path:
  `/…/linux-build-out/Users/damsleth/…/foo.dtb: No such file`.
- **Never redirect rig-script output to `/dev/null`.** A lease expiry prints
  `rig-guard: REFUSE` and exits; hidden, the next step reads a **stale** console
  log and every conclusion drawn from it is invalid.
- **Never leave a rig command polling in the background.** A stranded
  `until grep 'Running proxy'` loop woke up on a later reboot and launched a
  second `boot-dcuart.sh` concurrently, giving
  `UartTimeout: Expected 1 bytes, got 0 bytes`.
- **`debugusb-console.sh reboot` leaves its own reader** that fights the next
  proxyclient; `boot-dcuart.sh` detaches the old reader itself, so do not
  `pkill` it by hand. Contention looks like a console log frozen at m1n1's own
  ~625 bytes / 20 lines.
- **Do not delete a console log while a reader holds it open** — output goes to
  the unlinked inode and a good boot reads as empty.
- **`rig-guard` exits before any in-script checks**, so a guard added to
  `boot-dcuart.sh` cannot be tested with a fake `RIG_AGENT`.

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

### SD-root / initramfs interaction (added 2026-08-04)

- **`/init` refreshes the card's helpers every boot, so anything the card has
  that our copies lack is DESTROYED.** This cost two regressions in one session:
  refreshing `/etc/inittab` removed the card's `ttydc0` getty (losing all remote
  access) and then its `t6040-startx` entry (losing the GUI). **Rule: the shipped
  `inittab` must be a superset of everything the card is expected to run**, and
  the refresh must ship the whole dependency closure of what it installs.
- **Keep one dependency-free serial shell.**
  `ttydc0::respawn:/bin/busybox sh -l` cannot fail for a missing helper, unlike
  `early-console` → `t6040-b0-ttydc0-console` → `getty` + autologin. Losing the
  serial shell while a window-free object is enrolled means **no way in at all**.
- **The X0 socket existing does not mean X accepts connections.** A `setxkbmap`
  call right after the socket appears fails with `Cannot open display ":0"`, and
  `XAUTHORITY` must be set explicitly. Retry until it succeeds and log the result;
  a silenced failure leaves a working desktop in the US layout.
- **An empty WiFi scan is not broken WiFi.** A stale (or self-colliding)
  `wpa_supplicant` starves the radio: `iw scan` returned 0 networks, and after
  `killall wpa_supplicant` the same scan returned 75. The giveaway in the log is
  `nl80211: kernel reports: Match already configured`.
- **Verify by booting the real object, not the build.** Both regressions above
  passed every static check and were only caught by `t6040-boot-raw-object.sh`
  plus a live query over the serial shell.

### Desktop, input and locale on the SD root (added 2026-08-04)

All of these looked like driver or hardware faults and were none of them.

- **X gets NO input devices unless `udevd` is running.** `libinput_drv.so` being
  installed is not enough — Xorg autoconfigures input through udev, and without
  it silently starts with zero devices while logging *"If no devices become
  available, reconfigure udev or disable AutoAddDevices"*. The console keyboard
  keeps working, so it looks like an X or HID bug. Start `udevd --daemon`,
  `udevadm trigger` (subsystems **and** devices) and `udevadm settle` before X.
- **Do not run X on a VT that also has a login shell.** `inittab` respawns a
  shell on `tty1`; with Xorg on `vt1` the shell owns the terminal and keystrokes
  never reach X. Xorg runs on **vt2**, which also leaves Ctrl+Alt+F1 as a rescue
  console. Confirm with `cat /sys/class/tty/tty0/active` — it must name X's VT.
- **`Xft.dpi` scales pango (i3, i3bar, i3status) but NOT `st` or `dmenu`**, which
  are built with a fixed `pixelsize` font spec and ignore DPI completely. They
  need an explicit `-f`/`-fn`. Current values: `Xft.dpi: 192`, `st -f
  monospace:pixelsize=28`, i3 `font pango:DejaVu Sans Mono 10` — the pango size
  stays 10 *because* Xft.dpi already doubles it; raising it to 16 made the bar
  and tab titles far larger than the terminal.
- **`Xcursor.size` does nothing without a cursor THEME.** With only `hicolor`
  installed (no `cursors/` directory) X falls back to the fixed-size core cursor
  bitmap, so the pointer stays tiny while text scales correctly. The Adwaita
  cursors are bundled in the initramfs (~1.3 MiB compressed, 124 files) rather
  than `apk add`ed, so a machine with no network still gets a usable pointer.
  `XCURSOR_THEME`, `XCURSOR_PATH` and `Xcursor.theme` must all be set.
- **st's zoom keys are unreachable on this keyboard.** `Ctrl+Shift+Page Up/Down`
  needs `Fn+Up/Down` on an Apple keyboard; set the font explicitly instead.
- **i3's modifier is `Mod4` = the ⌘ key** (`/etc/i3/config`). With no terminal
  open, ordinary keys produce no visible response, so a perfectly working
  keyboard reads as dead. `⌘+Enter` opens `st`. Before declaring input broken,
  measure it: `timeout 60 cat /dev/input/eventN > /tmp/x.raw` then `wc -c`.
  That bypasses X, udev and libinput entirely and gives a yes/no in one number.
- **Only one `wpa_supplicant` may run.** OpenRC's `net` runlevel starts its own;
  a second instance does not fail loudly — it logs `nl80211: kernel reports:
  Match already configured` and starves the radio, so `iw scan` returns **zero**
  networks and it reads as broken WiFi. Cooperate with a running instance rather
  than `killall`-then-restart, which just races OpenRC's supervisor.
- **`iw scan` returning 0 while a supplicant runs is normal** — the supplicant
  owns scanning. Ask it instead: `wpa_cli -p /run/wpa_supplicant -i wlan0
  scan_results`.
- **`ctrl_interface=/run/wpa_supplicant` must be in the config**, or `wpa_cli`
  cannot attach and every diagnostic is blind.
- **udhcpc needs `-s /usr/share/udhcpc/default.script`.** Without it a lease
  cannot be applied; give it generous retries, because the AP may not answer
  DHCP for a few seconds after association.
- **`/etc/localtime` is absent on a fresh card**, so the whole system runs UTC
  and the bar clock is two hours behind Oslo in summer. The zoneinfo database is
  already present — only the symlink is missing.
- **wpa credentials are refreshed from the image every boot.** Installing them
  only-if-absent stranded the card on a one-network config while the host file
  had three, so the machine hunted for an out-of-range SSID. `~/wpa.conf` on the
  host is the source of truth.

### Host shell aliases (superseded 2026-08-04)

CJ has removed the `cat`→`bat` and `ls`→`eza` aliases. Both had caused real
damage: **`cat ~/file` piped through `bat` injects ANSI colour codes and
box-drawing characters**, which corrupted a config being written to the machine
over the serial console. If a heredoc arrives mangled, suspect a pager alias and
use `command cat`.
