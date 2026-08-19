# Ticket 108 re-run: v2 fix verified live — eUSB2 host sequence completes, xHCI root hubs restored

Date: 2026-08-19. Agent: fable. Lease: acquired and released **healthy**;
one chainload, warm reboot back to a quiescent `Running proxy`. CJ approved
the re-run this session after the buildB binary review PASS.

## Outcome in one line

**The dwc3 `-EINVAL` fix works on hardware.** The v2 PHY slice's eUSB2 host
sequence executed for the first time ever and completed
(`phy-apple-t6040-usb2 392a90000.phy: USB2 host sequence complete`), dwc3
probed cleanly, and both xHCI root hubs came up and stayed healthy — the
Aug-4 regression is closed. **No child device appeared**: VBUS is still not
being sourced (or the S128 stick is no longer in the port — see below), so
the enumeration goal now rests entirely on the PD/VBUS lane (231).

## Fixture (exactly the Aug-4 run with the kernel swapped)

| Artifact | SHA-256 |
|---|---|
| `Image-usb2-native-right-v2phy.buildB` | `802483060f217250aa764d6cd97c627aec3ecf935dd12e4161e49ec3f709a5be` |
| `t6040-j614s-dcuart-wifi-usb2-native-right.dtb` | `6df8af393c43c4a5…` (pinned in 108/303) |
| `initramfs-sdroot-hardened.cpio.gz` | (standard daily initramfs) |
| bootargs | `maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 fbcon=font:TER16x32 ignore_loglevel rdinit=/init` |

Binary review: `evidence/2026-08-19-t6040-usb2-v2phy-buildB-binary-review.md`
(PASS; non-builder). Rig: rollback proxy → chainload via
`IMAGE=… t6040-boot-dcuart.sh`, first try.

## Observations (dmesg via the ttydc0 shell; kernel timestamps)

```text
[    0.065437] platform 392280000.usb: Adding to iommu group 1
[    1.365331] phy-apple-t6040-usb2 392a90000.phy: USB2 event status 0x0
[    1.377278] phy-apple-t6040-usb2 392a90000.phy: USB2 host sequence complete
[    1.379275] xhci-hcd xhci-hcd.0.auto: xHCI Host Controller
[    1.379716] xhci-hcd xhci-hcd.0.auto: new USB bus registered, assigned bus number 1
[    1.380601] xhci-hcd xhci-hcd.0.auto: irq 69, io mem 0x392280000
[    1.383630] xhci-hcd xhci-hcd.0.auto: new USB bus registered, assigned bus number 2
[    1.384079] xhci-hcd xhci-hcd.0.auto: Host supports USB 3.1 Enhanced SuperSpeed
```

- **Zero** `-EINVAL` / `failed to initialize core` /
  `Failed forced host-mode init` lines — the Aug-4 failure signature is gone.
- `/sys/bus/usb/devices/` = `1-0:1.0 2-0:1.0 usb1 usb2` — both root hubs,
  re-sampled unchanged at uptime 107 s (persistence bar was 10 s).
- **Zero DART fault/error lines.** Console responsive throughout.
- SD healthy in the same boot (`mmcblk0` present) — machine baseline normal.
- **NVMe driver never entered the kernel**, as the review predicted: the
  only "nvme" dmesg lines are three pmgr `sync_state() pending due to
  44dcc0000.nvme` holds (the DT node exists, no driver ever bound) and the
  macsmc-rtc deferring on the SPMI nvmem cell — which also demonstrates the
  SPMI inertness live: the deferred probe waits forever on the `=m` SPMI
  controller that can never load. No SPMI transaction was issued.

## Pass/fail against the staged conditions

| Condition | Result |
|---|---|
| dwc3 probes without `-EINVAL` (primary) | **PASS** |
| eUSB2 host sequence executes (first live exercise of the 188-reviewed MMIO) | **PASS** — `event status 0x0`, `host sequence complete` |
| right xHCI root hubs up, healthy ≥10 s | **PASS** (verified at 107 s) |
| DART healthy, console responsive, no unexpected reset | **PASS** |
| no internal NVMe activity | **PASS** (structurally impossible; verified) |
| S128 child enumerates (bonus — requires VBUS already live) | **NOT MET** — no child |

The no-child result is ambiguous between "no VBUS" (expected: macOS-warm
VBUS did not survive two weeks / a reboot chain, and this image has no PD
driver) and "stick removed since 2026-08-04". CJ can settle it by checking
the right port; the engineering conclusion is the same either way: **the
data path is done, VBUS is the sole remaining gap**, exactly the split the
dwc3 evidence predicted ("that restores the USB2 data path…; this driver is
the VBUS/CC path. Both are needed").

## Next

1. The VBUS lane is fully staged: SPMI PD driver (77fd00b) + exact-source
   review (e0b49f1, envelope table for CJ) + draft hpm2-only connector DT
   (e272cba). CJ's sign-off and an attended run are the remaining gates.
2. Optional cheap disambiguation for the stick question during CJ's next
   attended session: with the stick confirmed seated, an R0 connector-state
   read (229) tells us role/VBUS state without any write.

## Transcripts

```text
8f4984a7f85f7a155a331faed0fb8c8887d84b00fb734d5ece47b1079d2eadbd  3455 bytes
  linux-build-out/transcripts/t6040-console-20260819-fable-ticket108-v2phy-rerun.log
1f47c1f430e19fcb582f…
  linux-build-out/transcripts/t6040-boot-20260819-fable-ticket108-v2phy.log
```

(ttydc0 carries no printk on this fixture; the kernel-side evidence lives in
the marker-delimited dmesg extraction blocks inside the console transcript.)
