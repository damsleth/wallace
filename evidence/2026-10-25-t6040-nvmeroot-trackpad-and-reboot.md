# Trackpad dead on the NVMe root: Codex diagnosis (2026-10-25)

Requested by CJ; claude ran Codex (agent-bridge, medium, read-only) and verified the key evidence. NVMe-root consoles (C1 and later): `dockchannel-hid 514600000.hid: Direct firmware load for apple/tpmtfw-j614s.bin failed with error -2` at 2.49 s, after `switching to the verified SD root` at 1.81 s. The initramfs carries the blob, but the host-built root (tree.txt) has no `lib/firmware/apple`. dockchannel-hid requests the firmware on first open, after switch_root. The keyboard does not need it. Fix (with the powerctl symlinks for the dirty-exFAT-on-reboot bug): `scripts/t6040-gen-nvmeroot-init.py` NVME_EXTRA, which copies the hash-pinned blob into the new root and links `/usr/local/sbin/{reboot,poweroff}` to `t6040-sdroot-powerctl` on every boot. The dirty flag was confirmed by a read-only m1n1 NVMe read of the p3 boot sector after CJ's plain `reboot`: VolumeFlags = 2. On the root, `ls /usr/local/sbin` shows powerctl but no reboot/poweroff links; `which reboot` gives /sbin/reboot (BusyBox).

## Codex answer
1. **Missing trackpad firmware on the NVMe root — very high confidence; sufficient to explain the failure.**

   - [C1 console](/Users/damsleth/Code/linux-build-out/nvmeroot-20261025/runs/C1/dcuart-console.log:488): root handoff at **1.813 s**; lines **522–534** then repeatedly report `apple/tpmtfw-j614s.bin` missing (`-ENOENT`) starting at **2.494 s**. The same failure appears in C3–C8.
   - The NVMe initramfs **contains** `./lib/firmware/apple/tpmtfw-j614s.bin`, but the [new root manifest](/Users/damsleth/Code/linux-build-out/nvmeroot-image-20261025/tree.txt:475) contains only Broadcom firmware—no Apple directory/blob.
   - Firmware loads **on device open**, not initial registration: [dockchannel-hid.c](/Users/damsleth/Code/linux/drivers/hid/dockchannel-hid/dockchannel-hid.c:554). Thus the earlier `input: Apple DockChannel Multi-touch` and `magicmouse` registration do **not** prove a usable trackpad. Keyboard operation is consistent: only multi-touch needs this firmware.
   - Working ticket 230 captured **37,950 events**: [console](/Users/damsleth/Code/linux-build-out/230-finger-test-opus-20260819.console.log:118).

   **Minimal fix:** change [scripts/t6040-nvmeroot-init](/Users/damsleth/Code/wallace/scripts/t6040-nvmeroot-init:266) to copy the approved blob from `/lib/firmware/apple/tpmtfw-j614s.bin` into `/newroot/lib/firmware/apple/` before `switch_root`, failing if unavailable. Alternatively, include it when building the persistent root in [t6040-build-nvmeroot-image.sh](/Users/damsleth/Code/wallace/scripts/t6040-build-nvmeroot-image.sh:36).

2. **udev startup guard — possible secondary weakness, little evidence it causes this incident.**

   [t6040-sdroot-startx:33](/Users/damsleth/Code/wallace/scripts/t6040-sdroot-startx:33) starts and triggers udev only if `/run/udev` is absent. An existing directory does not guarantee a running daemon or populated input database.

   **Minimal fix if still needed after firmware repair:** change that script to check daemon readiness and ensure input enumeration before launching X. A working keyboard **inside i3** makes this substantially less likely.

**Other suspected causes are unsupported:** the config diff removes KVM and related settings; HID settings are unchanged, with `HID_MAGICMOUSE`, `HID_MULTITOUCH` and DockChannel HID enabled. The new root includes `libinput_drv.so`, `40-libinput.conf`, input identification and libinput udev rules ([manifest](/Users/damsleth/Code/linux-build-out/nvmeroot-image-20261025/tree.txt:1207)). X launches directly as root, so the empty `input` group in the base archive is not a blocker.

No files changed; no hardware accessed.
1. **Missing trackpad firmware on the NVMe root — very high confidence; sufficient to explain the failure.**

   - [C1 console](/Users/damsleth/Code/linux-build-out/nvmeroot-20261025/runs/C1/dcuart-console.log:488): root handoff at **1.813 s**; lines **522–534** then repeatedly report `apple/tpmtfw-j614s.bin` missing (`-ENOENT`) starting at **2.494 s**. The same failure appears in C3–C8.
   - The NVMe initramfs **contains** `./lib/firmware/apple/tpmtfw-j614s.bin`, but the [new root manifest](/Users/damsleth/Code/linux-build-out/nvmeroot-image-20261025/tree.txt:475) contains only Broadcom firmware—no Apple directory/blob.
   - Firmware loads **on device open**, not initial registration: [dockchannel-hid.c](/Users/damsleth/Code/linux/drivers/hid/dockchannel-hid/dockchannel-hid.c:554). Thus the earlier `input: Apple DockChannel Multi-touch` and `magicmouse` registration do **not** prove a usable trackpad. Keyboard operation is consistent: only multi-touch needs this firmware.
   - Working ticket 230 captured **37,950 events**: [console](/Users/damsleth/Code/linux-build-out/230-finger-test-opus-20260819.console.log:118).

   **Minimal fix:** change [scripts/t6040-nvmeroot-init](/Users/damsleth/Code/wallace/scripts/t6040-nvmeroot-init:266) to copy the approved blob from `/lib/firmware/apple/tpmtfw-j614s.bin` into `/newroot/lib/firmware/apple/` before `switch_root`, failing if unavailable. Alternatively, include it when building the persistent root in [t6040-build-nvmeroot-image.sh](/Users/damsleth/Code/wallace/scripts/t6040-build-nvmeroot-image.sh:36).

2. **udev startup guard — possible secondary weakness, little evidence it causes this incident.**

   [t6040-sdroot-startx:33](/Users/damsleth/Code/wallace/scripts/t6040-sdroot-startx:33) starts and triggers udev only if `/run/udev` is absent. An existing directory does not guarantee a running daemon or populated input database.

   **Minimal fix if still needed after firmware repair:** change that script to check daemon readiness and ensure input enumeration before launching X. A working keyboard **inside i3** makes this substantially less likely.

**Other suspected causes are unsupported:** the config diff removes KVM and related settings; HID settings are unchanged, with `HID_MAGICMOUSE`, `HID_MULTITOUCH` and DockChannel HID enabled. The new root includes `libinput_drv.so`, `40-libinput.conf`, input identification and libinput udev rules ([manifest](/Users/damsleth/Code/linux-build-out/nvmeroot-image-20261025/tree.txt:1207)). X launches directly as root, so the empty `input` group in the base archive is not a blocker.

No files changed; no hardware accessed.
