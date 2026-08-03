# Cross-cutting correction: adt.py `.reg` is untranslated; add 0x200000000 in the arm-io low window

## The bug in my address reporting

Several addresses I reported this session from `m1n1/proxyclient` `adt.py` `.reg` were **0x200000000
too low**. The `/arm-io` node carries a `ranges` translation:

```
bus_addr=0x0  parent=0x200000000  size=0x480000000   (delta +0x200000000)
bus_addr>=0x800000000 ...                            (delta 0)
```

So any child register in the bus window `[0, 0x480000000)` maps to a CPU-physical address by **adding
0x200000000**. `adt.py` `.reg` returns the raw *bus* address and does not apply the parent `ranges`, so
every address I quoted in that window needs +0x200000000. Addresses at/above `0x800000000` are
unaffected (delta 0).

## Doubly confirmed against known-good values

- **USB:** `adt.py` gave `usb-drd2 = 0x192280000`; +0x200000000 = **`0x392280000`**, which is exactly the
  address in the working `t6040.dtsi` `usb_drd2` node (and the xHCI base the 2026-07-21 smoke logged).
- **PCIe:** last night I read `apcie0 reg[2] = 0x217000000` from `adt.py` and separately saw the tunables
  trace log `0x417000000`. I could not explain the `0x200000000` gap and speculated a "die alias" (AIC
  "1/2 dies"). **That was wrong.** It is this `ranges` delta. The trace was right all along.

## Corrected absolute addresses

PCIe (ticket 124) — the trace values were correct; the ADT-derived ones I published were low:

| what | wrong (published) | correct |
|---|---|---|
| PhyCommon[0] | `0x217004000` | **`0x417004000`** |
| PhyPhy base | `0x217008000` | **`0x417008000`** |
| op-115 PLL poll | `0x217048090` | **`0x417040090`** |

USB right-port CPU-physical (ticket 170), = raw ADT + 0x200000000:

| node | CPU-physical base |
|---|---|
| `usb-drd2` (dwc3) | `0x392280000` |
| `atc-phy2` | `0x393000000` |
| `dart-usb2` | `0x392f00000` + `0x392f80000` |

## Lesson

Twice now a `0x200000000` discrepancy cost analysis time (the PCIe "die alias" dead end last night, and
a near-miss on the USB DT addresses tonight). The rule going forward: **`adt.py` `.reg` values in the
arm-io low window are bus addresses; add the `ranges` delta (0x200000000 here) for CPU-physical.** The
working `t6040.dtsi` addresses are the cross-check — they already bake in the translation.

## Update: rule confirmed on four nodes, and feature addresses extracted

The `+0x200000000` translation is now cross-checked against our DT **and** m1n1's own boot log:

| node | adt.py bus | +0x200000000 | cross-check |
|---|---|---|---|
| `usb-drd2` | `0x192280000` | `0x392280000` | = `t6040.dtsi` usb_drd2 |
| `uart0` | `0x229200000` | `0x429200000` | = `t6040.dtsi` serial0 |
| `aic` | `0x302400000` | `0x502400000` | = m1n1 log "AIC Version 3 @ 0x502400000" |
| `dockchannel-uart` | `0x308828000` | `0x508828000` | = m1n1 log "dockchannel UART at 0x508828000" |

So it is a plain `ranges` translation, solid. Feature-kernel node addresses (CPU-physical), for
tickets 164/165:

| node | compatible (ADT) | CPU-physical |
|---|---|---|
| `smc` (RTKit mailbox) | `iop,ascwrap-v6` | `0x50c600000` (+ sram `0x50c050000`) |
| `dwi` (backlight) | `dwi,t8101` | `0x5029b0000` (irq 273) |
| `smc-gpio0` | `gpio,t8101` | `0x50c824000` |

Template the Linux `smc@50c600000` node on `t602x-die0.dtsi`'s `smc@2a2400000`
(`apple,tXXXX-smc`, `apple,t8103-smc`, `apple,smc` + gpio/hwmon/reboot/rtc children + an RTKit
mailbox), substituting these addresses. `t6040` genuinely differs from t6030's `smc@36c400000` —
that is a real per-SoC difference, not a translation error.
