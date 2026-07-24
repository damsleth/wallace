# T6040 ticket 068 PCIe clkgen/op-115 result (2026-07-24)

Result: **negative; PLL locks, PHY-IP read still hangs**. Do not retry
unchanged.

The exact independently reviewed candidate ran once. It applied the existing
live-proven T6040 PCIe prefix, then:

```text
pcie: T6040 clkgen PLL enable (clkgen=0x415044000)
pcie: T6040 clkgen PLL locked
pcie: Enabling T6040 PHY clock gate after PLL/clkgen tunables
pcie: T6040 PHY clock gate enabled
```

The common PHY then reached the same successful clock/reset boundary as the
earlier diagnostic:

```text
pcie: T6040 100 MHz reference clock available
pcie: T6040 PHY 0 CLK0 acknowledged
pcie: T6040 PHY 0 CLK1 acknowledged
pcie: T6040 PHY 0 reset released
```

The last target output was the pre-read description:

```text
tunable: apcie-phy-ip-pll-tunables[0] read-only addr=0x417040090 size=4 mask=0x1 value=0x1
```

No value, `op-115 ... complete`, SError text, or Linux output followed.
`linux.py` timed out awaiting the `kboot_boot` proxy reply. Thus the two exact
`_configPciePLLs` clkgen operations are valid and sufficient to obtain lock,
but they are not sufficient to make the T6040 PHY-IP `reg[3]` aperture
readable.

A normal DebugUSB reboot immediately restored a quiescent `Running proxy`.
Evidence hashes:

- `dcuart-chainload.log`:
  `d9a6245e366e3ba50bffc8accf4f1d912af180326fd2b2e7cb721dcc54a295c4`
- `dcuart-boot.log`:
  `4eba0d5c4555f80c913482f4123eee4d02a2a04cc5ed9c3fbf23f14ddf35ec52`
- empty `dcuart-console.log`:
  `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`

The next step is static paired-driver tracing for an additional pre-`reg[3]`
gate/reset/domain operation. Do not guess offsets, add another write, or
repeat the read until a new exact precondition is independently grounded.
