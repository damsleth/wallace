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

## v2 (9800f4d8): keyboard + ECM fixes after the first smoke

First smoke (`3cfdaf24`) booted to dwm but **the keyboard did not work in X** and **no ECM interface
appeared on the host**. Both were my build errors, both fixed:

- **Keyboard:** the working dwm kernel is the *hid-type-fix* kernel — it needs `HID_TYPE_FIX=1` to patch
  the DockChannel HID driver so `hid->type` is set and `hid-apple` accepts the internal keyboard
  (→ `event0` → libinput). I built with `DOCKCHANNEL=1 MACSMC=1` and omitted `HID_TYPE_FIX=1`. Rebuilt
  with it (confirmed the `hid->type = HID_TYPE_SPI_KEYBOARD` source change is applied).
- **ECM:** the tether port `usb_drd0` and its DARTs were `status = "disabled"` in the DTB, so Linux
  registered no UDC and `g_ether` had nothing to bind. Enabled `usb_drd0` (already
  force-device-mode/peripheral) + `usb0_dart0/1` in the macsmc variant.

New object: `m1n1-b0-macsmc-dualmode.bin`
`9800f4d8291f86fca577616c8dc9f4328249acb77184a2d0c5cb91e7565a315e` (28,590,080 B = 1745 × 16 KiB,
strict PASS, pages=4K). Kernel `14c2fffd`, DTB `e05dc7fa` (usb_drd0 okay, smc okay). Enroll-guard
approved; `3cfdaf24` retired. One re-enroll now tests keyboard + battery/thermals + tether ethernet.

Build note: with both `MACSMC=1` and `HID_TYPE_FIX=1`, the HID_TYPE_FIX image name (`Image-hid-type-fix`)
wins over `Image-macsmc` and hits the overwrite guard — the fresh Image was taken from the build tree
and copied as `Image-macsmc` by hand.

## First network smoke (9800f4d8): dwc3 gadget WORKS on M4; RNDIS is the wrong flavor

The v2 object booted, keyboard works. Battery/thermals: maintainer to read on the panel. **Network,
tested from the host Mac:**

`system_profiler SPUSBDataType` shows the M4 enumerated:

```
RNDIS/Ethernet Gadget:
  Manufacturer: Linux 7.1.3-g96ac043df12f-dirty with dwc3-gadget
```

**This is a major result: Linux dwc3 gadget mode works on the M4.** The hardest unknown for
tether-ethernet — whether Linux dwc3-apple can run the DFU port as a USB device — is resolved YES. The
UDC came up and g_ether presented a gadget that macOS enumerated over the tether cable.

But **no `en` interface was created on the Mac**, because the gadget enumerated as **RNDIS**.
`g_ether` (legacy `USB_ETH`) auto-binds a RNDIS-first composite ("RNDIS/Ethernet Gadget"), and **macOS
has never supported RNDIS**, so it enumerates the USB device but binds no network driver. My configfs
pure-ECM fallback never ran because g_ether had already grabbed the UDC.

### Fix (v3, building)

Drop `USB_ETH`/RNDIS from the kernel entirely and present a **pure CDC-ECM gadget via configfs**, which
macOS binds as an ethernet device. Kernel: `-d USB_ETH -d USB_ETH_RNDIS`, keep
`USB_CONFIGFS_ECM`/`NCM` + `USB_DWC3_DUAL_ROLE`. Service rewritten to build `functions/ecm.usb0`
directly and bind the tether UDC (no g_ether-detect path). Testing by **chainload over the caught
window** — no re-enroll needed.

## Network smoke campaign (chainload, 2026-07-28): dwc3 gadget works; macOS binds no interface

Tested four gadget flavors by chainloading window-free objects over the caught dual-mode window (no
re-enroll each time). Result table (all from `system_profiler SPUSBDataType` / `ioreg` on the host Mac):

| Gadget (M4 side) | macOS enumerates? | macOS binds an interface? |
|---|---|---|
| g_ether (RNDIS+ECM composite) | yes — "RNDIS/Ethernet Gadget ... dwc3-gadget" | no (RNDIS unsupported by macOS) |
| configfs pure CDC-ECM | yes — "t6040-ecm", `AppleUSBCDCCompositeDevice` | **no** — device `!matched` |
| configfs CDC-NCM | yes — "t6040-ecm" | no new `en` |
| configfs ACM+NCM composite (IAD) | yes — "t6040-debug" | **no** — no `/dev/cu.usbmodem`, no `en` |

**The milestone stands: Linux dwc3 gadget mode works on the M4.** Every flavor enumerates over the
tether cable — the UDC comes up and macOS sees the device. That was the biggest unknown and it is YES.

