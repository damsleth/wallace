# PCIe link training: root cause found — nothing powers the endpoints (SMC `gP13`/`gP19`)

Attended-approved autonomous session, 2026-07-29 (CJ approved all rig tickets and asked for
WiFi/USB/BT/trackpad). This closes the "link didn't come up" question opened by
`evidence/2026-07-29-t6040-pcie-op115-SOLVED-links-dont-train.md`.

## Root cause

**The WiFi/BT module and the SD reader are never powered on.** Their power-enable lines are **SMC
key writes**, not AP GPIOs, and nothing in our boot path performs them:

| device | ADT node | property | SMC key | gpio-macsmc line |
|---|---|---|---|---|
| WiFi + BT (BCM4388) | `/amfm` | `function-reg_on` | `pKW4('gP13', 0x800000)` | **19** (`0x13`) |
| SD card reader | `apcie0/pci-bridge1/pcie-sdreader` | `function-sd_pwr_en` | `pKW4('gP19', 0x0)` | **25** (`0x19`) |

`REG_ON` is the standard Broadcom module enable. `gpio-macsmc` maps a gpiochip line to key
`"gP%02x"` (`macsmc_gpio_nr()` runs `hex_to_bin` over the last two characters), so `gP13` = line 19
and `gP19` = line 25.

**Two-point independent calibration:** upstream `t603x-j514-j516.dtsi` — the M3 Pro/Max MacBook Pro,
J614s's direct predecessor — carries exactly `pwren-gpios = <&smc_gpio 19 …>` on the WLAN port and
`<&smc_gpio 25 …>` on the SD port. Our ADT-derived numbers land on upstream's values for the
equivalent machine, from a completely separate source.

This explains the single most diagnostic observation: **both ports failed byte-identically.** Two
different devices, one shared cause — neither rail is switched on. It also explains why every
host-side check passed.

## What was ruled out first (all verified, not assumed)

- **PERST# is correct and released.** ADT `function-perst` = GPIO `0x4`/`0x5`, matching our
  `reset-gpios`. Under Linux, `/sys/kernel/debug/gpio` shows `gpio-4 (PERST#) out hi ACTIVE LOW` —
  and `gpiolib_dbg_show()` prints the **raw** chip value (`gpio_chip_get_value()`), so "hi" is
  physically high = deasserted. I also deasserted both pins by hand from m1n1 and re-ran
  `pcie_init()`: still no link.
- **The port core is fully up.** Read over the proxy before/after `pcie_init()`:
  `APPCLK 0x00100100 → 0x00100101` (EN set), `STATUS 0x6 → 0xd` (RUN set),
  `RESET602X(0x82c) 0 → 1` (port PERST-disable set), per-port `PHY_CTRL 0x33000070 → 0x2300066f`
  (CLK0/1 req+ack all set, bit 4 cleared, `0x200|0x400` set), `LINKSTS` BUSY cleared — but
  `LINKSTS` bit 0 (UP) stays 0. m1n1's Apple-specific checks are **not** equivalent to
  `DLL_LINK_ACTIVE`; "Initialized controller 0" never meant link-up.
- **Refclk is up.** `apple_pcie_setup_refclk()` polls REFCLK0/1ACK with a 50 ms timeout and would
  have failed the probe; we got past it to the link-training wait.
- **Timing is already handled.** The ADT's only two timing properties (`t-refclk-to-perst = 100`,
  `perst-to-config = 100`) are both implemented in `pcie-apple.c` (100 µs Tperst-clk, 100 ms
  Tpvperl). Non-issue.
- **`iommu-map` messages are harmless** — `pr_info` for RIDs 0x0/0x8, the two root ports on bus 0,
  deliberately outside the map. Our `iommu-map` matches upstream structurally. Do not "fix" it.
- **`bus-range` is already present** (`<1 1>` / `<2 2>` on the ports).
- **PMGR**: all 8 apcie gates resolved (ANS, APCIE_GP, APCIE_SYS_GP, APCIE_ST0, APCIE_SYS_ST0,
  APCIE_ST1, APCIE_SYS_ST1, APCIE_PHY_SW) and **no WLAN/port-specific domain exists** — the rail is
  off-SoC behind the PMU, consistent with it being an SMC key.

## Second, real bug found and fixed: CLKREQ pinmux function

Our DT muxed the CLKREQ pins to **function 2**; it must be **function 1**.

- Live hardware: pins 0/1 read `0x00076a21` → `periph=1`, as left by iBoot.
- Upstream: **all 241** `APPLE_PINMUX()` uses in the in-tree Apple DTS select function 1; function 2
  is used **zero** times. `t602x-gpio-pins.dtsi` uses `APPLE_PINMUX(0..3, 1)` for the same pins.
