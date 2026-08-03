# T6040 Linux bring-up handoff (2026-07-11)

## Safety and connection

- Target: MacBook Pro M4 Pro, T6040/J614s (Mac16,8), tethered from an M1 Max.
- Proxy: `/dev/cu.usbmodemJ22GYCN4YG1`; `...YG3` is the secondary m1n1 UART,
  not a working raw-kernel console.
- Read the root `AGENTS.md` and `proxyclient/AGENTS.md` before hardware access.
- Historical note: this session used the former blanket SPMI ban. It was
  superseded on 2026-07-24 by `docs/SPMI_SAFETY.md`; PMU/charger/NVRAM/
  firmware and unknown endpoints remain prohibited, and only exact staged
  right-HPM2 transactions are eligible. PMGR/cluster/unknown MMIO writes are gated:
  show exact address and value and wait for maintainer approval. Never blind-probe.
- Do not unplug USB. If proxy wedges, stop and let the maintainer power-cycle.

## Verified boot progress

- Linux 7.2-rc2 reaches framebuffer console and BusyBox PID 1 on T6040.
- Persistent userspace works with `apple_wdt=y`; `/init` pings `/dev/watchdog0`
  every 10 seconds with a 30-second timeout.
- PMGR functional boot succeeds with the local minimal PMGR policy, ANE disabled,
  and `disp_cpu` disabled. Earlier PMGR hangs were localized and fixed sufficiently
  for userspace; do not undo the current policy casually.
- The on-screen console is simpledrm/fbcon. Raw Linux has no useful USB/serial
  console after m1n1 hands off.

## Internal keyboard/trackpad path: verified resources

ADT-derived J614s resources:

- MTP ASC: `0x514600000`; CPU control/status at `+0x44/+0x48`.
- ASC mailbox: `0x514608000`; IRQs 793, 792, 795, 794.
- DART-MTP: `0x514800000`; IRQ 775; SID 0; 16 SIDs; 16 KiB pages.
- DockChannel: IRQ/config/data at `0x514b14000`, `0x514b30000`,
  `0x514b34000`; IRQ 776; FIFO `0x800`.
- Preloaded MTP SRAM: `0x514c00000..0x514cac000`.
- ADT children: `multi-touch`, `keyboard`, `stm`, `actuator`, `tp-accel`.

Linux source uses the local `origin/dockchannel` series imported by
`.plans/t6040-kbuild.sh` when `DOCKCHANNEL=1`:

- `d2acb86f70a252cc458101d855e6e4c950031174`
- `f2b7718fd46c34b8c500ae77bdb7129de3494105`
- `c4a0e3d1b55d2ceca114681c1bae7aeb9caf06ea`
- `356985c33ceb197790012a2362542c2b62baea0a`
- mailbox accessor fix from `ba89d30070d42082a5eca95419e72f1e132b0893`

DT files are in `/Users/damsleth/Code/linux/arch/arm64/boot/dts/apple/`:

- `t6040.dtsi`: disabled MTP mailbox/DART/DockChannel/HID nodes.
- `t6040-j614s-kbd-infra.dts`: infrastructure only, MTP CPU not started.
- `t6040-j614s-kbd.dts`: full MTP HID path.

## Hardware test results (facts)

1. Infrastructure-only boot reached persistent userspace. Built-in DART logged:

   `apple-dart 514800000.iommu: DART [pagesize 4000, 16 streams, bypass support: 1, bypass forced: 1, AS 42 -> 42] initialized`

   Therefore the ADT-derived DART and DockChannel mappings and their normal probe
   writes are hardware-verified.

2. Full clean HID boot reached userspace but no input device appeared. It failed:

   `dockchannel-hid 514600000.hid: error -ETIME: failed to wake coprocessor`

   followed by probe error `-62`. DART attached HID to IOMMU group 0.

3. Read-only proxy baseline after a hardware reset:

   - CPU control `0x514600044 = 0x00000000`
   - CPU status `0x514600048 = 0x0000006a` (STOPPED set, RUNNING clear)
   - A2I control `0x514608110 = 0x00020001` (enabled, empty)
   - I2A control `0x514608114 = 0x00020001` (enabled, empty)
   - DART SID-0 TCR `0x514801000 = 0x00000001`
   - DART error `0x514800100 = 0x00000000`

