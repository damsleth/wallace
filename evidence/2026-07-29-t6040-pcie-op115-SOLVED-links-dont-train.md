# MILESTONE: the T6040 PCIe op-115 wall is GONE. Linux enumerates the root ports; links don't train yet

Attended session (CJ present, rollback loader enrolled so KIS gives a real proxy). **The two-week
op-115 blocker is solved, and it was the wrong PHY reset bit — nothing else.** WiFi is not up: the
remaining blocker is narrower and precisely located.

## Result 1 — `pcie_init()` completes on T6040 for the first time

V1 (`m1n1-t6040-pcie-V1-upstream-04e8829c.bin`, `28a4e0cf…` = upstream's PCIe path wholesale) was
chainloaded over KIS, then PCIe was triggered **on demand** via the proxy `P_PCIE_INIT` command
(`p.pcie_init()`) — no kernel payload needed, which is far better control than ticket 068 had:

```text
pcie: Initializing t6040 PCIe controller
pcie: ADT uses 7 reg entries per port
pcie: No common tunables
pcie: Initializing port 0        pcie: Port 0 max speed = 2
pcie: Initializing port 1        pcie: Port 1 max speed = 2
pcie: Initialized controller 0
pcie_init returned: 0
```

Previously this hung forever at the first PHY-IP access (`reg[3]+0x90`). **V1's hypothesis is
confirmed: the wrong PHY reset bit (BIT(7) instead of BIT(4)) was the *entire* cause.** Our
ticket-058 clkgen PLL sequence and delta D1 were **not** preconditions — V2 was never needed.
Transcript: `linux-build-out/pcie-v1-20260729.log` (`d5355c07…`).

## Result 2 — Linux boots with PCIe in the DT and the apple-pcie driver comes up

Because `pcie_init()` is also called from `kboot.c`, the hang had been blocking **any** Linux boot
carrying PCIe. With V1 as the loader, `Image-pcie` + `t6040-j614s-dcuart-pcie.dtb` booted to a
BusyBox shell, and:

```text
pcie-apple 1cb0000000.pcie: host bridge /soc/pcie@1cb0000000 ranges:
pcie-apple 1cb0000000.pcie:      MEM 0x0bc0000000..0x0bdfffffff -> 0x0bc0000000
pcie-apple 1cb0000000.pcie: ECAM at [mem 0x1cb0000000-0x1cbfffffff] for [bus 00-08]
pci 0000:00:00.0: [106b:100c] type 01 class 0x060400 PCIe Root Port
pci 0000:00:01.0: [106b:100c] type 01 class 0x060400 PCIe Root Port
pcieport 0000:00:00.0: PME: Signaling with IRQ 52 / AER: enabled with IRQ 52
pcieport 0000:00:01.0: PME: Signaling with IRQ 54 / AER: enabled with IRQ 54
```

`/sys/bus/pci/devices/` = `0000:00:00.0  0000:00:01.0`. Transcript:
`linux-build-out/pcie-v1-linux-console-20260729.log` (`77a1fdc5…`).

## The remaining blocker, precisely: link training

```text
pcie-apple 1cb0000000.pcie: /soc/pcie@1cb0000000/pci@0,0 link didn't come up
pcie-apple 1cb0000000.pcie: /soc/pcie@1cb0000000/pci@1,0 link didn't come up
```

Independently confirmed from m1n1 by reading the root ports' PCIe capability over the proxy
(ADT-derived ECAM `0x1cb0000000`, read-only):

| port | LnkCap | LnkSta | DLL_LINK_ACTIVE |
|---|---|---|---|
| 00:00.0 | `0x00737812` (max gen2, x1) | `0x1011` | **0** |
| 00:01.0 | `0x00737812` (max gen2, x1) | `0x1011` | **0** |

So no endpoint has trained: no BCM4388 (`pci14e4,4434`), no SD reader. Note m1n1's own Apple-specific
port checks (`APCIE_PORT_STATUS_RUN`, `LINKSTS`) passed silently — they are **not** equivalent to
`DLL_LINK_ACTIVE`, so "Initialized controller 0" must not be read as "link up".

## What I ruled out (so nobody repeats it)

- **PERST pin numbers are correct.** ADT: `pci-bridge0 function-perst = GPIO(0x4, 0x0)`,
  `pci-bridge1 = GPIO(0x5, 0x0)`; our DT has `reset-gpios = <&pinctrl_ap 4>` and `5`. Match.
- **CLKREQ pinmux is present and applied.** ADT: `function-clkreq = GPIO(0x0, 0x2)` / `GPIO(0x1, 0x2)`;
  our DT already has `pcie-pins { pinmux = <0x20000 0x20001>; }` (pin 0/1, function 2) referenced by
  the pcie node's `pinctrl-0`. `APPLE_PINMUX(pin,func) = pin | func<<16`, so these are exactly right.
- **The pinctrl/GPIO driver is present and bound** — `CONFIG_PINCTRL_APPLE_GPIO=y`, device
  `51c000000.pinctrl` exists. (`/sys/class/gpio` is absent only because `GPIO_SYSFS` is off; not
  meaningful.)
- **The DT reg layout is right** — 10 shared entries: ECAM, rc, 4× port core, 4× port PHY, matching
  the t602x shape.
- **No PCIe-related errors in dmesg** beyond the two link messages. The `pms_fpwm0-4` PMGR failures
  and the HID `hw start failed` lines are pre-existing and unrelated (fan PWM domains, trackpad).
- **Double-init is not the cause of no-link** — m1n1 alone, on a virgin boot, also shows
  `DLL_LINK_ACTIVE=0`.

## One real hazard found: pcie_init must not run twice per power cycle

The first Linux attempt died with a **synchronous data abort**, `ESR 0x96000410`,
`FAR 0x41705a000` = port 2's PHY-IP window (`0x417058000 + 0x2000`), `x22 = 0x417040000`
(phy_ip base), then `Unhandled exception, rebooting`. Cause: I had already run `pcie_init()` from the
proxy, and `kboot` then ran it again in the same power cycle on already-initialised hardware. The
retry from a clean boot, with that single variable changed, booted fine. **Rule: one `pcie_init()`
per power cycle.** (The `pcie_initialized` static guards it *within* one m1n1 instance, not across a
chainload.) Recovery was a normal DebugUSB reboot; nothing was damaged.

## Next hypotheses for link training, in priority order

1. **Endpoint power.** The ADT gives `pci-bridge1` a `function-sd_pwr_en = 294:pKW4('gP19', 0x0)` —
   the SD reader's power-enable is an **SMC key write**, which we do not perform, so port 1 almost
   certainly cannot train by design. `pci-bridge0` (WiFi) has **no** `pwren` in the ADT, so WiFi's
   rail is enabled some other way — identify it. Note any SMC key write is a **new** SMC write beyond
   the permitted `smc_reboot`/`smc_rtc` and needs decode + explicit approval.
2. **`t-refclk-to-perst = 100` / `perst-to-config = 100`** timing properties exist per bridge in the
   ADT; check whether pcie-apple honours an equivalent delay on t602x/t6040 and whether 100 µs/ms is
   being met.
3. **`no iommu-map translation for id 0x0 / 0x8`** appears in dmesg. The DT has `iommu-map` on the
   controller but Linux reports no translation for the port RIDs — worth resolving, though it should
   not prevent link training.
4. Compare against yuka's `t8140-pcie` branch (head `a7857af8`) and upstream's t8132 port bring-up
   for anything M4-specific after LTSSM start.

## Status of the candidates

- **V1 is the keeper** and should become our PCIe baseline; our fork's `19edc72b` D1/D2 patch is now
  only a decode record. **V2 (`3916bf15…`) is unnecessary** — do not run it; the clkgen sequence it
  adds is not a precondition.
- Ticket 175's offline goal is met. Ticket 124's op-115 question is **answered and closed**.
- WiFi (168) is no longer PCIe-init-blocked; it is link-training-blocked.