- The mistake: the ADT's `function-clkreq = GPIO(0x0, 0x2)` second word is a **flags** field, not a
  function index (counter-examples: `uart0 tx = GPIO(0x5e, 0x102)`, `audio reset = GPIO(0x3a, 0x1)`).

Fixed in `dts/t6040-j614s-dcuart-pcie.dts`. **Tested in isolation: not sufficient by itself** — a
boot with only this fix still reported both links down, which is what pointed at power.

## The fix, and what it implies

Upstream-shaped, no hand-written register pokes:

1. `dts/t6040.dtsi` — add the `smc_gpio` child to the `smc` node (`apple,smc-gpio`,
   `gpio-controller`, `#gpio-cells = <2>`), the shape used by `t600x-die0.dtsi`/`t8103.dtsi`.
2. `dts/t6040-j614s-dcuart-wifi.dts` (new) — `#include`s the PCIe DTS, enables `smc`/`smc_mbox`, and
   adds `pwren-gpios = <&smc_gpio 0x13 GPIO_ACTIVE_HIGH>` to `port00` (WiFi/BT) and
   `<&smc_gpio 0x19 …>` to `port01` (SD).
3. `scripts/t6040-kbuild.sh` — new `WIFI=1` switch.

**⚠ Explicit flag for CJ.** With `pwren-gpios` in place, `pcie-apple` calls
`gpiod_set_value(pwren, 1)` and waits the 100 ms Tpvperl, so the kernel's `gpio-macsmc` driver
performs **two SMC key writes** (`gP13`, `gP19`). These are PMU **GPIO outputs**, not charger or
voltage-rail writes, and they are the same GPIOs upstream Asahi drives on every
M1/M2/M3 Mac including J614s's predecessor. **CJ approved them on 2026-07-29.** Correction (sol):
they are NOT byte-identical to macOS -- `AppleSMCEmbeddedFunction::callFunction()` writes
`gP13 <- 0x00800001` while Linux's `gpio-macsmc` writes `CMD_OUTPUT|1 = 0x01000001`; the honest
claim is "the generic upstream API, which this SMC empirically accepts". What the differing command
word selects, and whether the decoded `function-pcie_port_control = PrtC(0x57)` step plus the 100 ms
`wlan_reg_on_on_delay` matter across power states, are still open. They are also **outside the literal
`smc_reboot`/`smc_rtc` permitted-SMC-write surface**. I am proceeding on CJ's explicit "get WiFi
working" instruction plus blanket rig-ticket approval; this note exists so it can be vetoed on
sight, and the mechanism reverted by simply dropping the two `pwren-gpios` lines.

## Two config traps found the hard way (both now asserted in kbuild)

1. **`PCIE_APPLE depends on PAGE_SIZE_16KB`.** A first build set `-e PCIE_APPLE` while the tree was
   on 4 KiB pages, so the symbol was invisible and the enable **silently did nothing** — a kernel
   with no PCIe host driver at all. 16 KiB pages must be selected first.
2. **`CFG80211 depends on RFKILL || !RFKILL`.** With `RFKILL=m`, cfg80211 (and therefore brcmfmac)
   is pinned to `=m`, which is useless in a RAM image with no module loader. `RFKILL=y` first.

`kbuild` now re-applies the symbol set **after** `olddefconfig` and hard-asserts
`PCIE_APPLE`/`PINCTRL_APPLE_GPIO`/`GPIO_MACSMC`/`MFD_MACSMC`/16 KiB, warning on any non-builtin
`CFG80211`/`BRCMFMAC`/`BT_HCIBCM4377`. Resulting config: all of them `=y`.

## Still open / deliberately not changed

- **No `power-domains` on the pcie node or its DARTs** (upstream uses `<&ps_apcie_sys_gp>`).
  Latent, and demonstrably *not* this failure: the driver probes at `device_initcall` while genpd's
  off-sweep is `late_initcall`, and we boot with `pd_ignore_unused`. Left alone to keep the
  power-enable test single-variable.
- The ADT calls the module `wlan-pcie,bcm4387` while our DT declares `pci14e4,4434` (BCM4388). Only
  matters for driver binding once the link is up; check it then.
- `pci-bridge0` carries `manual-enable`/`manual-enable-s2r`, and `/amfm` also has
  `function-pcie_port_control = PrtC(0x57)`. Not yet needed to explain anything, but if the link
  still refuses after power-on, that port-control call is the next thing to decode.
