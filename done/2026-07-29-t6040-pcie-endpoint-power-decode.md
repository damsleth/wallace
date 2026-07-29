# T6040 PCIe link training: how the BCM4388 gets powered, and what our boot path never does

Offline-only decode for ticket 179. **No rig contact**: no script in `scripts/` was run, no lease was
taken, no proxy was opened. Everything below comes from static files: the captured J614s ADT, the
in-tree Linux sources, our own DTS/DTB artifacts, and the two attended logs from this morning.

Every claim is tagged **MEASURED-FROM-ADT**, **MEASURED-FROM-DTB**, **READ-FROM-SOURCE**, or
**INFERENCE**. Where I could not determine something I say so and say what I tried.

Inputs:

| file | SHA-256 | used for |
|---|---|---|
| `linux-build-out/j614s-usb-port-map-20260721.adt` | `7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84` | primary ADT |
| `linux-build-out/j614s-full-20260728.adt` | (not re-hashed; read for cross-check) | independent confirmation — **identical** on every point below |
| `linux-build-out/t6040-j614s-dcuart-pcie.dtb` | 55 KiB, 2026-07-14 09:05 | the DTB that booted this morning |
| `linux-build-out/t6040-j614s-dcuart-pcie-clkreqfix.dtb` | 55 KiB, 2026-07-29 10:36 | the concurrent session's in-flight variant |
| `linux-build-out/pcie-v1-linux-console-20260729.log` | `77a1fdc5…` (per milestone doc) | dmesg ordering/timing |

ADT read with m1n1's `proxyclient/m1n1/adt.py` `load_adt()` on the file, no hardware.

---

# 1. VERDICT — ranked hypotheses for why the links do not train

## Rank 1 (highest confidence): **no `pwren-gpios`. The endpoint rails are never switched on.**

Our DT has no `pwren-gpios` on either port, no `smc_gpio` provider, and no SMC node at all in the
PCIe boot variant. Upstream Linux powers every on-board Apple PCIe endpoint from an **SMC PMU GPIO**
declared as `pwren-gpios` on the port node, and `pcie-apple` drives it in `apple_pcie_setup_link()`.

The ADT gives us both keys, and they calibrate **exactly** against the closest upstream machine:

| device | ADT operation | SMC key | Linux `smc_gpio` index | upstream J514s/J516s |
|---|---|---|---|---|
| WiFi/BT (port 0) | `/amfm  function-reg_on = 294:pKW4('gP13', 0x800000)` | `gP13` | 0x13 = **19** | `t603x-j514-j516.dtsi:220` `pwren-gpios = <&smc_gpio 19 GPIO_ACTIVE_HIGH>` |
| SD reader (port 1) | `/arm-io/apcie0/pci-bridge1/pcie-sdreader  function-sd_pwr_en = 294:pKW4('gP19', 0x0)` | `gP19` | 0x19 = **25** | `t603x-j514-j516.dtsi:240` `pwren-gpios = <&smc_gpio 25 GPIO_ACTIVE_HIGH>` |

Two independent keys, both matching the M3 Pro/Max MacBook Pro (the direct predecessor of J614s) on
the nose. This is not a coincidence and it is not an inference about which pin — the ADT names the
key and `gpio-macsmc` names the same key from the index.

This one hypothesis explains **both** failures with one cause, which no other candidate does.

**Check that confirms/refutes it** — DT-only, no m1n1 rebuild, no register writes by us:

```dts
&port00 { pwren-gpios = <&smc_gpio 19 GPIO_ACTIVE_HIGH>; };   /* WiFi  — SMC key gP13 */
&port01 { pwren-gpios = <&smc_gpio 25 GPIO_ACTIVE_HIGH>; };   /* SD    — SMC key gP19 */
```
plus a `smc_gpio: gpio { compatible = "apple,smc-gpio"; gpio-controller; #gpio-cells = <2>; };`
child on the working `smc` node in `dts/t6040.dtsi:471`, and the PCIe variant rebased on the
**macsmc** variant so `&smc`/`&smc_mbox` are `okay`.

**⚠ HARDWARE WRITE.** This performs two new SMC key writes we have never done:

- `gP13` ← `0x01000001` (`CMD_OUTPUT | 1`) — `gpio-macsmc.c:186-196` **READ-FROM-SOURCE**
- `gP19` ← `0x01000001` — same path

These are PMU **GPIO output** commands, not charger current/voltage and not an SPMI rail
programming write. They are what macOS's `AppleBCMWLANBusInterfacePCIe`/`amfm` does, and what
upstream Linux does on every Apple Silicon Mac. Per the standing rule
(`smc_reboot`/`smc_rtc` permitted, charger/PMU-voltage forbidden) this is **new surface and needs
CJ's explicit approval**; it is not covered by the existing permission. Naming it precisely:
SMC keys `gP13` and `gP19`, 4-byte writes, value `0x01000001`.

Secondary consequences to plan for, both **READ-FROM-SOURCE**:

- `apple_pcie_probe_port()` (`pcie-apple.c:928-950`) makes the whole controller's probe **depend**
  on the pwren GPIO resolving. If `smc_gpio` is absent or SMC fails, `pcie-apple` defers forever and
  we lose the root-port enumeration we already have. The combined DTB must carry the *proven* macsmc
  stack (`dts/t6040.dtsi` smc @ `0x50c600000`, sram `0x50de70000` — the version confirmed working in
  commit `023c164`), **not** the stale `dts/t6040-j614s-dcuart-smc.dts` (which declares a second
  `smc:` label at `0x30c600000` and would collide).
- `CONFIG_GPIO_MACSMC` must be **`=y`**. `config-macsmc-wifi-fw` and
  `config-macsmc-hid-type-fix-nbcon-wifi-fw` have it as `=m`; only `config-wifi-fw` has `=y`.
  A module that is never loaded means permanent probe deferral. **MEASURED** from those config files.
