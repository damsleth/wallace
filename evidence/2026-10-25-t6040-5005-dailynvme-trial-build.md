# 5005 daily+NVMe kernel and DTB: trial build (claude, 2026-10-25, offline)

## Kernel union (trial3, single build: compile and config check only)

Flags: the daily301 set (`DOCKCHANNEL DOCKCHANNEL_NBCON MACSMC HID_TYPE_FIX
T6040_PPP WIFI PCIE CPUFREQ TRACKPAD_FW TRACKPAD_RESET_CONTRACT`) plus
`NVME NVME_IOQ_SIZE NVME_EXFAT NVME_FLUSH_TCB`.

- Trial 1 failed the WiFi assert (`SPMI_APPLE`, `NVMEM_APPLE_SPMI`,
  `RTC_DRV_MACSMC` LOST): the `NVME_IOQ_SIZE` block forced them off, which
  is right for the minimal read/write test kernel. Trial 2 then hit the IOQ
  forbidden-config guard. Both now make an exception only when `WIFI=1`
  (48c7384 and its parent), so the 5003 test kernel config is unchanged.
- Trial 3: `exit=0`, every assert passed. `SPMI_APPLE`, `RTC_DRV_MACSMC`,
  `BRCMFMAC`, `MMC_SDHCI_PCI`, `NVME_APPLE`, `EXFAT_FS` are all `=y`.
  `t6040-nvme-apple-flush-tcb.patch` applies and compiles.
- Image `6511006d16f36673…`,
  config `96e83d858ddbbcf1…`.
  This is not a release candidate: the flush fix waits on probe 5006, then
  comes the final flag set and two identical builds.

## DTB `dts/t6040-j614s-dcuart-wifi-cpufreq-nvmeroot.dts`

Compiled in the trial3 tree from the repo's `dts/` files. As a method check,
the same procedure rebuilt the daily sdroot DTB **byte-identical to the pinned
`c5c3b4c3…`**.

- `t6040-j614s-dcuart-wifi-cpufreq-nvmeroot.trial3.dtb`
  `6d2d3da60352c93a6973dc068addcb7d2b1fd05a504506eb580bb18293c48e20`
- The decompiled diff against sdroot `c5c3b4c3` is exactly the model string
  plus `status = "okay"` on `mailbox@409608000`, `iommu@40dc50000` (SART)
  and `nvme@44dcc0000`. These are the same nodes and addresses that 6001 and
  5003 ran with. `nub_spmi0`, `smc_rtc` and `smc_reboot` stay disabled.
