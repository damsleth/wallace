# Asahi M4 feature-support page: T604x status (read 2026-10-24)

Claude, 2026-10-24. Offline documentation read; no rig, build or external post.

Source: <https://asahilinux.org/docs/platform/feature-support/m4/#m4-promax-devices>,
rendered from `docs/platform/feature-support/m4.md` in AsahiLinux/docs at
`c15c493788bfc8bb08fce9c2f01998b13ec5e339` (2026-10-03, "platform: M4: Update
support"; the last change to the file). Markdown at that commit:
SHA-256 `ff7f143302190c467a6bbc82295e95793d94621b2ecc6851e9acde51ab5dbf45`,
131 lines. The rendered page read on 2026-10-24 matched it.

## What the page says

Legend: `linux-asahi (7.4)` = stable in linux-asahi, expected upstream by 7.4;
WIP = active, not ready for testing; TBA = no active work.

| SoC block | M4 (T8132) | M4 Pro/Max (T604x) |
|---|---|---|
| AICv3 | linux-asahi (7.4) | **WIP** |
| Watchdog, I2C, GPIO | linux-asahi (7.4) | TBA |
| NVMe | WIP | **WIP** |
| Video decoder | WIP | WIP |
| DCP, USB2/USB3/TB/DP-alt, GPU, PCIe, cpufreq, cpuidle, suspend, DART, PMU, UART, USB-PD, MCA, SPI, SMC, SPMI, RTC, SEP, ANE | TBA | TBA |

MacBook Pro 14"/16" M4 Pro/Max (2024): installer **no**, devicetree **WIP**,
and every listed peripheral is **TBA**: main display, keyboard, KB backlight,
touchpad, brightness, battery, WiFi, Bluetooth, HDMI, audio, webcam, SD slot
and TouchID. The base-M4 MacBook Pro row does list a boot framebuffer in
linux-asahi plus KB backlight (7.4); the T604x row lists neither.

## Reading for Wallace

- **No upstream or linux-asahi T604x support to adopt yet.** The official
  T604x columns contain no `linux-asahi` entry at all. The DT, AICv3 and NVMe
  WIP entries agree with the submitted-but-unmerged M4 Pro/Max DTs and Yuka's
  branches mapped in the [6002 audit](2026-10-24-upstream-convergence-audit.md).
  They do not supersede Wallace's captured J614s DT, split NVMe mapping or v2
  input, which 6004 keeps.
- **The capability table's local results are ahead of the published status,
  not contradicted by it.** Wallace's SD, WiFi, BT, trackpad, PCIe, cpufreq and
  USB2-data results (NEXT_STEPS §0) are local, unmerged, single-CPU results.
  "TBA" means no upstream work, not that those results are invalid. Use
  Wallace evidence, not this page, for the daily-driver state.
- **The 7.4 target applies to base M4, not T604x.** The T8132 7.4 entries
  (AICv3, watchdog, I2C, GPIO, DT) are the nearest shared-IP reference for
  the AICv3, watchdog and GPIO bindings that a T6040 rebase will inherit. They
  are not evidence that T6040 lands in 7.4. This matches the October review's
  warning that base-M4 USB (`t8122,atcphy`) does not cover the M4 Pro TB5 PHY;
  the page lists USB3/TB as TBA for both.
- **NVMe stays an open local track.** T604x NVMe is WIP upstream as well. That
  is consistent with 6001 remaining the next hardware experiment and gives no
  reason to revive any refuted CQ-wrap hypothesis.
- **No safety envelope changes.** Nothing here affects SMC/SPMI permissions,
  the enrolled rollback, `maxcpus=1`, or the NVMe write restriction.

Re-check this page at the next upstream refresh. Treat a T604x column moving
from TBA/WIP to `linux-asahi` as the trigger to compare that component against
the 6002/6004 map.