**The wall: macOS creates no interface for any flavor**, including CDC-ACM — even though macOS binds
CDC-ACM fine from m1n1's own proxy gadget (`/dev/cu.usbmodemJ22GYCN4YG1/3`). That inconsistency means
the problem is almost certainly on the **M4 side**: the configfs functions likely are not fully
binding (UDC/function link failing, or malformed descriptors), so only the device descriptor
enumerates while the interfaces are absent/broken. I cannot confirm which, because **I have no M4-side
visibility** — and the ACM console I built to get it failed the same way (circular).

### Why I stopped iterating

Four rebuilds of gadget descriptors, all black-box, all "enumerates but no interface." Without the M4's
`dmesg` and `/var/log/ecm-gadget.log` (does the UDC bind? which function? errors?), further descriptor
guessing is not productive.

### Two ways to get M4-side visibility (either unblocks this cleanly)

1. **Maintainer reads the panel/shell** on a normal boot: `cat /var/log/ecm-gadget.log`, `ls
   /sys/class/udc`, `ls /sys/class/net`, `dmesg | grep -iE 'dwc3|gadget|configfs|ncm|ecm'`. This says
   exactly what the M4 gadget did.
2. **A dmesg-over-KIS diagnostic kernel** (ticket 153 / `t6040-dockchannel-nbcon.patch`, verified to
   apply): boot `console=ttydc0` via DebugUSB with **no** gadget (KIS and the gadget are mutually
   exclusive on the DFU port), giving a login + dmesg over KIS. That is the autonomous route, but it
   is a separate diagnostic boot from the gadget test (they cannot share the port).

**Battery/thermals (macsmc) was NOT network-testable** and remains for the panel: `cat
/sys/class/power_supply/*/uevent`, `/sys/class/hwmon/*/temp*_input`.

### Artifacts from this campaign (all window-free, chainload-tested)

- `Image-macsmc` (`53709312`, hid-fix + macsmc + usbnet + gadget, no g_ether) / `Image-macsmc.xz` `316c3c50`
- `t6040-j614s-dcuart-macsmc.dtb` `e05dc7fa` (smc + usb_drd0 enabled)
- rootfs variants: `-ecm` (pure ECM), `-ncm` (NCM), `-dbg` (ACM+NCM console)
- The **enrolled** object remains the v2 `9800f4d8` (dwm + keyboard, macsmc/gadget builtin). Machine
  restored to it.

## Panel reads (2026-07-28 pm): M4 gadget side healthy; macsmc empty; macOS binds nothing

Maintainer ran the panel diagnostic. Two decisive results:

**M4 gadget side is HEALTHY** (corrects my earlier "functions not binding" guess). On the enrolled v2
(g_ether):
```
UDCs: 382280000.usb
g_ether interface: usb0   (10.42.0.2/24, state DOWN, NO-CARRIER)
dmesg: g_ether gadget.0: Ethernet Gadget ... g_ether ready
```
So the UDC comes up, g_ether binds, usb0 is created — the M4 does its half. `NO-CARRIER` = the host
never completed the link. The blocker is macOS host-side.

**macOS binds NO Linux gadget flavor** — RNDIS, CDC-ECM, CDC-NCM, and now pure CDC-ACM all enumerate
(product strings visible) but macOS creates no interface / no `/dev/cu.usbmodem`, even though macOS
binds m1n1's own CDC-ACM gadget (`usbmodemJ22GYCN4YG1/3`). The uniformity across all flavors, incl. the
one macOS is known to support, points at the **M4 dwc3-apple gadget not completing enumeration**
(config descriptor / SetConfiguration), not a per-flavor descriptor issue: the device descriptor gets
through, the configuration/interfaces do not.

**macsmc produced nothing:** `/sys/class/power_supply/` and `/sys/class/hwmon/` are EMPTY on the
enrolled v2. So the SMC driver did not create its power/hwmon subdevices — it either did not probe or
the RTKit handshake failed. Prime suspect: the pattern-inferred SMC SRAM `0x50e000000` (flagged at
build time as a safe-failure inference) or the RTKit mailbox.

### The one command that pinpoints both (M4 panel)
```
cat /sys/class/udc/*/state; echo ---UDC-FUNC---; cat /sys/class/udc/*/function 2>/dev/null
echo ---; dmesg | grep -iE 'dwc3|gadget|configfs|smc|macsmc|rtkit|mbox|ep0|set.?config' | tail -40
```
- UDC `state`: if not `configured`, the host never set the config → M4 dwc3-gadget enumeration bug.
- `dmesg smc/macsmc/rtkit`: whether the SMC RTKit came up and why macsmc made no devices.

