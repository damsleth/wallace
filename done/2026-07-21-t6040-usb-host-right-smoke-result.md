# T6040 right-port USB2-host smoke — result (2026-07-21)

Rig ticket 063 ran once with CJ approval and the independently reviewed
right-side/`usb-drd2` artifact set. No `root=` was passed and no block device
was mounted or written.

## Exact booted set

| Input | SHA-256 |
|---|---|
| `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` |
| `Image-usb-host` | `6f0daf57baf942d6e1f43d8efa2ebd4160e976c02ccfaad232dd42e918eb7482` |
| `t6040-j614s-dcuart-usb-host-right.dtb` | `9bee944b8bb0d6d7ab541962ea2edc9a57c4069fedcd6c32db21e3b824a43759` |
| `initramfs-usb-root.cpio.gz` | `8b9b80c4eaad07aa0efa578a827f9d0766be81e9a4aed2650e748b1fc65993c8` |
| `System.map-usb-host` | `019d7504716788f6bda8b22a6bdbef94b89a940128be4083ae3d2f1d491d9d47` |
| `config-usb-host` | `8e11399b172035f7d88c0915ccfbf1bb277eb16097462336c4158b54d8d6bc80` |

Captured logs outside the repo:

- `linux-build-out/dcuart-boot.log`:
  `8c6ec4216383a4c86c157441df8607d9c8d9fcd094811df5fef5a8a7674c708a`
- `linux-build-out/dcuart-console.log`:
  `9a279984b27576d104b772d8d9d15e7ed480160ab26386035867361e3294e14e`
- recovery `/tmp/m1n1-console.log`:
  `b62c52d7d7852c0c637228d4914f979fddd6fc7a348150c799d477115f2c5465`

## Result

**Clean controller bring-up; USB device enumeration failed.**

- The selected DARTs initialized at `0x392f00000` and `0x392f80000`.
- The right-side xHCI controller registered at `0x392280000`, IRQ 42, and
  created USB buses 1 and 2. UAS and usb-storage registered.
- Both the initial report and the repeated report after ten seconds contained
  only the two xHCI root hubs. No child USB device appeared.
- `/proc/partitions` remained empty; no `sd*` device existed.
- The DockChannel shell answered `USB_SMOKE_CONSOLE_OK` and a read-only sysfs
  listing confirmed only `usb1`, `usb2`, and their root-hub interfaces.
- No async SError, DART fault, watchdog/reset loop, panic, internal ANS/NVMe
  probe, or console loss occurred.
- Recovery returned the rig to a quiescent `Running proxy`.

The registered host controller and DART path are therefore proven far enough
to reach Linux root hubs. This run does **not** prove the physical Type-C data
path: it cannot distinguish absent VBUS, missing ATC/ACE role/PHY setup, or a
cable/enclosure-specific failure. The DT deliberately enabled no ATC PHY and
performed no VBUS/PMU/SPMI writes.

## Consequence

Do not populate an external rootfs yet and do not repeat this image unchanged
with the same unpowered topology. First do an offline ADT/driver audit of the
right-port Type-C/ATC/VBUS dependencies. The lowest-risk discriminator is a
newly approved run of the same image with a powered hub or self-powered,
known-good USB2 device on the right port. If that still produces root hubs
only, the next work is the T6040 ATC/ACE role/PHY path—not DWC3/xHCI or storage
drivers. No raw MMIO or PMU/SPMI write is authorized by this result.

The attached device was later confirmed to be a simple bus-powered USB-C
memory stick, not a powered hub or self-powered enclosure. Ticket 065 therefore
proposes one topology-only powered retry; preflight:
`done/2026-07-21-t6040-usb-right-powered-smoke-preflight.md`.
