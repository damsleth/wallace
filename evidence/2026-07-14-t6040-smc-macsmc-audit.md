# T6040 J614s SMC / macsmc audit — power button, lid, battery/charger (2026-07-14)

Ticket 036 (offline, P1, SMC track). Using the ticket-028 RTKit 26.x map, audits
the J614s SMC path: mailbox/endpoint, compatibles, and `macsmc` MFD + subdriver
coverage for power button, lid, and battery/charger **status**. Draft,
evidence-backed DT/compat deltas only. No SPMI/PMU/charger writes; SMC MMIO
addresses are deferred to the ADT, never invented. Static; no rig, no MMIO.

## Headline

SMC needs **no 26.x-specific driver change** — the blockers are a missing DT node
and one missing input subdriver, not firmware/version incompatibility:

- SMC is an RTKit endpoint (0x20) on the `macsmc` core (`drivers/mfd/macsmc.c`,
  `compatible = "apple,smc"`). Per ticket 028 the RTKit management protocol is
  ≤ 12 on 26.x (proven by ANS), so the SMC endpoint comes up on the unchanged
  `apple-rtkit` core. The SMC key protocol (`READ_KEY`/`GET_KEY_INFO`/
  `NOTIFICATION`, msg ids 0x10–0x20) is version-independent, and the
  power/lid/battery keys are stable across generations. So no SMC 26.x compat
  patch is required.
- What's missing on J614s is (1) an SMC **DT node** (there is none in
  `t6040.dtsi`/`t6040-j614s*`), so nothing probes, and (2) the **macsmc-input**
  subdriver (power button / lid), which is absent from this tree.

## macsmc stack coverage (this tree)

| MFD cell | Function | Driver in tree? | Notes |
|---|---|---|---|
| `macsmc` core | RTKit SMC transport, key R/W, notifications | ✓ `drivers/mfd/macsmc.c` | `apple,smc`; endpoint 0x20 |
| `macsmc-power` | battery / charger **status** (power_supply) | ✓ `drivers/power/supply/macsmc*` | read-only SMC keys |
| `macsmc-hwmon` | temp/voltage/current sensors | ✓ `drivers/hwmon/macsmc*` | `apple,smc-hwmon` |
| `macsmc-rtc` | RTC | ✓ `drivers/rtc/rtc-macsmc*` | `apple,smc-rtc` + `rtc_offset` nvmem |
| `macsmc-reboot` | reboot / boot-stage nvmem | ✓ `drivers/power/reset/macsmc*` | `apple,smc-reboot` |
| `macsmc-gpio` | SMC GPIOs | ✓ `drivers/gpio/gpio-macsmc*` | `apple,smc-gpio` |
| **`macsmc-input`** | **power button (KEY_POWER), lid (SW_LID)** | **✗ absent** | the one driver gap |

So battery/charger status, sensors, RTC, reboot and SMC GPIOs are all covered by
in-tree subdrivers the moment the DT node exists; **only power button + lid**
need the missing `macsmc-input` (downstream linux-asahi driver).

## DT delta (draft) — add the J614s SMC node

There is no SMC node in the J614s DT. Shape is templated from the closest
mainline sibling, t602x (M2 Pro/Max, `t602x-die0.dtsi`), which the T6040 arm-io
layout follows; the macsmc core + subnode compatibles are identical across
generations. **The reg/IRQ addresses below are placeholders — they must be read
from the live J614s ADT `/arm-io/smc` (a read-only proxy dump), not carried over
from t602x** (the T6040 arm-io base differs; a wrong SMC MMIO base would SError):

```dts
smc_mbox: mbox@<ADT> {
    compatible = "apple,t6040-asc-mailbox", "apple,asc-mailbox-v4";
    reg = <…ADT…>;                 /* /arm-io/smc mailbox */
    interrupt-parent = <&aic>;
    interrupts = <…ADT: send/recv empty/not-empty…>;
    interrupt-names = "send-empty","send-not-empty","recv-empty","recv-not-empty";
    #mbox-cells = <0>;
};
smc: smc@<ADT> {
    compatible = "apple,t6040-smc", "apple,t8103-smc";
    reg = <…ADT smc…>, <…ADT sram…>;
    reg-names = "smc", "sram";
    mboxes = <&smc_mbox>;
    smc_gpio: gpio   { compatible = "apple,smc-gpio"; gpio-controller; #gpio-cells = <2>; };
    smc_reboot: reboot { compatible = "apple,smc-reboot";
        nvmem-cells = <&shutdown_flag>,<&boot_stage>,<&boot_error_count>,<&panic_count>;
        nvmem-cell-names = "shutdown_flag","boot_stage","boot_error_count","panic_count"; };
    rtc { compatible = "apple,smc-rtc"; nvmem-cells = <&rtc_offset>; nvmem-cell-names = "rtc_offset"; };
};
```

`macsmc-power`, `macsmc-hwmon` and `macsmc-input` are instantiated by the MFD by
name (no OF subnode needed), so this node is sufficient for battery/charger,
sensors, and — once the driver exists — power button/lid. The `nvmem-cells`
(`rtc_offset`, `shutdown_flag`, `boot_stage`, …) reference SMC-GPIO/nvram cells
that also need J614s ADT confirmation.

## Evidence-backed deltas (ranked)

1. **Add the J614s SMC DT node** (above) — unblocks macsmc + battery/charger,
   hwmon, rtc, reboot, gpio in one step. Blocked only on a read-only ADT dump of
   `/arm-io/smc` (mailbox reg, sram reg, four ASC IRQs) — no writes.
2. **Enable/port `macsmc-input`** (power button KEY_POWER, lid SW_LID) — the only
   missing subdriver; it's downstream in linux-asahi. `[UPSTREAM]`: confirm it
   builds against this tree's macsmc core (the notification chain
   `blocking_notifier_call_chain(&smc->event_handlers, …)` it hooks is present).
3. **No SMC 26.x compat patch needed** (per ticket 028) — record this so effort
   isn't spent looking for one.

## Safety boundary (respected)

- **Status only.** Battery gauge and charger state are read via SMC keys
  (`macsmc-power`, read-only). Charger *control* keys and any charge-limit writes
  are out of scope and not proposed.
- **No PMU / SPMI writes.** SMC-PMU-backed GPIOs are forbidden: the trackpad
  audit already found `gp1c` resolving through `/arm-io/smc/iop-smc-nub/smc-pmu`
  (`done/2026-07-12-t6040-trackpad-firmware.md`); this audit touches none of that.
- `macsmc-reboot` writes only its own boot-stage/shutdown nvmem keys (standard
  reboot path), not PMU/charger — noted, not exercised here.

## Open (needs the rig, read-only)

Confirm from the J614s ADT `/arm-io/smc`: the mailbox reg + four ASC IRQ numbers,
the smc + sram reg windows, and the SMC-nvram cell offsets for the reboot/rtc
subnodes. All read-only; then the DT node above is fillable and macsmc probes.
