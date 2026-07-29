# dwm image gets a ttydc0 getty (the payload is now host-drivable), and maxcpus=14 hangs early with the full driver set

2026-07-29, over KIS with the rollback loader enrolled.

## 1. The getty change — done, and it removes the blindness

The dwm payload could previously only be observed at the panel: `console=ttydc0` alone produced
nothing over KIS, and the USB-ACM console in that image is inert because macOS binds no Linux CDC
gadget (173). So every diagnostic became "please read the screen", which cost several boots and
produced almost nothing.

`scripts/t6040-build-alpine-dwm.sh` now installs the proven B0 helpers
(`t6040-b0-ttydc0-console` + `t6040-b0-autologin`) and adds one inittab line:

```text
::respawn:/usr/local/sbin/t6040-b0-ttydc0-console
```

**Verified working.** Booting the rebuilt image at `maxcpus=1`,
`scripts/t6040-boot-raw-object.sh` reports *"userspace: a shell prompt appeared"*, and the payload is
now driven from the host exactly like the minimal roots:

```sh
printf 'nproc; ls /sys/class/bluetooth\n' > /tmp/m1n1
tail -f ~/Code/linux-build-out/raw-object-console.log
```

Image: `initramfs-alpine-dwm-wifi-bt-ppp-getty.cpio.xz`
`b7b1a4dfa4876242a04439bac786510dee2d61907a4a02ad4b0eeafc533d240f`, 21,964,472 B, expands to
91,718,256 B (87.5 MiB, under the decode limit), **minilzlib harness PASS**. Built with
`T6040_PPP=1 T6040_WIFI_USERLAND=1 T6040_BT_USERLAND=1 T6040_WIFI_FW=1`.

## 2. Bonus result: the SD card reader driver binds

First time the GL9755 has had a driver, courtesy of the `MMC_SDHCI_PCI=y` kbuild change:

```text
sdhci-pci 0000:02:00.0: SDHCI controller found [17a0:9755] (rev 2)
sdhci-pci 0000:02:00.0: enabling device (0000 -> 0002)
mmc0: SDHCI controller on PCI [0000:02:00.0] using ADMA 64-bit
```

No `/dev/mmcblk*` appeared, which is expected with an empty slot — insert a card to finish the test.
Also confirmed on the same boot: `wlan0` present with the module's OTP MAC `84:2F:57:33:9E:D7`, and
`hci0` present. No oops, no panic. (A `grep -icE "oops|panic|BUG:"` returned 1, but the match was
`printk: **debug**: ignoring loglevel setting` — case-insensitive `bug:` inside "debug:". False
positive; worth remembering when writing these greps.)

## 3. maxcpus=14 with the full driver set: hangs before any console registers

Same object, same image, **only the bootargs differ** (`maxcpus=1` → `maxcpus=14`):

| bootarg | result |
|---|---|
| `maxcpus=1` | kernel messages over KIS, shell prompt, WiFi/BT/SD all probe |
| `maxcpus=14` | **zero bytes** on the console, no shell, panel keeps m1n1's logo |

Zero console bytes means it dies *before* the DockChannel tty registers its console, i.e. earlier
than driver probe. This is not the initramfs-unpack oops from the earlier session (different, proven
archive, and that one still printed plenty first).

**Note the contrast with the SMP smoke:** on `Image-dcuart-earlycon` with the storage/PCIe-free DTB,
`maxcpus=14` reached `SMP: Total of 14 processors activated` and the full 4E+5P+5P mapping. So 14-core
bringup itself works; what fails is 14 cores *plus* the full driver set (PCIe, WiFi, BT, SD, trackpad
HID, SMC).

Secondary observation from CJ at the panel: with `maxcpus=14` the **fan spins up and the underside
warms**. That is consistent with the cores being online and is a direct consequence of `idle=nop` —
which exists because the M4 loses CPU state on WFI/WFE, so the idle loop *spins* rather than sleeping.
One spinning core is invisible; fourteen is a space heater. **This promotes cpuidle from a nicety to a
prerequisite for SMP being usable**, ahead of cpufreq (006).

## Next step for this

Diagnosis needs `earlycon` on the *daily-driver* kernel — it currently has the nbcon patch
(`DOCKCHANNEL_NBCON=1`) but not `patches/t6040-dockchannel-earlycon-debug.patch`, so there is no
output before driver probe. Rebuild that kernel with the earlycon patch as well, boot at
`maxcpus=14`, and read where it stops. Until then:

**Keep `maxcpus=1` in anything enrolled.** The enrollable object `679fe133` / the v116 rebuild
`679fe133`-class is unaffected and remains correct as reviewed.