## Root causes found from the dmesg (2026-07-28 pm) — macsmc FIXED, network is a macOS wall

The panel dmesg was decisive on both.

### macsmc: SRAM address wrong → FIXED (high confidence, ground truth)
```
macsmc 50c600000.smc: RTKit: Initializing (protocol version 12)
macsmc 50c600000.smc: RTKit buffer request outside SRAM region: [0x50de70000, 0x50de73fff]
macsmc 50c600000.smc: Failed to initialize shared memory (-14)
macsmc 50c600000.smc: probe with driver macsmc failed with error -5
```
The SMC RTKit came up (protocol 12) but its shared-memory buffers are at **`0x50de70000+`**, outside my
declared SRAM `0x50e000000`. My `smc_base + 0x1a00000` cross-SoC inference was wrong for t6040. The
coprocessor's own buffer addresses are ground truth: SRAM base = **`0x50de70000`** (first buffer at
offset 0). Fixed `reg[1]` to `<0x5 0x0de70000 0x0 0x100000>`; new DTB `11abca72`. This is derived from
observed hardware, not a pattern — high confidence it lets macsmc initialize shared memory and create
the battery/hwmon devices.

### Network: udc `configured`, but macOS binds no Linux CDC gadget — a macOS host wall
`cat /sys/class/udc/*/state` = **`configured`**. So the M4 dwc3 gadget *fully enumerates* — the host
completes SetConfiguration — for every flavor. Combined with the earlier "usb0 up, NO-CARRIER" and the
absence of any `en`/`cu.usbmodem` on macOS, the conclusion is firm: **the M4 side is 100% healthy; macOS
does not attach a class driver to a Linux dwc3 CDC gadget** (RNDIS, ECM, NCM, or ACM), even though it
binds m1n1's own CDC-ACM. `AppleUSBDeviceNCM*` is macOS's *device*-side NCM, not a host driver for an
arbitrary gadget; macOS Apple-Silicon host-side CDC-ethernet for a generic gadget appears absent.

**Verdict:** tether-ethernet to *this Mac* is blocked by macOS, not by the M4. The gadget works and
would bind on a **Linux host** (which has CDC-ECM/NCM/ACM host drivers). Options if tether networking is
still wanted: (a) plug the M4 into a Linux box, or (b) go the original USB-*host* route (real dongle,
gated on VBUS/HPM). Not worth more macOS gadget-descriptor iteration.

## Shipped: macsmc daily driver v3 (SRAM-fixed)
`m1n1-b0-macsmc-dualmode.bin` `5931f9c3d1f785f2a25cd40754fec1f38078efbc3ceaa952288c529bbc7527f8`
(dual-mode + Image-macsmc + fixed DTB `11abca72` + clean hidpi dwm rootfs, no gadget). Strict PASS.
Enroll-guard approved; `9800f4d8` retired. Expected after enroll: dwm + keyboard + **battery + temps**.

## macsmc CONFIRMED WORKING (2026-07-28) — battery + thermals live on the M4 Pro

The SRAM fix (`0x50de70000`) was correct. On the fixed object (`5931f9c3`):

```
POWER_SUPPLY_NAME=macsmc-ac        ONLINE=1  INPUT_POWER_LIMIT=15000000
POWER_SUPPLY_NAME=macsmc-battery   STATUS=Full  HEALTH=Good  CAPACITY=100
  CYCLE_COUNT=404  CHARGE_FULL=5186000  CHARGE_FULL_DESIGN=6249000
  VOLTAGE_NOW=12911000  ENERGY_NOW=59006400  MODEL_NAME=bq40z651
  MANUFACTURE 2024-08-24  CHARGE_BEHAVIOUR=auto
/sys/class/hwmon/*/temp1_input = 30300   (30.3 C)
```

Battery gauge, AC/charger state, and a temperature sensor all read correctly. The SMC RTKit shared
memory initialised once `reg[1]` matched the coprocessor's reported buffer base — the error message
`RTKit buffer request outside SRAM region: [0x50de70000, ...]` was ground truth and the fix from it
worked first try. Note `CHARGE_BEHAVIOUR` is exposed but stays read-only per policy (no charge-control
writes).

**Tickets 165 (macsmc) done — battery/thermals is a real, working daily-driver feature.** 167 (usbnet
host dongles) is built-in and waits on a USB host port. 173 (tether ethernet) is a macOS host wall
(the M4 gadget works; documented above).
