# SD-root daily v4: trackpad integrated into the daily image (ticket 301)

Claude, 2026-10-24. Offline build only. No rig, card, enrollment or boot.

## Outcome

`m1n1-alpine-sdroot-daily-v4.bin` is the first daily object that carries the
proven trackpad stack (230: touch and haptics) together with the daily
SD-root, WiFi, BT, cpufreq and PPP fallback, plus the 3006-fixed shutdown.
Two fresh-tree kernel builds and two object compositions are byte-identical,
and both objects pass the strict raw-object verifier and
`t6040-image-preflight.sh` with no failure or warning.

```text
a9a2096ff47cc8538090ad28cd0bc41b75b09354e90abff8135b3d242d987bc8  Image-…-trackpad-nbcon-ppp-cpufreq-daily301.build{1,2}
93cfaa38bc4b3906485b66d0f081a30d8963c46fd9d7d75a2c100a3a39fbc253  System.map (both)
96e83d858ddbbcf19027d3ea56411158f75ae75fe4c42c0b03dbdd28b6da3eee  config (both)
69ae3ba76b27afaa47be639f9378ffeeb8e4e2f6f91e379253bb8dd317457366  compressed kernel member (both)
32eac091b1f71c0fc35d0af76d0ff8acf2773098bb8e093fd1ddd6da2c4b8408  m1n1-alpine-sdroot-daily-v4.build{1,2}.bin
```

Object: 25,886,720 bytes (1,580 × 16 KiB), entry `0x800`.

## Composition

- Kernel: Linux `wallace/t6040-bringup` at `4f2429104009`, the tree of the 230
  finger-test PASS kernel (`80c15f58…`) and of the 2026-08-19 SD-root boot.
  Flags: `DOCKCHANNEL DOCKCHANNEL_NBCON MACSMC HID_TYPE_FIX T6040_PPP WIFI PCIE
  CPUFREQ TRACKPAD_FW TRACKPAD_RESET_CONTRACT`. kbuild script `de179323…`,
  `t6040-dockchannel-trackpad-fw.patch` `f7a3eb88…`,
  `t6040-dockchannel-hid-reset-contract.patch` `6eba591f…`. All 16 patches
  applied cleanly, and every config assertion passed, including the
  integrated trackpad firmware path.
- Config is exactly the intended union. Against the 230 kernel it only adds
  the PPP fallback; against daily-v2 it only adds `HID_MAGICMOUSE=y` and
  `HID_MULTITOUCH=y`.
- DTB: daily `t6040-j614s-dcuart-wifi-cpufreq-sdroot` `c5c3b4c3…`, unchanged.
  Its `hid@514600000` node matches the 230 DTB's node apart from phandle
  numbers: the same mailboxes `514608000`/`514b14000`, DART `514800000` and
  `multi-touch { firmware-name = "apple/tpmtfw-j614s.bin"; }`. ANS/NVMe, PMU
  SPMI, `smc_rtc` and `smc_reboot` stay disabled.
- Initramfs: daily v3 `f089ffa7…` (ticket 5000). It ships the approved
  volatile HIDF blob at `lib/firmware/apple/tpmtfw-j614s.bin`, `a1f4131d…`,
  and the 3006-fixed init/shutdown.
- Bootargs: as daily v3, `console=tty0` last.

## Not yet shown

- This combination has not booted. The trackpad-plus-PPP config and the
  SD-root mount/shutdown path with this kernel are covered only by component
  evidence: 230 (trackpad), the 2026-08-19 boot of the same tree as an SD
  root, and the 3006 harness.
- The final hardware poweroff/reboot may still no-op, as for all daily
  objects with `smc_reboot` disabled.

## Gates

Independent exact review (ticket 4003, non-claude), ticket 215 repair (v4
`6ae7244e…` awaiting review and CJ's ack), then an attended SD-root boot that
checks touch, haptic click, WiFi DHCP, BT and a clean-shutdown postcheck.
