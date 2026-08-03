# T6040 Alpine HID regression analysis

Date: 2026-07-23  
Offline ticket: 069  
Result: **RX acknowledge/re-arm race hypothesized and tested; live result shows
it is not the sufficient HID fix**

## Failure boundary

Ticket 067 proved that Alpine itself boots and that the MTP firmware reaches
`Keyboard ready`, but Linux stops before the STM identity exchange:

```text
hid-generic 0019:0000:0000.0001: device has no listeners, quitting
```

There is no `05ac:0359`, `/dev/input`, or input registration. The MTP
DockChannel interrupt count stops at 383, while its IRQ thread and HID workers
are idle. This excludes a userspace keymap problem and a worker blocked on an
MTP command.

## Delta audit

- The failed 7.1.3 kernel and known-good 7.2-rc2 kernel enable the same input,
  evdev, generic HID, Apple HID, and Apple DockChannel HID options.
- The relevant DockChannel HID source carried by the two kernel histories is
  content-identical. There is no missing keyboard-specific fix to backport.
- The failed DT enables the MTP mailbox, DART, DockChannel, HID, keyboard, and
  multi-touch nodes with the expected MTP RX/TX masks.
- The old working path masks its RX child interrupt before the threaded FIFO
  consumer runs. The current mailbox driver W1C-acknowledges RX while leaving
  the local RX source enabled, drains later in an `IRQF_ONESHOT` thread, and
  does not explicitly re-arm after the drain.

The last item is a plausible latent timing race rather than a clean
7.1-to-7.2 source regression: data arriving around the acknowledge/drain
boundary could be folded into the active interrupt and leave FIFO data without
a new edge. Kernel layout or boot timing could expose it even when the
transport source is unchanged. The saved failure was consistent with that
hypothesis, but did not prove it.

## Minimal correction

`patches/t6040-dockchannel-rx-rearm.patch` changes only the IRQ-driven
DockChannel receive path:

1. Mask the local RX source in the hard IRQ before W1C acknowledgement.
2. Drain all available FIFO data in the existing oneshot thread.
3. Clear the consumed flag and re-enable RX.
4. Recheck the FIFO and repeat under the same oneshot invocation if data raced
   with re-arming.

UART remains in its proven `apple,poll-mode`, so this change is exercised only
by the MTP DockChannel. The patch introduces no address, interrupt, power,
SPMI/PMU, storage, or firmware change.

## Built artifact

The isolated build used:

```sh
podman exec -e DOCKCHANNEL=1 -e HID_RX_REARM=1 \
  -e BUILD_DIR=/build/linux-hid-rx-rearm -e NPROC=12 kbuild \
  bash /out/t6040-kbuild.sh image
```

| Artifact | SHA-256 |
|---|---|
| `Image-hid-rx-rearm` | `a6c2f09354bf1d61559b450f9430eb06d42f94d027d539c2deade708d708c4ff` |
| `System.map-hid-rx-rearm` | `f75b79d6baf02e8d2ee30587aceb98835aed88cac457bbbe7139118e74f13038` |
| `config-hid-rx-rearm` | `8e11399b172035f7d88c0915ccfbf1bb277eb16097462336c4158b54d8d6bc80` |
| `t6040-j614s-dcuart-hid-rx-rearm.dtb` | `2782b92237c35c8950212207391c3ae28c44b6b9c635b2e864c5748a77bb3cce` |
| RX re-arm patch | `83d07766678acd271ef3be9b9cbb93e35fb186bfe162b329de634d91fe2f3b01` |
| build harness | `720301c3d2d0a68088231c612419cd1a8f5ffa3f135516ddd61b827ef0d084cd` |

The kernel is `7.1.3-g96ac043df12f-dirty`, 53,303,808 bytes. Its extracted
embedded config matches `config-hid-rx-rearm` byte-for-byte and has the exact
same SHA-256 as ticket 067's failed kernel config. This removes config drift
from the A/B test. The inactive USB force-host source patch is not present in
this storage-disabled build.

## Static verification

- Fresh case-sensitive build: pass.
- `git diff --check`: pass.
- strict kernel `checkpatch.pl`: 0 errors, 0 warnings.
- MTP DT: mailbox IRQ 776, TX mask `0x4`, RX mask `0x8`, MTP mailbox/DART/HID
  enabled.
- UART DT: IRQ 816, TX mask `0x4`, RX mask `0x2`, `apple,poll-mode`.
- All three external USB controllers and six USB DARTs: disabled.
- ANS mailbox, SART, and NVMe: disabled.
- `CONFIG_APPLE_DOCKCHANNEL_TTY=y`; the remote `/dev/ttydc0` failure boundary
  is retained.

## Live validation

Ticket 071 booted this exact image once. Alpine 3.24.0/aarch64 and ttydc0
worked, `/proc/partitions` remained empty, but `/proc/bus/input/devices` was
still empty and `/dev/input` did not exist. Therefore the re-arm change is not
the sufficient HID correction and must remain experimental. Exact result:
`done/2026-07-23-t6040-alpine-hid-rx-rearm-result.md`.

The next experiment must first add observation-only state tracing across the
mailbox IRQ/FIFO and DCHID event/identity boundaries. Do not add another
receive kick without that evidence.