- With `pwren` present the driver switches the pre-PERST delay from `usleep_range(100,200)` to
  `msleep(100)` (`pcie-apple.c:622-625`) — i.e. Tpvperl. This is strictly more conservative than the
  ADT's `t-refclk-to-perst = 100`.

## Rank 2 (high confidence, independent, free to test in the same boot): **CLKREQ pinmux function is 2; upstream is unanimously 1.**

Our DT: `pcie_pins { pinmux = <0x20000>, <0x20001>; }` = `APPLE_PINMUX(0,2)`, `APPLE_PINMUX(1,2)`
(`dts/t6040-j614s-dcuart-pcie.dts:56-57`, and `pinmux = <0x20000 0x20001>` in the booted DTB
line 2592) — **MEASURED-FROM-DTB**.

- Across the **entire** in-tree Apple DTS set, all **241** `APPLE_PINMUX(...)` uses select function
  **1**. Function 2 is used **zero** times. `pcie_pins` is function 1 on t8103, t8112, t600x, t602x,
  t6030, t6031 and t8122 without exception. **MEASURED** (`grep -rho 'APPLE_PINMUX([0-9]*, *[0-9]*)'`
  over `arch/arm64/boot/dts/apple/`).
- Function 2 is a *valid* value (`REG_GPIOx_PERIPH = GENMASK(6,5)`, names
  `"gpio","periph1","periph2","periph3"`, `pinctrl-apple-gpio.c:56` and `:442`), so it passes the
  bounds check at `pinctrl-apple-gpio.c:141-144` and is silently applied. **There is no dmesg
  error** — exactly matching our silent failure. **READ-FROM-SOURCE**.
- The project's "GPIO 0 fn 2" reading came from the ADT `function-clkreq = GPIO(0x0, 0x2)` second
  word. **That word is a flags bitfield, not a function index.** Counter-examples from the same ADT
  (**MEASURED-FROM-ADT**): `/arm-io/uart0 function-tx = GPIO(0x5e, 0x102)`,
  `/arm-io/spi2/mesa function-mesa_pwr = GPIO(0x35, 0x101)`,
  `/arm-io/i2c2/audio-codec-output function-reset = GPIO(0x3a, 0x1)`,
  `/arm-io/i2c1/audio-speaker function-reset = GPIO(0x36, 0x10001)`,
  `/arm-io/apcie0 function-debug_gpio = GPIO(0x4d, 0x101)`. A GPIO *reset* line cannot be
  "function 1", and `0x102` cannot be both "function 2" and carry bit 8. The bits behave as flags
  (`0x1`/`0x100`/`0x10000` recur on plain GPIOs; `0x2` appears on `uart0 tx` and the two CLKREQ pins,
  i.e. the pins that are genuinely muxed away from GPIO). **INFERENCE**, but the upstream
  unanimity is the operative evidence either way.

The concurrent session has already built exactly this change:
`t6040-j614s-dcuart-pcie-clkreqfix.dtb` differs from the booted DTB in **one word pair**,
`pinmux = <0x20000 0x20001>` → `<0x10000 0x10001>` — **MEASURED-FROM-DTB** (full `diff` of the two
decompiled trees shows only line 2592). That change is correct and should be kept.

**Check:** boot with function 1. No hardware write by us beyond what pinctrl already does.

**Recommendation on ordering:** both Rank 1 and Rank 2 are DT-only and each is independently
justified by upstream. Rig cycles are expensive, so put **both** in one DTB; if it passes, bisect
only if the attribution matters. If CJ withholds SMC-write approval, Rank 2 alone is still a
worthwhile single-variable boot.

## Rank 3 (latent bug, **not** this morning's cause): **`pcie0` and the DARTs have no `power-domains`.**

Ours: none. Upstream: `power-domains = <&ps_apcie_sys_gp>` on `pcie0` and on every
`pcie0_dart_*` (`t6030.dtsi:1116`, `:1204,1214,1224,1232`); t602x uses `ps_apcie_gp_sys`,
t8122 `ps_apcie_gp`. **READ-FROM-SOURCE.**

Why it is not the cause: `pcie-apple` is a `device_initcall`-level platform driver, so probe (and
both `link didn't come up` messages, at 0.249 s and 0.457 s) happen **before** genpd's
`late_initcall` sweep that powers off unclaimed domains. m1n1 left all eight gates active. So the
domains were on at training time. **INFERENCE**, well supported by the dmesg timestamps.

Why it still matters: the eight `ps_apcie_*`/`ps_ans` controllers exist in the booted DTB
(`power-controller@100/108/110/370/380/388/390/398`, **MEASURED-FROM-DTB**) with **no consumer**, so
after `late_initcall` genpd is free to gate PCIe off underneath us. Add the domain reference once the
link trains. Fix: `power-domains = <&ps_apcie_sys_gp>;` on `pcie0` and both DARTs.

## Rank 4 (defer): the ticket-180 m1n1 port-reset values (`port+0x130`, `port+0x13c`).

The prior static review's paired-Apple comparison is sound work, but it is a **m1n1 binary change**
and an **attended** run, versus two DT properties for Rank 1+2. Also, `apple_pcie_setup_link()`
reached `PORT_STATUS_READY` on both ports (see §6), which is the port core saying it is happy — the
failure is downstream of the port core. **Do not spend a rig cycle on 180 before Rank 1+2.**
⚠ 180 involves hardware writes to `port+0x130`/`port+0x13c`.

## Rank 5 (refuted as a cause): `no iommu-map translation for id 0x0 / 0x8`.

Expected and harmless. See §7. Not a hypothesis.

## Not hypotheses (checked and eliminated here)

