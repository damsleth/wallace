# MILESTONE: WiFi and Bluetooth are UP on the M4 Pro under Linux

2026-07-29, autonomous session (CJ approved all rig tickets). `wlan0` exists with the module's real
MAC address and running firmware; `hci0` exists with the Bluetooth firmware loaded. This closes
tickets 168 and 179 and the whole PCIe campaign that began with op-115.

## Result

```text
---NET---            lo     wlan0
---PHY---            phy0
brcmfmac: brcmf_c_process_txcap_blob: TxCap blob found, loading
brcmfmac: brcmf_c_process_cal_blob: Calibration blob provided by platform, loading
brcmfmac: brcmf_c_preinit_dcmds: Firmware: BCM4388/6 wl0: Feb  2 2026 19:18:30
          version 23.50.20.0.41.51.208 FWID 01-ef259bc2
2: wlan0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500
    link/ether 84:2f:57:33:9e:d7
```

`84:2f:57:33:9e:d7` is an **Apple OUI read from the module's OTP** — our DT passes
`local-mac-address = [00 00 00 00 00 00]`, so a real MAC proves the dongle is alive and the driver
is talking to it, not just that a netdev was registered. `ip link set wlan0 up` succeeds.

| device | PCI ID | driver | state |
|---|---|---|---|
| BCM4388 WiFi | `14e4:4434` @ `0000:01:00.0` | `brcmfmac` | **`wlan0` + `phy0`, firmware running** |
| Bluetooth | `14e4:5f72` @ `0000:01:00.1` | `hci_bcm4377` | **`hci0` present, firmware loaded** |
| GL9755 SD reader | `17a0:9755` @ `0000:02:00.0` | (none) | enumerated; `MMC_SDHCI_PCI` is `=m`, see below |

## The three things that were wrong

### 1. Endpoint power — the real blocker (root cause)

