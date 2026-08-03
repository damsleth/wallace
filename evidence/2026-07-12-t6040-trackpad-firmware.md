# T6040 J614s trackpad firmware path (2026-07-12)

## Result

The lack of trackpad events is not caused by the absent haptic click. Haptics
are a separate MTP actuator interface. The multi-touch interface itself cannot
start until Linux uploads the board-paired BCM5976 firmware.

The current upstream-oriented Apple DockChannel HID series intentionally
supports the internal keyboard without external firmware. Compared with the
older Asahi driver, it omitted multi-touch firmware loading and GPIO proxying.
That made `dchid_start_interface()` send two resets without first initializing
the AFE; J614s firmware rejected both with `0xe00002c2`. The driver ignored the
errors, timed out, and left `iface->starting` set, so every later open returned
`-EINPROGRESS`.

## Implemented

`patches/t6040-dockchannel-trackpad-fw.patch` restores the safe prerequisite:

- read `firmware-name` from the per-interface child node;
- load and bounds-check the `HIDF` wrapper emitted by `asahi-fwextract`;
- patch the runtime MTP interface number in a private payload copy;
- upload it through the transport's existing coherent DMA/IOMMU mapping;
- issue the two interface resets only after upload succeeds; and
- clear `starting` after command errors, start timeouts, and ready events.

The J614s board DT requests `apple/tpmtfw-j614s.bin` (Linux commit
`6399cdc1bb94`). `scripts/t6040-make-initramfs.sh` accepts
`TRACKPAD_FIRMWARE=/path/to/tpmtfw-j614s.bin` and installs it at the matching
`/lib/firmware/apple/` path after validating the HIDF magic, version, header,
payload bounds, and interface offset.

Current upstream `asahi-installer` commit `c53d66dc7193` does not require a
board mapping for this file. Its
[`MultitouchFWCollection`](https://github.com/AsahiLinux/asahi-installer/blob/c53d66dc71937efa2530d4323c81addaebb5a09b/asahi_firmware/multitouch.py)
scans every `j*` directory in the collected FUD firmware and derives the
`tpmtfw-<machine>.bin` name directly. The remaining provisioning prerequisite
is therefore access to this target's Asahi ESP: either the already-extracted
`vendorfw/apple/tpmtfw-j614s.bin` or `asahi/all_firmware.tar.gz`. A local search
found neither file, no IPSW cache, and no installed extractor on the host.

## Live negative-path proof

Kernel build #12 compiled and booted to BusyBox:

- `Image`: `93c33ea10dddcc69b50c39a7c0b64a7a8d9c5485bfcc94119839ed4501fdadfb`
- `t6040-j614s-dcuart.dtb`:
  `485b7efb895888ea26bd1e575ddaff689327840eb5c5aea404031920d7122b75`

Two consecutive opens of event0 each logged a fresh direct-firmware request
and returned `-ENOENT` for `apple/tpmtfw-j614s.bin`. There were no command-0x40
messages, two-second waits, or stale `-EINPROGRESS` result. This proves both the
DT association and retry cleanup before using a proprietary blob.

## Remaining

1. Retrieve this machine's paired `tpmtfw-j614s.bin` from its Asahi ESP, or run
   the ESP's `asahi/all_firmware.tar.gz` through the Asahi vendor-firmware
   extraction flow. Do not substitute a blob from another board.
2. Rebuild the initramfs with `TRACKPAD_FIRMWARE=...`, boot, and open event0.
3. If firmware upload exposes an MTP GPIO request, capture its interface, ID,
   name, and command, but do not acknowledge it with a pulse. Read-only ADT
   inspection has now resolved `function-afe-reset` to phandle 294,
   `/arm-io/smc/iop-smc-nub/smc-pmu`, `pKW4('gp1c', 0x10000)`. The older proxy
   would write SMC key `gp1c` as `0x10001` then `0x10000`. That is a PMU path,
   and this project's non-negotiable rules prohibit the writes.
4. Once motion reports flow, add the MTP IDs/report format to `hid-magicmouse`
   as needed and test haptics separately through the actuator interface.
