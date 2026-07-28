# Feature kernel built: macsmc (battery/thermals) + usbnet + USB-tether ECM (165/167/173)

## The object

`m1n1-b0-macsmc-dualmode.bin`
`3cfdaf247827ca765026ab2a8419e43d43af19c1f22f34b1b2eeb30e6e07ef62`
**28,590,080 B = 1745 × 16 KiB**, strict verify PASS, kernel `pages=4K`.

| Member | Hash | Note |
|---|---|---|
| m1n1 window10 v6 (dual-mode) | `c10a502f` | 10 s debug window, else boots dwm |
| kernel `Image-macsmc.xz` | `e9bd3f8d` | full kernel + macsmc/usbnet/gadget builtin (raw 53.6 MiB) |
| DTB `t6040-j614s-dcuart-macsmc.dtb` | `a122129b` | **carries `smc@50c600000`, status okay** |
| initramfs `initramfs-alpine-dwm-ecm.cpio.xz` | `aec1e688` | dwm + udev + HiDPI + the ECM service (62 MiB expanded) |
| bootargs | `3659a0da` | proven B0 set |

Confirmed built into the kernel (System.map): `apple_smc`, `apple_mbox`, `macsmc_power`, `usbnet`,
`cdc_ether`, `ecm_alloc`, `gether_setup`, `dwc3_gadget`. Enrolled-guard-approved (`3cfdaf24`).

## What it adds over the working dwm daily driver

Exactly the feature set, one build:

1. **Battery / charge / temperatures** — macsmc MFD auto-creates `macsmc-power` (power-supply) and
   `macsmc-hwmon`. SMC node from the live ADT (mailbox `0x50c600000`, IRQs 996-999); SRAM
   `0x50e000000` is pattern-inferred, so if it is wrong macsmc simply fails to probe (no battery/
   thermals) with boot unaffected — a safe, one-address failure mode.
2. **USB ethernet dongles** — `usbnet` + CDCETHER/AX/RTL builtin, ready the moment a USB host port
   works (096/170).
3. **USB-tether ethernet** — a CDC-ECM gadget on the device-mode DFU port makes the M4 a NIC to the
   host Mac over the proxy cable. `g_ether` (builtin) auto-binds the UDC; `t6040-usb-ecm-gadget`
   assigns `usb0 = 10.42.0.2/24`.

## How to run it (maintainer)

Enrolled cold boot (daily-driver candidate): `kmutil configure-boot -c <path> --raw --entry-point 2048
--lowest-virtual-address 0 -v /Volumes/m1n1` from 1TR (no sudo). Or catch the 10 s window for a proxy.

Pass criteria, in order of confidence:

- **dwm still comes up with a working keyboard** (regression check — one variable changed vs the proven
  dwm object: the kernel+DTB).
- **Battery/thermals:** on the panel or a tty1 shell, `cat /sys/class/power_supply/*/uevent` and
  `cat /sys/class/hwmon/*/temp*_input`. If empty, macsmc did not probe — read the boot log / check the
  SMC sram address (the one flagged inference).
- **Tether ethernet:** on this Mac a new CDC/RNDIS interface appears; set it to `10.42.0.1/24` and
  `ping 10.42.0.2`. On the M4, `/var/log/ecm-gadget.log` shows the UDC bind and `usb0` state.

## Honest unknowns (all safe-failure, none block boot)

- SMC SRAM address is pattern-inferred → macsmc may not probe.
- Linux dwc3 gadget mode on M4 is untested (the proxy gadget is m1n1's own stack) → ECM may not
  enumerate.
- macOS CDC-ECM/NCM host support is partial → the Mac may not auto-configure the interface (the
  service enables both ECM and NCM to improve odds).

Each is a "find out at smoke"; the worst case is a feature not appearing, never a boot failure.
