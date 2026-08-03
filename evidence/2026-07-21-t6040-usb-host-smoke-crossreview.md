# T6040 one-port USB2-host smoke cross-review (2026-07-21)

Reviewer: `usb_smoke_cross_review` (independent agent)

Verdict: **PASS for both port-specific artifact sets, conditional on selecting
and pinning exactly one physical-drive port before CJ approval.**

Re-review after the IRQ-816 correction: **PASS**. Replacing only the DTB's 816
interrupt cell with the old 360 recreates each prior reviewed hash exactly,
proving there is no other binary DT change. Inspection of the pinned Image also
confirmed that `apple,poll-mode` bypasses IRQ acquisition entirely. The stale
`linux-build-out/t6040-j614s-dcuart.dts` staging copy found during review was
refreshed to 816; repo, Linux-tree, and staging sources now agree.

## Verified artifacts

| Physical drive port | DTB | SHA-256 |
|---|---|---|
| left-front | `t6040-j614s-dcuart-usb-host-left-front.dtb` | `6e6f6bfa4eee896211516ac04e242f96fc650410900b8641fc5bcee443a2d430` |
| right | `t6040-j614s-dcuart-usb-host-right.dtb` | `9bee944b8bb0d6d7ab541962ea2edc9a57c4069fedcd6c32db21e3b824a43759` |

Both port-specific six-file manifests pass. The kernel, m1n1, initramfs,
System.map, and config hashes match the preflight. The old generic all-port
manifest and DTB are not eligible for a live boot.

## Decompiled-DTB checks

- Left-front enables only `usb-drd1` at `0x38a280000` and its DARTs at
  `0x38af00000`/`0x38af80000`.
- Right enables only `usb-drd2` at `0x392280000` and its DARTs at
  `0x392f00000`/`0x392f80000`.
- Each DTB contains exactly one enabled host controller and one
  `apple,force-host-mode` property.
- `usb-drd0`/left-back and all unused USB/DART groups remain disabled.
- No ATC PHY is enabled. ANS, SART, and internal NVMe remain disabled.
- The rebuilt DockChannel node uses measured AIC input 816 and retains
  `apple,poll-mode`; the interrupt is therefore corrected but not exercised by
  this smoke test.

The independent ADT parse also confirms
`usb-drd0/1/2 = left-back/left-front/right` and the raw-capture hash
`7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84`.

## Runtime-safety checks and caveats

The initramfs contains no kernel modules; its smoke path mounts only proc,
sysfs, and devtmpfs and does not mount a block device. NVMe is modular and its
module is absent. No PMU/SPMI/charger/NVRAM path is introduced. The selected
USB devices use their existing ADT-derived PMGR power domain, which remains
within the CJ approval gate.

Before approval, replace the preflight's `CHOSEN` placeholder with exactly the
DTB matching the attached drive and use only its matching manifest. Keep the
DebugUSB tether on left-back. Because there is no ATC PHY or explicit VBUS
control, a powered hub or self-powered enclosure is preferred and enumeration
remains experimental.
