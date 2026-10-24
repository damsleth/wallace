# SD-root clean shutdown: host regression and three fixed defects (ticket 3006)

Claude, 2026-10-24. Offline Apple Silicon Linux hardware enablement work. No
rig lease, T6040 access, SD-card access, enrollment, image build or external
post. The harness ran in the local podman VM on loop-backed image files.

## Result

The staged clean-shutdown path (ticket 204 design, pinned unchanged in ticket
216's reviewed object `bdd8cc86…`) **could not unmount the SD root on the
real system**. Three independent defects each defeat it. All three are fixed in
`scripts/t6040-sdroot-init` and `scripts/t6040-sdroot-shutdown`, and a host
regression harness now exercises the real scripts against real kernel mount
semantics:

| Run | Scripts | Verdict |
|---|---|---|
| baseline | `--rev HEAD` = `a57682f`: shutdown `afb2433e…` and powerctl `791c0f8a…` (byte-identical to 216's pins); init `c434eb1d…` (same shutdown-tmpfs block as 216's `d0f55c56…`) | **0 / 23 PASS** |
| fixed | working tree as committed here: init `95f1e268…`, shutdown `c5c05855…`; powerctl, inittab, OpenRC wrapper unchanged | **23 / 23 PASS** |

Every fixed clean case ended in the requested action with no ext4 or exFAT
mount left, the root loop detached, exFAT `VolumeFlags`=0, and both
`fsck.exfat -n` and `e2fsck -fn` clean. Every injected failure fired and ended
in the rescue shell. No power action ran with a filesystem mounted, and no
loop device leaked. Both runs used the same harness (`ns.sh` `e322b8bf…`),
initramfs BusyBox `61781806…`, Alpine 3.24.0 card BusyBox `97d52efa…` and
digest-pinned container image. Manifests, case tables, results, verdicts,
package versions, run logs and per-case traces are in
[2026-10-24-t6040-3006-sdroot-shutdown/](2026-10-24-t6040-3006-sdroot-shutdown/)
(`baseline/` and `fixed/`).

Reproduce (podman machine running; about 3.5 minutes per run):

```bash
scripts/t6040-test-sdroot-shutdown.sh --rev a57682f   # expect 0/23, exit 1
scripts/t6040-test-sdroot-shutdown.sh                 # expect 23/23, exit 0
```

## The defects

1. **OpenRC hides the shutdown tmpfs.** `/init` mounted the shutdown tmpfs at
   `/run/initramfs` but left `/run` a plain directory on the ext4 root. OpenRC
   0.63.2 (`openrc-0.63.2-r0.apk`, `usr/libexec/rc/sh/init.sh:72-83`) mounts a
   fresh tmpfs over `/run` whenever `/run` is not a mountpoint. The 2026-08-19
   SD-root boot transcript (`linux-build-out/dcuart-console.log:2087`) shows
   `* Mounting /run ... [ ok ]`. From then on `/run/initramfs/shutdown` does
   not exist. `poweroff`/`reboot` (symlinks to powerctl) print `shutdown tmpfs
   is unavailable` and exit 1 without signalling init, and Ctrl-Alt-Del uses
   the same powerctl. A direct SIGQUIT makes BusyBox init run `::shutdown`,
   kill everything, fail to exec the `::restart` target and call
   `reboot(RB_HALT_SYSTEM)` with both filesystems still mounted read-write
   (busybox 1.37 `init.c:842-880`, `pause_and_low_level_reboot`). Reproduced:
   `clean-openrc-*`/`clean-mountro-*` end `refused`, and `clean-mountro-sigquit`
   ends `init-halted`.
2. **The ext4 remount needs `/proc`.** After `pivot_root` the old script
   mounted only devtmpfs. The initramfs BusyBox (Debian 1.35.0, `61781806…`)
   implements `mount -o remount` by reading `/proc/mounts` and fails with
   `can't read '/proc/mounts'` (isolated probe: rc=1 without proc, rc=0 with
   it). So even without OpenRC (`clean-bare-*`) the old path stops at
   `remount,ro /oldroot` and drops to the rescue shell with ext4 and exFAT
   mounted. It fails closed, but it never completes.
3. **OpenRC's submounts block the old-root unmount.** The old script unmounted
   only `/oldroot/{dev/pts,dev,proc,sys}`. OpenRC sysinit also mounts `/run`,
   `/dev/mqueue`, `/dev/shm`, securityfs, debugfs, configfs, pstore and bpf
   (all eight appear in the same transcript). `mount-ro` deliberately skips
   `/dev/*`, `/sys/*` and `/run`, so they survive into the pivot, and
   `umount /oldroot/dev`, `/oldroot/sys` and `/oldroot` would be EBUSY.
   `mount-ro` does unmount the `/mnt/sd` bind (observed: `umount -r /mnt/sd:
   ok (unmounted)`), so an unconditional `umount /mnt/sd || fail` would also
   stop the path.

None of this was visible earlier because the clean path never ran on the
device: no transcript or evidence records a `sdroot-shutdown` line.

## The fix

`scripts/t6040-sdroot-init` (block after "Preserve only the shutdown tools"):

- mount a tmpfs on `/newroot/run` with OpenRC's own options
  (`mode=0755,nosuid,nodev,nr_inodes=800k,size=20%,strictatime`) so OpenRC
  sees a mountpoint and leaves it alone, then mount the shutdown tmpfs at
  `/run/initramfs` below it. `pivot_root` needs it to be its own mount;
- pre-create `dev` and `proc` in the shutdown tmpfs, because `mount-ro`
  remounts it read-only when it cannot unmount it;
- `cleanup_root` also unmounts `/newroot/run`.

`scripts/t6040-sdroot-shutdown`:

- unmount `/mnt/sd` only if it is still mounted;
- after the pivot, mount `proc` as well as `devtmpfs`;
- unmount every `/oldroot/*` mount newest-first from `/proc/mounts`
  (re-checking each so stacked mounts peel), then remount `/oldroot`
  read-only, unmount it, detach the loop and unmount `/sd` as before;
- **postcondition:** power off or reboot only if `/proc/mounts` has no `/sd` or
  `/oldroot` entry and the loop device is detached; otherwise fail to the
  rescue shell.

Unchanged: powerctl, inittab, the OpenRC wrapper, the PID-1 check, action
validation, `sync` placement and the fail-closed rescue shell. BusyBox 1.35
`mount` accepts `strictatime`, and the harness exercises it through the same
binary.

## The harness

`scripts/t6040-test-sdroot-shutdown.sh [--rev REV] [--out DIR]` (driver) and
`scripts/t6040-test-sdroot-shutdown-ns.sh` (container side). Per case:

- fresh exFAT `SD64` on a loop device, holding a fresh ext4
  `wallace-root.img` with the real root UUID;
- a new PID+mount namespace makes a tmpfs its root and replays `/init`. The
  shutdown-tmpfs block is **copied verbatim** from the variant's init, and the
  identity gates before it (PCI, label, flags) are replaced by direct mounts;
- `switch_root` uses the reviewed initramfs BusyBox (`initramfs-sdroot-daily-v2`,
  `7fe674e2…`). PID 1 is the card's BusyBox init from the hash-checked
  `alpine-minirootfs-3.24.0` (1.37.0-r31). It runs the variant's real inittab,
  `t6040-sdroot-openrc`, early-console and powerctl, with `poweroff`/`reboot`
  symlinked as `t6040-sdroot-apply-remote` installs them;
- `/sbin/openrc` is a stub replaying OpenRC 0.63.2's sysinit mounts (exact
  options from `init.d/devfs` and `init.d/sysfs`, set matched to the
  transcript) and optionally `mount-ro` (its skip regex, newest-first
  `umount -r`);