- **A missing WiFi PMGR power domain.** There is none. All eight apcie gates are generic (§3).
- **A WiFi pwren under `apcie0`.** There is none anywhere in the `apcie0` subtree (§1/§2). The rail
  is switched from the top-level `/amfm` node.
- **ADT timing not honoured.** It is honoured, with the right units (§4).
- **A second timing property we missed.** There are exactly two, on the bridges only (§4).

---

# 2. Deliverable 1 — every `function-*` on `/arm-io/apcie0` and all descendants, decoded

**MEASURED-FROM-ADT** (both ADT captures identical). Phandles resolved to paths by walking
`AAPL,phandle` over the whole tree.

| ADT path | property | phandle → node | 4CC | args |
|---|---|---|---|---|
| `/arm-io/apcie0` | `function-debug_gpio` | 248 → `/arm-io/gpio0` | `GPIO` | `0x4d, 0x101` |
| `/arm-io/apcie0/pci-bridge0` | `function-clkreq` | 248 → `/arm-io/gpio0` | `GPIO` | `0x0, 0x2` |
| `/arm-io/apcie0/pci-bridge0` | `function-perst` | 248 → `/arm-io/gpio0` | `GPIO` | `0x4, 0x0` |
| `/arm-io/apcie0/pci-bridge0` | `function-dart_force_active` | 92 → `/arm-io/dart-apcie0` | `Fact` | — |
| `/arm-io/apcie0/pci-bridge0` | `function-dart_request_sid` | 92 → `/arm-io/dart-apcie0` | `SReq` | — |
| `/arm-io/apcie0/pci-bridge0` | `function-dart_release_sid` | 92 → `/arm-io/dart-apcie0` | `SRel` | — |
| `/arm-io/apcie0/pci-bridge0` | `function-dart_self` | 92 → `/arm-io/dart-apcie0` | `Self` | — |
| `/arm-io/apcie0/pci-bridge0/wlan` | *(none)* | — | — | — |
| `/arm-io/apcie0/pci-bridge0/bluetooth-pcie` | *(none)* | — | — | — |
| `/arm-io/apcie0/pci-bridge1` | `function-clkreq` | 248 → `/arm-io/gpio0` | `GPIO` | `0x1, 0x2` |
| `/arm-io/apcie0/pci-bridge1` | `function-perst` | 248 → `/arm-io/gpio0` | `GPIO` | `0x5, 0x0` |
| `/arm-io/apcie0/pci-bridge1` | `function-dart_force_active` | 97 → `/arm-io/dart-apcie1` | `Fact` | — |
| `/arm-io/apcie0/pci-bridge1` | `function-dart_request_sid` | 97 → `/arm-io/dart-apcie1` | `SReq` | — |
| `/arm-io/apcie0/pci-bridge1` | `function-dart_release_sid` | 97 → `/arm-io/dart-apcie1` | `SRel` | — |
| `/arm-io/apcie0/pci-bridge1` | `function-dart_self` | 97 → `/arm-io/dart-apcie1` | `Self` | — |
| `/arm-io/apcie0/pci-bridge1/pcie-sdreader` | `function-pcie_port_control_sd` | 86 → `/arm-io/apcie0` | `PrtC` | `0x5a` |
| `/arm-io/apcie0/pci-bridge1/pcie-sdreader` | `function-sd_pwr_en` | 294 → `/arm-io/smc/iop-smc-nub/smc-pmu` | `pKW4` | `'gP19', 0x0` |

That is the **complete** list. There are only two `pci-bridgeN` nodes (`pci-bridge0`, `pci-bridge1`)
even though `#ports = 4`; ports 2 and 3 are unpopulated and have no ADT bridge node.

Notes:

- `PrtC` args are **bridge phandles**, not port indices: `0x5a` = 90 = `pci-bridge1`; `0x57` = 87 =
  `pci-bridge0`. **MEASURED-FROM-ADT** (`AAPL,phandle` of those nodes).
- `/pcie-sdreader-helper` (top-level, outside `apcie0`) carries **duplicates** of both SD functions:
  `function-pcie_port_control_sd = 86:PrtC(0x5a)` and `function-sd_pwr_en = 294:pKW4('gP19',0x0)`.
- **`pci-bridge0` and `pci-bridge1` both carry `manual-enable` and `manual-enable-s2r`** (empty
  boolean properties). Neither m1n1 nor Linux reads them (`grep` over `m1n1/src`, `m1n1/proxyclient`,
  `linux/drivers` → no hits, **MEASURED**). **INFERENCE:** they mean iBoot does not bring these ports
  up; the OS does. That is consistent with the endpoint rails being *off* at handoff, which is what
  Rank 1 predicts.

Other non-`function-*` properties of interest on the bridges, **MEASURED-FROM-ADT**:

| | `pci-bridge0` | `pci-bridge1` |
|---|---|---|
| `apcie-port` | 0 | 1 |
| `maximum-link-speed` | 2 | 1 |
| `t-refclk-to-perst` | 100 | 100 |
| `perst-to-config` | 100 | 100 |
| `msi-vector-base` / `#msi-vectors` | 0 / 8 | 8 / 8 |
| `apcie-piodma` / `apcie-piodma-sid` | 96 / 17 | 100 / 17 |
| `default-apcie-options` | `0x80f00001` | `0x80100000` |
| `pci-l1pm-control` | `0x4055190f` | *(absent)* |
| `manual-enable`, `manual-enable-s2r`, `built-in` | present | present |
| tunable sets | `apcie-config` (24), `pcie-rc` (72), `pcie-rc-gen3-shadow` (72), `pcie-rc-gen4-shadow` (72) | same shapes |

`default-apcie-options` and `pci-l1pm-control` are **not decoded** — I did not find a consumer in
m1n1 or Linux and did not disassemble the paired driver for them. Recorded, not interpreted.

---

