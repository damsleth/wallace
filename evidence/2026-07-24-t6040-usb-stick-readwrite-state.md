# T6040 USB-stick read/write state — landed (2026-07-24)

Answering CJ's question: how to get the USB stick read/writable on the M4, and
whether "write the distro on the M1, read/boot it on the M4" sidesteps the block.

## The read/write framing is not the bottleneck — enumeration is

On the M4, **read and write are equally blocked, for the same reason**: the stick
never enumerates. Linux sees only the xHCI **root hubs**; no USB *device* appears
on the bus at all (ticket 063/064). It is not that write is harder than read —
once a device enumerates, `usb-storage`/`uas` handle read and write symmetrically
at the SCSI/block layer. The wall is one layer below the filesystem: the
Type-C/ATC physical link.

Why (064, grounded in the live ADT): the port has the full hardware —
`usb-drd2`(right) → `atc-phy2` (`atc-phy,t6040`, with `tunable_USB2PHY_HOST`
records) → `acio2` fabric → `hpm2` Type-C PD manager (`usbc,sn201202x,spmi`, on
SPMI). But Linux has **no** `atc-phy,t6040` driver and no HPM/Type-C path, so
DWC3 brings up xHCI with **no PHY provider**, and nothing establishes cable
orientation, VBUS, the eUSB2-repeater reset, or USB2 host-PHY state. m1n1's
inherited `usb_phy_bringup()` is a fixed legacy device-mode sequence that does
**not** apply the ADT's `tunable_USB2PHY_HOST` records or deliver HPM orientation.

## "Write on the M1, boot/read on the M4" — yes; the image is ready, the stick is not flashed

This IS the right architecture and its image-construction half is done:

- The selected GPT/ext4 artifact is
  `linux-build-out/t6040-alpine-openrc-usb-root.build4.img`, SHA-256
  `1c493fad1d1b44520d9265c5946c8ac00b867b3d47fac93f88d1f55cde25060e`,
  PARTUUID `e4731abe-3566-4c3a-8019-c8828ca27a5a`. Ticket 098 completed its
  GPT/ext4/OpenRC/content checks and independent review. It is ready for a
  separately confirmed destructive flash after M4 enumeration/read-only block
  identity succeeds.
- The older ticket-086 image `32a897cb...` is structurally valid but lacks
  OpenRC and must not be flashed.
- A secondary 512 MiB filesystem-only artifact was also built at
  `linux-build-out/t6040-usbroot-alpine.img` (`ccc18ab...`), but it is not the
  selected release artifact, has the same missing-OpenRC defect, and should
  not be flashed.
- On the M1, macOS can write the selected raw image without mounting ext4.
  The exact external removable whole disk must first be resolved and reviewed;
  the destructive command remains intentionally outside the builder and is
  not authorized while the stick is attached to the M4.
  The M4 then only ever **reads** this stick (kernel/DTB/initramfs come from the
  enrolled m1n1 object; boot with `root=LABEL=t6040root rootfstype=ext4`), so the
  M4 never needs USB *write* — CJ's exact intent.

**But this does NOT unblock the M4 read.** The M4 still has to *enumerate + read*
the stick, which is the same physical-link gate above. Populating on the M1 only
removes the M4-write requirement; it does not remove the M4-enumerate requirement.

## The actual unblock: M4 USB enumeration (the hard gate)

Establishing the Type-C link needs the **HPM (`sn201202x` PD controller) driven
over SPMI** for cable detect/orientation/VBUS + the eUSB2-repeater reset, plus
the **ATC host PHY** brought up with the ADT `tunable_USB2PHY_HOST`. Two paths:

1. **m1n1 brings the storage port up in host mode (with HPM orientation) and
   hands Linux a live link.** Yuka's new `tps6598x-spmi` branch
   (`dcc5f1bc...`) is the first public code matching our exact Gen3
   SPMI/SN201202x nodes. It is not sanctioned for Wallace merely because the
   writes happen in m1n1. The endpoint-scoped policy permits only the separate
   direct-HPM2 policy; this branch performs
   WAKEUP/SHUTDOWN, register-select, possible `SSPS`, and IRQ writes across
   additional HPMs and has unresolved safety/correctness issues. Audit:
   `evidence/2026-07-24-t6040-yuka-hpm-spmi-branch-audit.md`.
2. **Upstream `atc-phy,t6040` + tipd/HPM Linux drivers** — the clean long-term
   path; tracked (ticket 023), not build-here.

Either way, M4 USB-stick boot is gated on the HPM/ATC host-link bring-up. We
cannot force it from the Linux side without a reviewed HPM/ATC sequence.
Tickets 093–095 proved the endpoint through S0; 096 and decomposed tickets
102–113 own rollback, link, enumeration, block access, flash, and root tests.
No new stage is implicitly approved.

## Net "landed state"

- **Write (M1) → boot-read/write (M4)** is the correct plan; the ticket-098
  image is flash-ready, but the stick has not been flashed.
- **M4 read/enumeration is the remaining hard blocker**, gated on reviewed
  m1n1 (or upstream Linux) HPM/ATC host-link support. The exact HPM endpoint
  now reaches S0 (`0x07` → `0x00`); role/VBUS/repeater/ATC and xHCI child
  enumeration remain.
- Therefore the **achievable untethered distro** is the RAM-root path (Alpine
  boots today, keyboard now works); USB-stick persistent root follows the
  decomposed link, read-only block, flash, bounded-write, and cold-boot tests.