- the variant's shutdown program runs **unmodified** as PID 1. Its `$BB` is a
  shim that logs each applet, injects one failure on request and never
  forwards `poweroff`/`reboot`/`halt`. It execs the real BusyBox otherwise;
- verdict: a clean request must end in the requested action with zero ext4 and
  exFAT mounts in the namespace, the exact root loop detached, and
  `fsck.exfat -n` plus `e2fsck -fn` clean. An injected failure must fire and end
  in the rescue shell. Any power action with a filesystem still mounted is
  flagged separately.

Cases: three topologies (`bare`, `openrc`, `openrc+mountro`) × poweroff/reboot
via powerctl, a SIGQUIT straight to init with `mount-ro`, an invalid action,
and 15 single-phase injections on the `openrc` topology. The injected phases
are the `/mnt/sd` unmount, pivot, proc, devtmpfs, `/oldroot/dev/shm`, `dev`,
`proc`, `sys`, `run`, the remount, the ext4 unmount, the loop detach, the exFAT
unmount, a forged still-mounted postcondition and a forged still-attached loop.

### Model limits

- The VM kernel is Fedora 6.12, not the T6040 kernel. Mount, pivot_root,
  devtmpfs, loop and exFAT/ext4 semantics are generic VFS behaviour. The
  harness does not cover hardware behaviour of the final `poweroff -f`/
  `reboot -f`, which the 216 review already treats as a separate blocker
  (the PMU-backed reboot node is disabled; the final action may no-op).