4. One explicitly approved proxy RUN pulse was performed:

   - write `0x514600044 = 0x10`
   - after 100 ms: control `0x10`, status `0x6c`; both mailboxes still empty
   - write `0x514600044 = 0x0`
   - status remained `0x6c` after 100 ms and several seconds

   STOPPED cleared, but the normal RUNNING bit never set. The SRAM header/vector
   at `0x514c00000` is populated (15 nonzero bytes in the first 256 bytes), so
   firmware is not simply absent. Do not repeat this pulse: clearing RUN does not
   return MTP to STOPPED without a hardware reset.

5. The proxy pulse contaminated the following Linux boot because
   `chainload.py -r` reloads m1n1 but does not hardware-reset MTP. Photo
   `IMG_3765.jpeg` shows `apple_dart_t8110_irq`, Linux disabling IRQ 40, then DART
   initialization, followed later by a halt at `Demotion targets for Node 0: null`.
   The 20-second hardware-watchdog reset restored the pristine `0x6a` baseline.
   Treat that boot as invalid, not as evidence against the diagnostic initramfs.

6. A logging-heavy kernel diagnostic Image is unusable: three attempts exposed
   unrelated layout/timing-sensitive early boot halts (twice at `Demotion targets
   for Node 0: Null`, once during PMGR after `sep@c00`). Do not use
   `Image-keyboard-debug` or enable `DOCKCHANNEL_DEBUG=1` for the next test.

## Current clean artifacts

- `/Users/damsleth/Code/linux-build-out/Image` and `Image-keyboard`:
  SHA-256 `f0c8f35294e4354b12e474a100dc0a880212390eec33653f1164a1e8d240f36a`
- Full HID DTB `t6040-j614s-kbd.dtb`:
  SHA-256 `e24d1302938e366f8612b393012fa7a4b77d59eacceecaa2b48b5534cf1d1e83`
- Userspace-only status initramfs `initramfs-keyboard-status.cpio.gz`:
  SHA-256 `76f5cbf7e91a241fd857c06f6124cfc627b06f3722cb5187b8809cb195ee7c07`
- Known-good watchdog-only Image:
  SHA-256 `9fadaea08be9ae4ae0e8c4ae35aca3ec7bf8116cd6db530e2068648a9c2626b5`

The status initramfs changes only `/init`. After five seconds it uses BusyBox
`devmem` for read-only prints of CPU control/status, both mailbox controls, DART
SID-0 TCR, and DART error. Kernel text remains the clean known-good Image.

## Current in-flight test / immediate next action

At handoff time, a clean retry was just chainloaded from a verified hardware-reset
baseline with:

```sh
bash .plans/t6040-bootcap-fb.sh \
  t6040-j614s-kbd.dtb initramfs-keyboard-status.cpio.gz
```

Its on-screen outcome has not yet been reported. First ask the maintainer for the
last lines/photo.

- If userspace appears, capture the `MTP post-probe MMIO (read-only)` block. This
  directly shows whether Linux left MTP at `0x6c`, whether mailboxes changed, and
  whether SID 0 is really `0x6` during the timeout.
- If it halts and watchdog returns to `Running proxy`, do only the six known
  read-only baseline reads above before another run.
- If DART IRQ 40 is disabled again despite a pristine start, investigate the DART
  interrupt/error path before any more MTP writes.

Do not assume a write barrier or delay will fix wake: the proxy pulse held RUN for
100 ms without mailbox output, though that proxy test had SID-0 TCR `0x1` rather
than Linux's bypass `0x6`. Do not guess ascwrap-v6 offsets. Derive any additional
startup requirement from ADT/known drivers or a hardware trace.

## Working-tree state

Expected local changes/untracked files include:

- modified `.plans/2026-07-11-t6040-keyboard-plan.md`
- modified `.plans/t6040-init-keyboard`
- modified `.plans/t6040-kbuild.sh`
- untracked `.plans/NEXT_STEPS.md`
- untracked `.plans/t6040-dockchannel-debug.patch`

These are bring-up work, not disposable changes. Preserve them.