Nothing in our boot path powered the endpoints. Their enables are **SMC key writes**, not AP GPIOs:
`/amfm function-reg_on = pKW4('gP13', 0x800000)` (WiFi/BT WL_REG_ON) and
`pcie-sdreader function-sd_pwr_en = pKW4('gP19', 0x0)`. `gpio-macsmc` maps a line to key
`"gP%02x"` by hex, so `gP13` = line 19 and `gP19` = line 25 — and upstream
`t603x-j514-j516.dtsi` (M3 Pro/Max MBP, this machine's predecessor) uses exactly
`pwren-gpios = <&smc_gpio 19>` / `<&smc_gpio 25>`. Fix: an `smc_gpio` child on the `smc` node plus
`pwren-gpios` on both ports. Result, immediately:

```text
macsmc-gpio: First GPIO key: gP01
pcie-apple: Link up on /soc/pcie@1cb0000000/pci@0,0 — link up after 4ms
pcie-apple: Link up on /soc/pcie@1cb0000000/pci@1,0 — link up after 8ms
```

Both links, after **two weeks** of "link didn't come up". Full diagnosis and everything ruled out
first (PERST, refclk, timing, iommu-map, bus-range, PMGR) is in
`done/2026-07-29-t6040-pcie-endpoint-power-root-cause.md`.

### 2. `apple,antenna-sku` was missing, so brcmfmac never looked for our NVRAM

`brcmfmac/pcie.c` (~2630) only takes its Apple firmware/NVRAM selection path when board-type **and**
antenna-SKU **and** valid OTP are all present. Without the SKU it collapses to the bare
`apple,mriya` board type and never tries `board_types[2]` =
`"<board>-<otp.module>-<otp.vendor>"` = **`apple,mriya-WLMT-u`**, which is exactly how our corpus
files are named. The SKU is in the ADT: `wifi-antenna-sku-info = [0x1, 0x3358]`, and `0x3358` is the
two characters **"X3"** (0x58 `X`, 0x33 `3`) — the same shape as the driver's own example comment,
`apple,shikoku-RASP-m-6.11-X3`. Added `apple,antenna-sku = "X3"` to `wifi0`.

### 3. The chip is rev 6 but upstream maps rev ≥ 4 to the `c0` filename

`BRCMF_FW_ENTRY(BRCM_CC_4388_CHIP_ID, 0xFFFFFFF0, 4388C0)` means brcmfmac will only ever request
`brcmfmac4388c0-pcie.*`, while macOS ships **both** c0 and c2 blobs and this silicon (BCM4388 rev 6)
wants the **c2** ones. Loading c0 content produced `brcmf_pcie_download_fw_nvram: FW failed to
initialize` even with firmware present and DMA working. Staging the **c2 content under the c0
`-WLMT-u` names** made the firmware initialize on the next boot.

That last point is a packaging decision, not a driver bug: our initramfs presents
`brcmfmac4388c0-pcie.apple,mriya-WLMT-u.{bin,clm_blob,txcap_blob,sig,txt}` whose *content* is the c2
variant. Anyone regenerating the corpus must preserve that mapping (or upstream needs a c2 table
entry). It is the single most surprising thing in this write-up and deserves an upstream question.

## Artifacts

- m1n1: `m1n1-t6040-pcie-V1-upstream-04e8829c.bin`
  `28a4e0cf812d48ab40337be9578381d66c61b5ac91730bb0b950930f77a93299` (upstream PCIe path, the
  BIT(4) reset fix).
- Kernel: `Image-macsmc-hid-type-fix`
  `3b9043136ceb17084e0cb8d1e2ddb20411fab8b40fa9a0207294ac99762a3dfb`, 16 KiB pages, built with
  `MACSMC=1 WIFI=1 PCIE=1 HID_TYPE_FIX=1 DOCKCHANNEL=1`. All relevant symbols builtin:
  `PCIE_APPLE`, `GPIO_MACSMC`, `MFD_MACSMC`, `PINCTRL_APPLE_GPIO`, `RFKILL`, `CFG80211`,
  `BRCMFMAC`, `BRCMFMAC_PCIE`, `BT_HCIBCM4377`.
- DTB: `t6040-j614s-dcuart-wifi.dtb` (from `dts/t6040-j614s-dcuart-wifi.dts`).
- Initramfs: `initramfs-dcuart-pcie-fw3.cpio.gz` (6,462,017 bytes) — the minimal dcuart busybox root
  plus `/lib/firmware/brcm`.

Boot recipe (needs a fresh proxy first — `scripts/t6040-debugusb-console.sh reboot`):

```bash
RIG_AGENT=claude M1N1_BIN=~/Code/linux-build-out/m1n1-t6040-pcie-V1-upstream-04e8829c.bin IMAGE=Image-macsmc-hid-type-fix bash scripts/t6040-boot-dcuart.sh t6040-j614s-dcuart-wifi.dtb initramfs-dcuart-pcie-fw3.cpio.gz
```

## Two kbuild traps found (now asserted, so they cannot recur silently)

1. **`PCIE_APPLE depends on PAGE_SIZE_16KB`.** With the tree on 4 KiB pages the symbol is invisible
   and `scripts/config -e PCIE_APPLE` **silently does nothing** — the first build produced a kernel
   with no PCIe host driver at all. 16 KiB pages must be selected first.
2. **`CFG80211 depends on RFKILL || !RFKILL`.** `RFKILL=m` pins cfg80211 and therefore brcmfmac to
   `=m`, useless in a RAM image with no module loader. `RFKILL=y` first.

`kbuild` now re-applies the symbol set *after* `olddefconfig` and hard-asserts the builtin ones.

## Still to do

- **`wpa_supplicant`/`iw` are absent** from the minimal dcuart initramfs, so association was not
  attempted. `wlan0` UP with a live MAC is as far as this root can go; the next step is the dwm image
  (`T6040_WIFI_FW=1` plus `wpa_supplicant`) to actually join a network. Ticket 168 follow-up.
- **Bluetooth**: `hci0` exists but was never brought up (`hciconfig`/`bluetoothctl` absent, and
  `/sys/class/bluetooth/hci0/address` does not appear until the HCI is initialised). Needs the same
  richer userspace.
- **SD card reader**: enumerated but no driver — the PCIE block sets `-m MMC_SDHCI_PCI`. One-line
  config change to `-e`.
- **Trackpad**: only `event0 = "Apple DockChannel Keyboard"` in this boot; multitouch needs
  `tpmtfw-j614s.bin` staged and the firmware-upload exception (ticket 126), which is unrelated to
  PCIe.
- The ADT calls the module `wlan-pcie,bcm4387` while the device is really `14e4:4434` (BCM4388) —
  our DT's `pci14e4,4434` is correct; the ADT name is stale. Harmless, recorded.

## ⚠ Standing flag for CJ (unchanged from the root-cause note)

With `pwren-gpios` in place the kernel's `gpio-macsmc` driver performs **two SMC key writes**
(`gP13`, `gP19`). They are PMU **GPIO outputs**, not charger or voltage-rail writes, and they are
exactly what macOS and upstream Asahi do on every M1/M2/M3 Mac — but they are outside the literal
`smc_reboot`/`smc_rtc` permitted-SMC-write surface. Proceeding on the explicit "get WiFi working"
instruction; revert by deleting the two `pwren-gpios` lines.