- The card's runlevels are not recorded anywhere. The transcript shows
  Alpine-default boot services, so `mount-ro` in the shutdown runlevel is
  plausible but unproven; both cases pass.
- OpenRC is replayed, not executed. The replayed commands are copied from
  the exact package with file references above. `killprocs` is covered by
  BusyBox init's own SIGTERM/SIGKILL sweep before `::restart`.
- `bootmisc` is not replayed. It is absent from the transcript, and its only
  `/run` step, `clean_run` (`init.d/bootmisc:128-156`), bind-mounts `/`
  non-recursively and deletes the *underlying* ext4 `/run`. Submounts do not
  appear in such a bind, so the new `/run` tmpfs and the shutdown tmpfs are
  out of its reach even if bootmisc is enabled.
- The `/init` identity gates are not exercised. Only its shutdown-tmpfs
  block runs.
- The DockChannel `ttydc0` node is a symlink to `/dev/null` in the VM.
  BusyBox init's respawn noise is collapsed in the console logs.

## Harness pitfalls found on the way (recorded so nobody re-derives them)

- A non-interactive shell starts `&` jobs with SIGINT/SIGQUIT ignored, and
  BusyBox init never resets them. A real init starts with all signals at
  SIG_DFL, so the harness restores that with `env --default-signal`.
- **Alpine 3.22's BusyBox 1.37.0-r20 silently drops every `::restart`
  entry.** Its downstream "separate reboot action" patch moved `RESTART` to
  `0x100` but left `struct init_action.action_type` as `uint8_t`. Alpine fixed
  it in aports `c792a061` (2025-08-30), and 3.23/3.24 (`-r30`/`-r31`) carry the
  fix. Probe: 3.22 → no shutdown, no restart. Debian 1.35 and Alpine 3.24 →
  both run. The card is 3.24 (OpenRC 0.63.2; 3.22 ships 0.62.6), so this does
  not affect the device, but **any SD root rebuilt from a 3.22 rootfs would
  lose the clean shutdown path without an error.**
- Inside a namespace a loop device's recorded backing path is the namespace
  path, so cleanup tracks devices, not paths. Killed namespaces release mounts
  asynchronously, so a final sweep retries the detach.

## What this changes

- **Ticket 216 must not run with object `bdd8cc86…`**: its pinned init block,
  shutdown and powerctl are the baseline that scores 0/23. The daily object has
  to be rebuilt from these scripts, byte-reproduced, preflighted (Norwegian
  keymap included) and independently exact-reviewed before 216 can become ready
  (ticket 5000). 301/4003's trackpad-integrated daily object must carry the
  same fixed scripts.
  Its init/inittab pins were already stale against HEAD
  (`d0f55c56…`/`d92897ff…` vs HEAD `c434eb1d…`/`f5e1628e…`).
- Ticket 215 (repair) is unaffected.
- The harness is the regression gate for any further change to the shutdown
  path; it needs no fixture, rig or lease.
