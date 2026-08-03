# Tethered session: full ADT saved, SMC decoded, SRAM pattern-derived (172 → 165)

Caught the dual-mode 10 s proxy window (plain `macvdmtool reboot`, poll the gadget, connect to assert
DTR), fetched the ADT, then fell through to dwm. Read-only, no writes.

## Primary deliverable: the full live ADT is saved

`~/Code/linux-build-out/j614s-full-20260728.adt` (606,208 bytes, the complete `Fetching ADT (0x94000)`).
**All future address work — SMC, Type-C (170), anything — is now offline against this file; no more rig
needed for ADT reads.**

## SMC node — from the ADT (confirmed)

`/arm-io/smc`, compatible `iop,ascwrap-v6`:

| reg | bus | CPU-physical (+0x200000000) | size |
|---|---|---|---|
| [0] mailbox/ascwrap | `0x30c600000` | **`0x50c600000`** | `0x88000` |
| [1] | `0x30c050000` | `0x50c050000` | `0x4000` |
| [2] | `0x30c810000` | `0x50c810000` | `0x100` |

Mailbox IRQs (AIC): **997, 996, 999, 998**. Child `iop-smc-nub` (`iop-nub,rtbuddy-v2`, no own reg).

## SMC SRAM — pattern-derived, NOT in the ADT (flagged)

The Linux `apple,smc` node needs reg-names `smc`(0x4000) + `sram`(0x100000). The SRAM is **not** an ADT
reg here, and `/chosen/memory-map` is zeroed at this boot stage. But the SMC SRAM sits at a **constant
`smc_base + 0x1a00000`, size `0x100000`, across four SoC generations**:

| SoC | smc mailbox | sram | delta |
|---|---|---|---|
| t8103 | `0x23e400000` | `0x23fe00000` | `0x1a00000` |
| t600x | `0x290400000` | `0x291e00000` | `0x1a00000` |
| t602x | `0x2a2400000` | `0x2a3e00000` | `0x1a00000` |
| t6030 | `0x36c400000` | `0x36de00000` | `0x1a00000` |

So the **inferred t6040 SMC SRAM = `0x50c600000 + 0x1a00000` = `0x50e000000`, size `0x100000`.**

**Confidence: high (4-generation pattern), but flagged.** One yellow flag: the other SoCs' mailbox base
ends `...400000` while t6040's ends `...600000`; if the Asahi convention for those SoCs is *not*
"Linux smc@ = ADT ascwrap base", the reference point could differ. Failure mode if wrong is **safe**: a
mis-addressed SRAM makes the SMC driver fail at probe (no battery/thermals), not a fault or hardware
risk, and it's a one-address fix caught in the eventual smoke.

## 165 is now authorable (offline)

Full node set for the Linux `apple,smc`, templated on `t602x-die0.dtsi`:

```dts
smc_mbox: mbox@50c608000 {                    // smc_base + 0x8000
    compatible = "apple,t6040-asc-mailbox", "apple,asc-mailbox-v4";
    reg = <0x5 0x0c608000 0x0 0x4000>;
    interrupt-parent = <&aic>;
    interrupts = <AIC_IRQ 997 ...>, <996 ...>, <999 ...>, <998 ...>;   // order to verify vs t602x
    #mbox-cells = <0>;
};
smc: smc@50c600000 {
    compatible = "apple,t6040-smc", "apple,t8103-smc", "apple,smc";
    reg = <0x5 0x0c600000 0x0 0x4000>, <0x5 0x0e000000 0x0 0x100000>;  // sram pattern-inferred
    reg-names = "smc", "sram";
    mboxes = <&smc_mbox>;
    smc_gpio { compatible = "apple,smc-gpio"; ... };
    smc_hwmon { compatible = "apple,smc-hwmon"; ... };
    smc_reboot { compatible = "apple,smc-reboot"; ... };   // permitted write class
    smc_rtc { compatible = "apple,smc-rtc"; ... };
};
```

Enable `MFD_MACSMC` + `SENSORS_MACSMC_HWMON` + `RTC_DRV_MACSMC` (+ `HWMON`). Read-only telemetry;
charger/PMU-voltage writes stay forbidden. Fold into a feature kernel with usbnet (167).

Two small things still to pin, both offline against the saved ADT / t602x: the **mailbox IRQ order**
(4 lines — match t602x's convention) and whether the mailbox `reg` is `smc_base+0x8000` or one of the
ascwrap sub-regs. Neither blocks a first candidate.
