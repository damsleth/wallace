# SD-root: a persistent Alpine system on the SD card (ticket 204)

2026-08-03 autonomous session. Built on the 193 SD result. **Boots and switch_roots; userspace
services not yet up** — status and the exact remaining work are at the bottom.

## Why this architecture

The 99 MB i3 RAM image loses a race during boot: it booted at maxcpus **1 and 4** but hung at
**3 and 5**, and earlier booted once at 5. Non-monotonic ⇒ a **race**, not a maxcpus threshold;
the big initramfs just widens the window. So the fix is to stop shipping a big initramfs at all.

Layout, deliberately non-destructive to CJ's card (**no repartitioning, no reformat**):

```
SD p1 (exFAT, CJ's own)  ->  /mnt/sd
  wallace-root.img       ->  6 GiB ext4 image, loop-mounted as /
initramfs-sdroot.cpio.gz ->  1.8 MB expanded (55x smaller than the i3 image)
```

Requirements all builtin already: `BLK_DEV_LOOP=y`, `EXT4_FS=y`, `EXFAT_FS=y`, `MMC_BLOCK=y`.

## What works

- `mkfs.ext4` + loop mount on the card: **OK**
- Alpine bootstrapped with `apk --root`: **197 packages, 377 MB** — i3, Xorg, st, dmenu, wpa_supplicant,
  bluez, openssh, e2fsprogs, git/vim/htop, tzdata, Norwegian keymaps
- `initramfs-sdroot` mounts the card, loop-mounts the image, and **switch_roots**: `sdroot:
  switching to the SD root`, `Freeing initrd memory: 960K`
- **OpenRC starts from the SD root**: `OpenRC 0.63.2 is starting up Linux 7.1.3 (aarch64)`

## The SMP bug is broader than "unpack_to_rootfs"

The SD-root boot at maxcpus=5 produced `copy_page → copy_user_highpage → do_wp_page` — a
**copy-on-write** fault, not an initramfs unpack fault, but the same memory-corruption family.
At **maxcpus=1 the same boot produced zero call traces.** So this is a general MM/SMP fault on
this hardware that initramfs unpack merely exercises first and hardest. Ticket 121's framing
("maxcpus>=6 faults in unpack_to_rootfs") is too narrow and should be rewritten.

## Three self-inflicted bugs worth remembering

1. **`sh -s` eats heredocs.** Piping a config script to `ssh 'sh -s'` makes every internal
   `cat > file <<EOF` read from the *same stdin*, so files land **0 bytes**. `t6040-net-up` and
   the console script were empty — an empty file execs as **"Exec format error"**, which is what
   the panel showed. Fix: pass the script as an *argument* (`ssh host "$(cat script.sh)"`).
2. **The minimal initramfs busybox has only 10 applet symlinks** (busybox, cat, dmesg, echo, ls,
   mount, poweroff, sh, sleep, uname). `mkdir` and `switch_root` have none, so calling them bare
   exits 127 → `Attempted to kill init! exitcode=0x00007f00`. Always invoke via `$BB applet`.
3. **Alpine has no `/sbin/agetty`.** `tty1::respawn:/sbin/agetty …` spins forever with
   "No such file or directory". Use busybox `setsid sh -i <>/dev/ttyX`.

## Status and what remains

The system switch_roots and OpenRC runs, but **no console appears on ttydc0 or tty1 and sshd does
not come up**, so the boot cannot yet be driven. The inittab was rewritten (console entries first,
busybox-only, no wrapper scripts, `openrc default` demoted to `::once:` so it can never block the
console) and `authorized_keys` repaired (98 bytes), but the boot after those fixes still showed no
console. Next steps, in order:

1. Read the **panel** (`console=tty0`) during an SD-root boot — it carries OpenRC's output and any
   init error, and is independent of whatever is failing on ttydc0.
2. If OpenRC is hanging, drop it entirely for a first pass: inittab with only the two console
   respawns and `::once:` networking; add services back one at a time.
3. Once a console exists, verify persistence (`/root/boot-log.txt` accumulates a line per boot),
   then start X and confirm i3 on the panel.

Artifacts: `initramfs-sdroot.cpio.gz` (`1a8c4599…`), `initramfs-bootstrap-sdroot.cpio.gz`
(`ae815319…`, headless WiFi + e2fsprogs + apk, 49.8 MB — the image used to build and repair the
card, reachable over SSH at 192.168.10.157). `scripts/t6040-sdroot-init` is the switch-root init.

---

# ✅ RESOLVED: the SD root works, and the whole blocker is ONE kernel bug

## It works

Booted with `/sbin/init` at `maxcpus=1`:

```
sdroot: newroot /dev ok (ttydc0 present)
sdroot: switching to the SD root
   OpenRC 0.63.2 is starting up Linux 7.1.3-gcd5da1d058e3-dirty (aarch64)
 * Starting System Message Bus ... [ ok ]
 * Starting Bluetooth ... [ ok ]
~ # hostname; nproc; df -h /
t6040
1
/dev/loop0   5.8G   371.3M   5.1G   7%   /
```

**Persistence proven across a reboot** — `/root/boot-log.txt` accumulated:

```
boot Mon Aug  3 06:47:30 UTC 2026
boot Mon Aug  3 06:50:51 UTC 2026
```

Two different timestamps, written by two separate boots to the SD card. Note the dates are real:
the SPMI/abbey RTC work is holding. Also confirmed live in this system:
`/sys/class/leds/kbd_backlight` exists, `max_brightness` 255, and writing 255 succeeds — the fpwm0
+ pwm-leds wiring from 2026-07-30 is functional at the sysfs level.

## The single remaining blocker, isolated

`sdroot.shell` (switch_root into the SD root but exec a plain shell instead of init) gave the clean
answer:

| maxcpus | result |
|---|---|
| 4 | shell **SIGSEGV** (`exitcode=0x0000000b`), `copy_page → do_wp_page`, panic |
| 1 | **zero call traces, zero panics**, working shell, correct root |

So the SD-root architecture is entirely sound and **every** daily-driver symptom we have been
chasing — the i3 image failing to boot, the SD-root userspace dying, the `unpack_to_rootfs` fault —
is the *same* kernel memory bug appearing under SMP. It is not initramfs-specific, not image-size
specific, and not architecture-specific to this design; those factors only change how likely the
race is to fire.

**Consequence for the project:** a persistent, complete Alpine daily driver on the SD card exists
today at `maxcpus=1`. Getting it to 4-5 cores is now a single, well-scoped kernel bug rather than a
pile of unrelated boot failures. Ticket 121 should be rewritten around `do_wp_page`/`copy_page` CoW
corruption under SMP, with the `unpack_to_rootfs` signature demoted to one symptom among several.

## How to boot it

```
EXTRA_BOOTARGS='maxcpus=1 console=ttydc0'   initramfs-sdroot.cpio.gz
```

Add `sdroot.shell` to get a bare shell instead of init (diagnostics). The card holds everything;
edit files on it directly instead of rebuilding an object.