# 3. Deliverable 2 — the WiFi/BT power path

**FOUND.** It is not under `apcie0` at all; it is the top-level `/amfm` node.
**MEASURED-FROM-ADT**, both captures:

```
/amfm
  device_type = amfm
  AAPL,phandle = 44
  default-options = 4
  function-pcie_port_control = 86:PrtC(0x57)                 -> /arm-io/apcie0, bridge phandle 87 = pci-bridge0
  function-reg_on          = 294:pKW4('gP13', 0x800000)      -> /arm-io/smc/iop-smc-nub/smc-pmu
```

and the WiFi device node explicitly delegates to it:

```
/arm-io/wlan
  device_type = wlan
  module-instance = mriya
  amfm-managed-port-control                (empty boolean -> port control lives on /amfm)
  function-sac = 475:SACC('lcd0','lcd1')
  local-mac-address = 842f57339ed7
  wifi-antenna-sku-info = [0x1, 0x3358]
  wifi-calibration-msf = <blob>
  interrupt-parent = 248 (/arm-io/gpio0), interrupts = [39, 2]
```

So: **`/amfm function-reg_on` = SMC PMU key `gP13` = the BCM4388 module's WL_REG_ON/rail enable, and
`/amfm function-pcie_port_control` points at `pci-bridge0`.** The two halves of "power the module,
then enable the port" are both on `/amfm`, which is why `pci-bridge0` itself has no `pwren` — the
attribution in the milestone doc and in the earlier static review ("no pwren for bridge0, so the rail
must be always-on or enabled elsewhere") is now resolved: **elsewhere = `/amfm`.**

Exhaustive search evidence (all **MEASURED-FROM-ADT**):

- Every `function-*` property in the **whole** ADT was dumped and phandle-resolved. The only
  `pKW4` SMC-key writes anywhere are:
  `/amfm function-reg_on ('gP13', 0x800000)`,
  `/arm-io/apcie0/pci-bridge1/pcie-sdreader function-sd_pwr_en ('gP19', 0x0)`,
  `/pcie-sdreader-helper function-sd_pwr_en ('gP19', 0x0)`,
  `/arm-io/dockchannel-mtp/mtp-transport/multi-touch function-afe-reset ('gp1c', 0x10000)`,
  `/arm-io/dockchannel-mtp/mtp-transport/stm function-stm-reset ('gp1d', 0x10000)`,
  `/arm-io/dp2hdmi-gpio0 function-reset ('gP10', 0x10000)` / `dp2hdmi_pwr_en ('gP1a', 0x0)` /
  `hdmi_pwr_en ('gP0f', 0x800000)`,
  `/arm-io/aop-spmi0/stockholm-spmi/stockholm function-enable ('gp0e', 0x800000)`,
  `/arm-io/pmgr function-toggle_vdd_cio ('pmVC', 0x0)`.
  **`gP13` is the only one that is WiFi-related.**
- Nodes matching `wlan|wifi|bcm|brcm|mriya|bluetooth`:
  `/arm-io/apcie0/pci-bridge0/wlan` (`compatible = wlan-pcie,bcm4387, wlan-pcie,bcm`),
  `/arm-io/apcie0/pci-bridge0/bluetooth-pcie` (same compatible),
  `/arm-io/dart-apcie0/mapper-apcie0-wlan`, `/arm-io/wlan`,
  `/arm-io/bluetooth` (`bluetooth,n88`, `vendor-id 1452`, `product-id 4768`, `bootstrap-delay 100`,
  `function-bootstrap_lock = LOCK()`), `/arm-io/aop-spmi0/spmi-wifibt`.
  **None of these carries a power-enable operation.** `/arm-io/aop-spmi0/spmi-wifibt` has only
  `reg`/`interrupt-parent`/`AAPL,phandle` — no `function-*`, so it is an SPMI slave descriptor, not a
  switch we can actuate.
- No PMGR power domain named for wlan/wifi exists (§3 below).

The ADT arg `0x800000` on `gP13` is **not decoded**. `gpio-macsmc.c` ignores the ADT arg entirely and
writes `CMD_OUTPUT | value` = `0x01000001` (`gpio-macsmc.c:186-196`) — **READ-FROM-SOURCE**. I could
not calibrate the arg's meaning: the other `0x800000` users (`gP0f` HDMI, `gp0e` stockholm) map to
different pin numbers on different upstream machines, so there is no clean two-point fit. I tried
that comparison and it does not close; recording the value without interpreting it.

Minor note, **MEASURED-FROM-ADT**: the ADT calls the module `wlan-pcie,bcm4387` while our DT declares
`pci14e4,4434` (BCM4388, same as upstream `t8122-jxxx.dtsi:60`). The ADT string is Apple's family
name; the real PCI ID is only readable once the link trains. Not blocking. Also, the ADT carries the
real MACs (`842f57339ed7` wlan, `842f572eb188` bluetooth) while our DT has zeros — cosmetic, and m1n1
normally patches these at handoff.

---

# 4. Deliverable 3 — the PMGR angle

`/arm-io/apcie0` has `clock-gates = [240, 162, 244, 163, 242, 164, 243, 245]` and
`power-gates = [240, 162, 244, 163, 242, 164, 243, 245]` — **identical lists**.
**MEASURED-FROM-ADT.**

Resolved against `/arm-io/pmgr` `devices[]` by `id2` (the same field `pmgr_find_device()` matches,
`m1n1/src/pmgr.c:150-240`):

| # | ADT id | PMGR device NAME | ps offset | parents | matches our DTS label |
|---|---|---|---|---|---|
| 0 | 240 | `ANS` | `0x370` | `FAB3_SOC` | `ps_ans` (`t6040-pmgr.dtsi:615`) |
| 1 | 162 | `APCIE_GP` | `0x100` | — | `ps_apcie_gp` (`:47`) |
| 2 | 244 | `APCIE_SYS_GP` | `0x390` | `FAB3_SOC` | `ps_apcie_sys_gp` (`:651`) |
| 3 | 163 | `APCIE_ST0` | `0x108` | — | `ps_apcie_st0` (`:55`) |
| 4 | 242 | `APCIE_SYS_ST0` | `0x380` | `ANS` | `ps_apcie_sys_st0` (`:633`) |
| 5 | 164 | `APCIE_ST1` | `0x110` | — | `ps_apcie_st1` (`:63`) |
| 6 | 243 | `APCIE_SYS_ST1` | `0x388` | `ANS` | `ps_apcie_sys_st1` (`:642`) |
| 7 | 245 | `APCIE_PHY_SW` | `0x398` | `APCIE_SYS_ST0` | `ps_apcie_phy_sw` (`:660`) |

Offsets are a **1:1 match** with `arch/arm64/boot/dts/apple/t6040-pmgr.dtsi`
(`power-controller@100/108/110/370/380/388/390/398`) — **READ-FROM-SOURCE**. Our PMGR description is
correct. (`t6040-pmgr.dtsi` also declares the parent links: `ps_apcie_sys_st0` →
`<&ps_ans>, <&ps_apcie_st0>`, `ps_apcie_phy_sw` → `<&ps_apcie_sys_st0>, <&ps_apcie_sys_st1>`,
matching the ADT parent fields.)

**Answer to the question asked: none of the eight is WiFi-specific or port-specific.** The pairs are
`ST0`/`ST1` (two "stacks", not two ports) plus `GP` (general-purpose) plus the shared `PHY_SW` and
`ANS` fabric. A full scan of `pmgr.devices[]` for `pcie|apcie|wlan|wifi` found **no** WLAN domain at
all — the only other PCIe-named devices are the Thunderbolt ones
(`ATC0..3_PCIE`, `ATC0..3_CIO_PCIE`, all `on=0`) and the virtual
`APCIE-SYS-GX-V`/`APCIE-SYS-STX-V`/`AUSB[0-3]-AONPCIE-V`. **MEASURED-FROM-ADT.**

Conclusion: **there is nothing in PMGR that could be the WiFi rail.** The rail is off-SoC, behind the
PMU, reachable only via SMC `gP13`. This closes the "check whether a PMU rail or an always-on domain
does it" branch of ticket 179.

Cross-check against our `dts/t6040.dtsi`: it references `ps_ans` (lines 345, 355, 369, 371) and
`ps_apcie_phy_sw` (line 369, for NVMe's `apcie0` domain), and the PCIe node itself references
**none** — see Rank 3.

---

# 5. Deliverable 4 — timing properties, and what Linux actually does

**Exhaustive ADT search** for property names matching `^t-|-to-|delay` over the entire tree, both
captures. On the PCIe side the result is **exactly two properties, per bridge, and nothing else**:

```
/arm-io/apcie0/pci-bridge0  t-refclk-to-perst = 100
/arm-io/apcie0/pci-bridge0  perst-to-config   = 100
/arm-io/apcie0/pci-bridge1  t-refclk-to-perst = 100
/arm-io/apcie0/pci-bridge1  perst-to-config   = 100
```

(the only other hits anywhere are `mesa power-on-delay/power-off-delay`, three `gl9755-sdr104-delayN`
tuning values on the SD reader, `bluetooth bootstrap-delay = 100`, `dwi str-delay`,
`spmi-abbeyL1 upo-shutdown-delay`, and two unrelated `*-to-*` blobs). **MEASURED-FROM-ADT.**

What `pcie-apple` does, `drivers/pci/controller/pcie-apple.c`, **READ-FROM-SOURCE**:

`apple_pcie_setup_link()` — declared at **:557**:

| line | operation |
|---|---|
| :574 | `devm_fwnode_gpiod_get(np, "reset", GPIOD_OUT_HIGH)` — PERST# |
| :580-591 | up to 3 auxiliary `reset-gpios` (index 1..3) |
| :595-602 | `devm_fwnode_gpiod_get(np, "pwren", GPIOD_ASIS)`; **`-ENOENT` → `pwren = NULL`** |
| :604 | `rmw_set(PORT_APPCLK_EN, port->base + PORT_APPCLK)` (`PORT_APPCLK = 0x800`, `:106`) |
| :607-609 | assert PERST# |
| **:612** | **`gpiod_set_value_cansleep(pwren, 1)` — power the endpoint** |
| :614 | `apple_pcie_setup_refclk()` (`:508`) — PHY `REFCLK0REQ`/`ACK`, `REFCLK1REQ`/`ACK`, `REFCLKEN`; on t602x `hw->port_refclk == 0` so `PORT_REFCLK` is skipped |
| **:622-625** | **`if (pwren) msleep(100); else usleep_range(100, 200);`** |
| :628 | `rmw_set(PORT_PERST_OFF, port->base + hw->port_perst)` — `PORT_T602X_PERST = 0x82c` (`:137`) |
| :629-631 | deassert PERST# (and aux) |
| **:634** | **`msleep(100)`** — "Wait for 100ms after PERST# deassertion (PCIe r5.0, 6.6.1)" |
| :636-641 | poll `PORT_STATUS`(`0x804`) for `PORT_STATUS_READY`(BIT 0), 100 µs interval, **250 ms** timeout; on failure `"port %pOF ready wait timeout"` |

then in `apple_pcie_setup_port()` (`:644`): `:699-704` clear `PORT_REFCLK_CGDIS`/set
`PHY_LANE_CFG_REFCLKCGEN` and clear `PORT_APPCLK_CGDIS`; `:706` IRQ setup; `:711-719` RID2SID
autodetect; `:727` register IRQs; **`:729-743` read `PORT_LINKSTS`(`0x208`), and if
`!PORT_LINKSTS_UP` write `PORT_LTSSMCTL_START` and wait `link_up_timeout` ms** (module param,
default **500**, `:36-38`) for the completion, else `"%pOF link didn't come up"`.

**Does the driver honour the ADT values, and in what units?**

- `t-refclk-to-perst = 100` → **microseconds**. Linux's no-pwren path is `usleep_range(100, 200)`
  at `:625`, commented "The minimal Tperst-clk value is 100us (PCIe CEM r5.0, 2.9.2)". Numerically
  and semantically identical. **INFERENCE** on the unit (the ADT carries no unit), but the match of
  both the value and the spec minimum makes it near-certain.
- `perst-to-config = 100` → **milliseconds**. Linux's `msleep(100)` at `:634`, commented
  "PCIe r5.0, 6.6.1". Again identical. **INFERENCE** on the unit, same reasoning.
- So **yes, on t602x/t6040 the driver already implements the ADT timing shape**, with no
  t602x-specific deviation. Priority 2 of ticket 179 is **closed as a non-issue**.
- The one place the driver differs is *deliberately conservative*: with `pwren` present it waits
  `msleep(100)` (Tpvperl) instead of 100 µs before deasserting PERST#. So adding `pwren-gpios`
  changes the timing too — in the direction the endpoint needs after a cold power-on.

Corroboration from the boot log (**MEASURED** from `pcie-v1-linux-console-20260729.log`): host-bridge
ranges printed at `0.042730`, port 0 warning at `0.249226` (Δ ≈ 206 ms), port 1 warning at
`0.457225` (Δ ≈ 208 ms). That is `~100 µs + 100 ms (post-PERST) + ~100 ms` — **not** the extra
`msleep(100)` a `pwren` would add. Independent confirmation that `pwren == NULL` on both ports.

---

# 6. Deliverable 5 — diff against machines where this works

Reference: **`t6030` + `t603x-j514-j516.dtsi`** (MacBook Pro 14"/16" M3 Pro/Max — the direct
predecessor of J614s, same 4-port t602x-shaped APCIE, same BCM4388 family, same
`gP13`/`gP19` SMC indices). Cross-checked against `t602x-die0.dtsi` + `t602x-j474-j475.dtsi` and
`t8122.dtsi` + `t8122-jxxx.dtsi`. All **READ-FROM-SOURCE**.

## Controller node

| property | ours (`dts/t6040-j614s-dcuart-pcie.dts`) | t6030 | t602x | t8122 |
|---|---|---|---|---|
| `compatible` | `apple,t6040-pcie`,`apple,t6020-pcie` | ✔ | ✔ | ✔ |
| `device_type`, `reg`, `reg-names` | ✔ (10 entries, ADT-correct — see below) | ✔ | ✔ | ✔ |
| `interrupt-parent`, `interrupts` ×4 | ✔ (1723/1732/1741/1750) | ✔ | ✔ | ✔ |
| `msi-controller`, `msi-parent`, `msi-ranges` | ✔ (AIC 2071, 32) | ✔ | ✔ | ✔ |
| `iommu-map`, `iommu-map-mask` | ✔ (2 entries, mask `0xff00`) | ✔ (4 entries) | ✔ | ✔ |
| `bus-range` | `<0 8>` | `<0 4>` | `<0 4>` | `<0 4>` |
| `ranges`, `#address-cells`, `#size-cells` | ✔ | ✔ | ✔ | ✔ |
| `pinctrl-0`, `pinctrl-names` | ✔ (but **function 2** — Rank 2) | ✔ (function 1) | ✔ (1) | ✔ (1) |
| **`power-domains`** | **ABSENT** | `<&ps_apcie_sys_gp>` | `<&ps_apcie_gp_sys>` | `<&ps_apcie_gp>` |
| `dma-coherent` | absent | absent | present (`t602x-die0.dtsi:1075`) | absent |

`bus-range = <0 8>` is **ADT-correct**: `/arm-io/apcie0 bus-range = 0x800000000` = the u32 pair
`(0, 8)` — **MEASURED-FROM-ADT**. Not a defect.

`reg` is **ADT-correct**. `/arm-io/apcie0` has **35** entries = 7 header + 4 ports × 7
(**MEASURED-FROM-ADT**). Applying the `/arm-io` `ranges` delta `+0x200000000`
(`done/2026-07-27-t6040-adt-ranges-address-correction.md`): rc `0x214000000`→`0x414000000`,
port0 core `0x210028000`→`0x410028000` (size `0x8000`), phy0 `0x217020000`→`0x417020000`,
port1 `0x411028000`, port2 `0x412028000`, port3 `0x413028000`, phy1/2/3
`0x417024000`/`0x417028000`/`0x41702c000`, ECAM `0x1cb0000000`/`0x10000000` (high window, no delta).
Every one matches our DT exactly.

## Port nodes — **this is where the answer is**

| property | ours `port00` | t603x `port00` (base + board) |
|---|---|---|
| `device_type`, `reg`, `#address-cells`, `#size-cells`, `ranges` | ✔ | ✔ |
| `interrupt-controller`, `#interrupt-cells`, `interrupt-map-mask`, `interrupt-map` | ✔ | ✔ |
| `reset-gpios` | `<&pinctrl_ap 4 GPIO_ACTIVE_LOW>` | `<&pinctrl_ap 167 …>` (per-SoC pin) |
| `bus-range` | `<1 1>` | `<1 1>` |
| **`pwren-gpios`** | **ABSENT** | **`<&smc_gpio 19 GPIO_ACTIVE_HIGH>`** ← |
| `max-link-speed` | `<2>` (from ADT `maximum-link-speed`) | not set |
| children `wifi@0,0` / `bluetooth@0,1` | ✔ (`pci14e4,4434`, `pci14e4,5f72`, `brcm,board-type="apple,mriya"`) | ✔ |

| property | ours `port01` | t603x `port01` |
|---|---|---|
| `reset-gpios` | `<&pinctrl_ap 5 GPIO_ACTIVE_LOW>` | `<&pinctrl_ap 168 …>` |
| `bus-range` | `<2 2>` | `<2 2>` |
| **`pwren-gpios`** | **ABSENT** | **`<&smc_gpio 25 GPIO_ACTIVE_HIGH>`** ← |
| child `mmc@0,0` | ✔ (`pci17a0,9755`, `cd-inverted`, `wp-inverted`) | ✔ |

## DART nodes

| | ours | t6030 |
|---|---|---|
| `compatible` | `apple,t8110-dart` | `apple,t6030-dart`,`apple,t8110-dart` |
| `reg`, `interrupts`, `#iommu-cells` | ✔ | ✔ |
| **`power-domains`** | **ABSENT** | `<&ps_apcie_sys_gp>` |

## Every property the working machine has that we lack

1. **`pwren-gpios` on `port00`** — `<&smc_gpio 19 GPIO_ACTIVE_HIGH>` (SMC key `gP13`). ← Rank 1
2. **`pwren-gpios` on `port01`** — `<&smc_gpio 25 GPIO_ACTIVE_HIGH>` (SMC key `gP19`). ← Rank 1
3. **`smc_gpio` provider** — no `apple,smc-gpio` node anywhere in the PCIe DTB. `dts/t6040.dtsi:471`
   declares `smc` with **no children at all**. The stale `dts/t6040-j614s-dcuart-smc.dts` does have
   an `smc_gpio` child, but on a second, colliding `smc:` label at a superseded address.
   **MEASURED-FROM-DTB**: decompiling `t6040-j614s-dcuart-pcie.dtb` finds **zero** matches for
   `pwren`, **zero** for `smc`/`mbox` in the SMC range, and exactly **one** `gpio-controller` (the
   `pinctrl_ap`). Same for `t6040-j614s-dcuart-pcie-clkreqfix.dtb`.
4. **`power-domains` on `pcie0`** — `<&ps_apcie_sys_gp>`. ← Rank 3
5. **`power-domains` on both DARTs** — `<&ps_apcie_sys_gp>`. ← Rank 3
6. **`dma-coherent`** — only `t602x-die0.dtsi` has it; t6030 and t8122 do not, so not required.

Things we have that upstream does not (all benign): `max-link-speed` on the ports (ADT-derived),
`brcm,board-type = "apple,mriya"` (board-correct), `bus-range = <0 8>` (ADT-correct), two ports
declared `status = "disabled"` (correct — the ADT has no bridge nodes for ports 2/3, and
`for_each_available_child_of_node()` at `pcie-apple.c:961` skips them).

Also checked: **`apple,t6040-pcie` is not in the driver's match table** (`pcie-apple.c:993`: only
`apple,t6020-pcie`, `apple,pcie`, plus `apple,t6020-pcie-ge` via `t602x-pcie-ge.dtsi`). Our second
compatible string `apple,t6020-pcie` matches `t602x_hw` (`:175`), which is what we want:
`port_perst = 0x82c`, `port_rid2sid = 0x3000`, `port_msimap = 0x3800`, `port_refclk = 0`,
`phy_lane_ctl = 0`, `max_rid2sid = 512`. **READ-FROM-SOURCE.** Nothing t6040-specific is missing
from the driver.

Yuka's `t8140-pcie` branch: **not re-checked here.** The prior static review reports no extra
endpoint-power or post-LTSSM step on head `a7857af8`; I did not independently verify that and am not
claiming it.

---

# 7. The `no iommu-map translation for id 0x0 / 0x8` messages

**Expected and harmless. Our `iommu-map` is correct. Do not change it.**

- Severity: it is **`pr_info`**, not an error — `drivers/of/base.c:2215`,
  `pr_info("%pOF: no %s translation for id 0x%x on %pOF\n", …)`. **READ-FROM-SOURCE.**
- Ordering: in the console log both `link didn't come up` lines (0.249226, 0.457225) precede the
  first `no iommu-map translation` (0.457453). The messages are emitted while *enumerating the root
  ports*, after training already failed. They cannot be a cause. **MEASURED** from the log.
- Do the RIDs fall in the mapped ranges? **No, by design.** With
  `iommu-map = <0x100 &pcie0_dart_0 1 1>, <0x200 &pcie0_dart_1 1 1>` and
  `iommu-map-mask = <0xff00>`:
  - RID `0x0` = `00:00.0`, the root port itself. `0x0 & 0xff00 = 0x0`, which is in neither
    `[0x100,0x101)` nor `[0x200,0x201)`.
  - RID `0x8` = `00:01.0` (dev 1 → `1<<3`), the second root port. `0x8 & 0xff00 = 0x0`. Same.
  - The mapped IDs are `0x100` (bus 1 → the BCM4388 behind port 0) and `0x200` (bus 2 → the SD
    reader behind port 1), which is exactly right given our `bus-range = <1 1>` / `<2 2>`.
  Root ports live on bus 0, do not DMA, and are intentionally left untranslated.
- Upstream is **structurally identical**: `t6030.dtsi:1103-1107` and `t602x-die0.dtsi:1061-1065` use
  the same `<0x100 …>, <0x200 …>, …` + `iommu-map-mask = <0xff00>` with root ports on bus 0.
  A working M3 Pro emits the same two `pr_info` lines. **INFERENCE**, strongly supported by the
  identical DT shape and the `pr_info` call site.

Ticket 179's priority 3 is **closed as a non-issue.**

---

# 8. Additional confirmation: where in the sequence we actually die

**MEASURED** from `pcie-v1-linux-console-20260729.log`: the log contains **no**
`"port … ready wait timeout"` line. Combined with `pcie-apple.c:636-641`, that means
`PORT_STATUS_READY` (bit 0 of `port+0x804`) was set within 250 ms on **both** ports — the port core
completed refclk bring-up and PERST deassertion successfully. `apple_pcie_setup_refclk()` also
returned 0 (it would otherwise abort `setup_link` with an error and fail the probe, and we would not
see `link didn't come up` at all), so the PHY `REFCLK0/1 REQ→ACK` handshake worked.

We then reach `:729-743`: `PORT_LINKSTS_UP` is clear, `PORT_LTSSMCTL_START` is written, and the
link-up completion never fires within `link_up_timeout`.

**INFERENCE:** the root complex side is healthy and LTSSM was started; what is missing is a
responding partner at the other end of the link. That is precisely the signature of an endpoint whose
supply rail was never switched on (Rank 1), and secondarily of a reference clock the endpoint cannot
request (Rank 2). It is *not* the signature of a mis-programmed port-core reset value, which would be
expected to fail earlier, at the `PORT_STATUS_READY` poll.

---

# 9. Concrete next step (offline work only; nothing here has been run)

A single DT variant carrying both top-ranked fixes, based on the **macsmc** variant so the proven SMC
stack is present:

1. base the PCIe variant on `dts/t6040-j614s-dcuart-macsmc.dts` (or add `&smc {status="okay"}` /
   `&smc_mbox {status="okay"}` to the PCIe variant) — uses `dts/t6040.dtsi:457/471`, smc
   `0x50c600000`, sram `0x50de70000`, the combination confirmed working in commit `023c164`;
2. add to that `smc` node: `smc_gpio: gpio { compatible = "apple,smc-gpio"; gpio-controller;
   #gpio-cells = <2>; };`
3. `&port00 { pwren-gpios = <&smc_gpio 19 GPIO_ACTIVE_HIGH>; };`
4. `&port01 { pwren-gpios = <&smc_gpio 25 GPIO_ACTIVE_HIGH>; };`
5. change `pcie_pins` to `<APPLE_PINMUX(0,1)>, <APPLE_PINMUX(1,1)>` (= `0x10000`, `0x10001`) —
   already built by the concurrent session as `t6040-j614s-dcuart-pcie-clkreqfix.dtb`;
6. build the kernel with **`CONFIG_GPIO_MACSMC=y`** (not `=m`);
7. optionally, in the same DTB, `power-domains = <&ps_apcie_sys_gp>` on `pcie0` and both DARTs
   (Rank 3 — prevents genpd gating PCIe off after `late_initcall`).

**Gates before this can run:** CJ's explicit approval for the two new SMC key writes (`gP13`,
`gP19`, 4-byte, value `0x01000001`, via `gpio-macsmc`), plus the standing rules — attended session,
fresh power cycle, exactly one `pcie_init()` per power cycle. V1
(`m1n1-t6040-pcie-V1-upstream-04e8829c.bin`) stays the loader; V2 must not be run; ticket 180's m1n1
change should wait until after this DT-only attempt.

