# Device map, Wallace side: panel, keyboard backlight, USB-C, HDMI, fingerprint, ANE, GPU (2026-10-30)

These are read-only reads on the running 5019 kernel (`/proc/device-tree`, `/proc/config.gz`,
`/sys/class`, dmesg) plus the repo. They're for CJ's new scope (wallace-rex maps the macOS side in
its `findings/2026-10-30-device-map.md`). Nothing was written to hardware.

## Overall

- **Display is the m1n1 framebuffer only:** `/chosen/framebuffer@105d306a880`
  (`apple,simple-framebuffer`), simpledrm as DRM `card0`, connector `Unknown-1` connected at
  3024x1890. `CONFIG_DRM_APPLE` is not set.
- The daily DT has **no** `dcp`, `dcpext`, `disp*`, `dptx`, `lpdptx`, `ane`, `agx`/`gfx`/`sgx`,
  `sep`, `sio`, `atcphy` or `acio` nodes. They are absent, not disabled.
- `soc` has 42 children: 31 okay or implicit-okay, 11 disabled. The IOMMUs present are the USB
  DARTs (`382f00000`, `382f80000`, `38af00000`, `38af80000`, `392f00000`, `392f80000`) plus
  `40dc50000`, `410000000`, `411000000` and `514800000`. None are display DARTs.
- There are no kernel modules on the root (`/lib/modules` is absent), so any `=m` option below is
  unusable.

## Per device

| device | live state | config | Wallace tickets / evidence |
|---|---|---|---|
| Panel brightness | no `/sys/class/backlight`; brightness stays where iBoot left it | `APPLE_DWI_BL` absent, `BACKLIGHT_CLASS_DEVICE=m` | 164 (state "KBD-BACKLIGHT-WORKS-panel-still-dcp-blocked"), 5018 (Gravity T6041 display dtsi diff, open) |
| Keyboard backlight | **works**: `pwm@429040000` (`apple,t6040-fpwm`, okay) drives `/led-controller` (pwm-leds) → `/sys/class/leds/kbd_backlight`, max 255 | `PWM_APPLE=y`, `LEDS_PWM=y` | 164, 213. Boot warning "always-on domain pms_fpwm0 is not on at boot … Failed to reach power state 0xf (now: 0xf)", harmless so far |
| USB-C | the three `dwc3` nodes (`382280000`, `38a280000`, `392280000`) are **disabled** in the daily DT; `spmi@509014000` is disabled ("PMU SPMI disabled" in the model string) | `USB_DWC3=y`, `TYPEC_TPS6598X=m`, `PHY_APPLE_ATC` not set | USB2 host path proven (108/303); VBUS 305 (run 8 `pddiag` pending CJ); hpm2 090, 092-096, 097 (archived); ATC/TB5 023 (open), 6003; `docs/SPMI_SAFETY.md`; `2026-07-27-t6040-typec-adt-map.txt` |
| HDMI / external display | nothing bound | `DRM_APPLE` not set | 022 dcp-track-upstream (open): blocked on the 26.x ABI, a fifth display MMIO window, the ASC IRQ delta, DCP SID/register banks and PMGR ownership; `2026-07-23-t6040-dcp-upstream-dt-prep.md` |
| Fingerprint (SEP) | no node | — | none (SPTM context only: 038, 055) |
| ANE | no node | — | none |
| GPU | no node | — | 4004 (open, upstream tracking only), 039 (done); `2026-07-24-t6040-gpu-upstream-test-prep.md`; ROADMAP §F |

Also found: **`smc/rtc` is `disabled` in the DTB** although `RTC_DRV_MACSMC=y`, which is why
there is no `/dev/rtc`. `smc/reboot` is disabled too. The 5022 notes are corrected.

## ADT sources

The live ADT is not readable from Linux on this boot. A phram reserved node `adt` sits at
`0x100040f0000 +0x94000`, but there is no MTD device, and `/dev/mem` needs a ticket. The full dump is
on the Mac (`~/code/linux-build-out/j614s-full-20260728.adt`, sha256 `2fe477c6…`). The repo has a
display-only subset in `2026-10-24-upstream-convergence/sources/adt-summary.json`: `disp0`,
`dispext0/1` (`*,t604x`), `dcpext0/1` (`iop,ascwrap-v6`), `dcpext*-expert` (`dcp-expert-v1`), the
`dart,t8110` display DARTs, and PMGR `DISPEXT0..3` domains. Ticket 220 (approved, attended) is a live
ADT/ioreg capture from macOS.
