# 5014 — three startup entries: rollback proxy, NVMe desktop, macOS

CJ (2026-10-25): boot the NVMe i3 desktop without the USB tether, as a third
entry next to the m1n1 DebugUSB proxy and macOS, and pick the default himself.

## The object

`/Users/damsleth/Code/linux-build-out/nvmedesk-20261025/wallace-nvmedesk.build1.bin`

| member | sha256 |
|---|---|
| object (build1 == build2) | `6a522d648cf8e48d03dbcc0fa5f29256b434f3a127eed9b9076e66c536abbd7c` |
| m1n1 (window-free, 80badc91) | `bf4b24627560759fcf460bb09ec6b0348274f4418bedb6003411a5d3e675d055` |
| kernel 2234baad, gzip member | `a0bad4deb78b9531d3f289ab70dea38e8c624e92d0ef81a319c63399452e6a52` |
| DTB | `6d2d3da60352c93a6973dc068addcb7d2b1fd05a504506eb580bb18293c48e20` |
| nvmeroot initramfs | `82a86064b3d440584b4ac484ff8f4da06ed10752036eeeeee5eb794026c9004d` |

25 559 040 bytes = 1560 × 16 KiB, entry 0x800, strict verify PASS, image
preflight OK, no proxy window. Bootargs are the 5008 C runs' cmdline verbatim
(`bootargs.txt` beside the object): `maxcpus=1 … console=ttydc0 console=tty0
rdinit=/init`. It is the C11 payload with only the m1n1 swapped from the
always-proxy `7de07c71` to the window-free `bf4b2462`.

## Gates before enrollment

1. **Tethered smoke boot** (rig, needs the lease and the M4 at the proxy):
   chainload the object over the rollback proxy with
   `scripts/t6040-boot-raw-object.sh`. Pass = desktop up, WiFi, keyboard,
   trackpad, then a powerctl reboot and a clean p3 (no dirty repair) on the
   next boot. Per the Codex review this does not reproduce iBoot's pristine
   ANS state (the rollback m1n1 has already adopted and shut down ANS), so it
   is necessary but not sufficient.
2. Add `6a522d64…` to `WALLACE_HASHES` in `scripts/t6040-enroll-guard.sh`.
3. CJ creates the volume (below) and pins its Volume UUID in the guard.
4. **First enrolled cold boot** from the picker, then a clean reboot and a
   p3 check. Only that proves the untethered case.

## CJ's steps (on the M4)

1. **macOS, Disk Utility:** select the internal container that holds
   `Macintosh HD` and `m1n1`, click **+** (Add APFS Volume), name it exactly
   `wallace`, APFS, no quota. Space is shared; it does not touch the exFAT
   `linux` partition.
2. **Install macOS 26 onto `wallace`** (the installer app or Recovery's
   *Reinstall macOS*, choosing the `wallace` volume). Create a throwaway admin
   user; this is how `m1n1` was made (first-light session, 2026-07-09).
3. **Read the UUID** from the main macOS and send it to me:
   `diskutil info /Volumes/wallace | grep -E 'Volume Name|Volume UUID|Role'`
   I pin it in the guard together with the object hash.
4. **1TR** (shut down, hold the power button → Options), Terminal:
   `csrutil disable` (pick `wallace` when asked), then
   `bputil -n -v /Volumes/wallace`. `Macintosh HD` stays at Full Security and
   `m1n1` keeps its own policy.
5. **Enroll** with the guard (main macOS, as for `m1n1`):
   `TARGET=/Volumes/wallace bash scripts/t6040-enroll-guard.sh <object>` and
   check the printed command, then re-run with `--confirm-enroll`.
6. **Pick the default:** hold power → choose `wallace` → hold Option/⌥ on it
   for *Always Use*, or System Settings → General → Startup Disk.

## Caveat: the default also decides where remote reboots land

`macvdmtool reboot debugusb` restarts into the default entry. With `wallace`
as the default the agents' recovery lands in the NVMe desktop, not the proxy,
so rig work needs `m1n1` selected first (picker, or Startup Disk from the
desktop is not available — use the picker). Recommendation: keep `m1n1` the
default while agents hold rig tickets; switch to `wallace` for daily use.