**PASS** = `DLL_LINK_ACTIVE=1` on port 0 and a `pci14e4,44xx` endpoint on bus 1.
A partial pass (port 0 up, port 1 still down, or vice versa) is still informative and would isolate
which of the two SMC keys matters.

---

# 10. Independent convergence with the concurrent session

This decode was done blind to the concurrent rig session's in-flight work. Checking `git status` at
the end (read-only) shows that session **independently reached and already implemented Rank 1 and
Rank 2**, from the same ADT evidence:

- `dts/t6040.dtsi` (uncommitted): adds the `smc_gpio: gpio { compatible = "apple,smc-gpio"; … }`
  child, with a comment citing `/amfm function-reg_on = pKW4('gP13', 0x800000)` and
  `pcie-sdreader function-sd_pwr_en = pKW4('gP19', 0x0)`, and the same `gP%02x` → line-number
  derivation.
- `dts/t6040-j614s-dcuart-wifi.dts` (new, uncommitted):
  `pwren-gpios = <&smc_gpio 0x13 GPIO_ACTIVE_HIGH>` on the WiFi port and
  `<&smc_gpio 0x19 GPIO_ACTIVE_HIGH>` on the SD port. (`0x13` = 19, `0x19` = 25 — same lines.)
- `dts/t6040-j614s-dcuart-pcie.dts` (uncommitted): `pcie_pins` corrected to
  `APPLE_PINMUX(0,1)`/`APPLE_PINMUX(1,1)`, with the same conclusion that the ADT's
  `GPIO(pin, 0x2)` second word is a **flags field**, not a function select.

Two things that session adds beyond this report, worth recording:

- **Live ground truth for Rank 2**: they read the pinctrl register at `0x51c000000 + 4*pin` and got
  `0x00076a21`; `REG_GPIOx_PERIPH = GENMASK(6,5)` extracts `(0x76a21 >> 5) & 3 = 1`, i.e. iBoot
  leaves these pins at **periph 1**. That upgrades Rank 2 from "upstream-unanimous inference" to
  measured — our function-2 value was actively *changing* the pins away from what iBoot set.

Two things this report adds that their change does **not** cover:

- **Rank 3 is still open**: neither `pcie0` nor the two DARTs has gained `power-domains`. Latent, not
  a training blocker, but it should land before this configuration is trusted past `late_initcall`.
- **`CONFIG_GPIO_MACSMC` must be `=y`, not `=m`.** `config-macsmc-wifi-fw` and
  `config-macsmc-hid-type-fix-nbcon-wifi-fw` both have `=m`; a module that is never loaded turns
  `apple_pcie_probe_port()`'s pwren lookup into permanent probe deferral and would lose the
  root-port enumeration we already have. Only `config-wifi-fw` has `=y`.
