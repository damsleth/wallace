# T6040 PCIe endpoint-power candidate: independent cross-review

Offline-only cross-review by **sol**, 2026-07-29. No rig contact, lease, SMC
transaction, or hardware write was made.

## Verdict

**NO-GO for a live run in its current form.**

The candidate has two strong and independently confirmed foundations:

1. the endpoint mapping is correct (`gP13` / GPIO line 19 for WiFi, `gP19` /
   line 25 for the SD reader); and
2. the PCIe CLKREQ pins should use Apple pinmux function 1, not function 2.

However, the report's load-bearing claim that the proposed Linux SMC-GPIO
writes are exactly what macOS performs is false. The paired Apple platform
function does not discard the second `pKW4` argument. For a one-element
template it copies the 32-bit ADT constant and replaces only its low 16 bits
with the runtime argument:

| operation | paired Apple `pKW4`, enable = 1 | Linux `gpio-macsmc`, value = 1 |
|---|---:|---:|
| `pKW4('gP13', 0x00800000)` | `gP13` &larr; `0x00800001` | `gP13` &larr; `0x01000001` |
| `pKW4('gP19', 0x00000000)` | `gP19` &larr; `0x00000001` | `gP19` &larr; `0x01000001` |

This mismatch is a **review blocker, not a finding that the upstream Linux
GPIO API is dangerous**. The generic Linux command is explicitly intended for
device power control and is already used on supported Apple systems. What is
not yet established is whether that generic action is equivalent to the
J614s-specific Apple/AMFM sequence at this point in the boot.

The standing project rule permits only `smc_reboot` and `smc_rtc` without a
new decision. These two writes therefore require an exact, explicitly approved
plan even after the semantics are resolved. CJ is AFK, so no such write should
run.

## Inputs

Paired 25F84 binaries extracted offline:

| binary | SHA-256 |
|---|---|
| `com.apple.driver.AppleBCMWLANBusInterfacePCIe` | `2f2855a5434859165360f55e254e9e50bb0e44244d6618f17be295b104383c8e` |
| `com.apple.driver.AppleOLYHAL` | `e2bbf6093af26e7b5b77f68d2ecb7156a821911d10d8eb3999b8493fe34f5996` |
| `com.apple.driver.AppleSMC` | `dba2d4fbe91c1578da800680cd36eb43a96f37a17beb7887f75a64be04cceee6` |
| DriverKit `com.apple.DriverKit-AppleBCMWLAN` | `84cf4fcf79f11078f8f9923abcdda8b272c831bd7b53d9d18a168831d43594e5` |

Other primary inputs:

- captured J614s ADT
  `linux-build-out/j614s-usb-port-map-20260721.adt`, SHA-256
  `7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84`;
- Linux `drivers/gpio/gpio-macsmc.c`;
- Linux `drivers/pci/controller/pcie-apple.c`;
- Linux `arch/arm64/boot/dts/apple/t603x-j514-j516.dtsi`;
- upstream commits `9b21051b0885` (SMC GPIO driver) and `096a93beca9f`
  (T603x J514/J516 PCIe power-enable GPIOs).

## Confirmed parts

### Endpoint identity and GPIO indices: PASS

The captured ADT contains:

```text
/amfm
  function-reg_on = 294:pKW4('gP13', 0x800000)
  function-pcie_port_control = 86:PrtC(87)

/arm-io/wlan
  amfm-managed-port-control

/arm-io/apcie0/pci-bridge1/pcie-sdreader
  function-sd_pwr_en = 294:pKW4('gP19', 0)
```

Phandle 294 resolves to
`/arm-io/smc/iop-smc-nub/smc-pmu`; phandle 87 is PCI bridge 0. The WLAN PCI
child is `wlan-pcie,bcm4387`.

`gpio-macsmc` converts a line number to `gP%02x`, so line `0x13` is 19 and
line `0x19` is 25. The direct T603x J514/J516 predecessor independently uses:

```dts
pwren-gpios = <&smc_gpio 19 GPIO_ACTIVE_HIGH>; /* WLAN */
pwren-gpios = <&smc_gpio 25 GPIO_ACTIVE_HIGH>; /* SD */
```

This is strong evidence for the identity and polarity of both logical
power-enable controls.

### CLKREQ pinmux function 1: PASS

In-tree Apple PCIe CLKREQ groups consistently use Apple pinmux function 1.
The ADT `GPIO(pin, 2)` second argument is a flags word, not a Linux pinmux
function selector. Changing pins 0 and 1 from function 2 to function 1 is
therefore a sound correction independent of the endpoint-power hypothesis.

### Linux driver behavior: PASS

`pcie-apple` obtains optional `pwren-gpios`, asserts it, waits 100 ms, and
only then deasserts PERST. `gpio-macsmc` maps a high output to a four-byte SMC
key write with:

```text
CMD_OUTPUT | 1 = 0x01000001
```

There is no ambiguity about what the proposed Linux artifact would write.

The SMC GPIO driver's upstream commit message also states that firmware owns
pin configuration and that the low command API is sufficient for device
power control. This supports the generic Linux operation as a deliberate
action API; it does not establish byte equivalence with every ADT platform
function template.

## Refuted exact-equivalence claim

`AppleSMCEmbeddedFunction::callFunction()` in the paired `AppleSMC` binary is
at `0xfffffe0009a1daec`. Its `pKW4` dispatch is the comparison against the
little-endian 4CC value `0x704b5734`.

For a one-element constant template, the relevant sequence is:

```asm
fffffe0009a1de28  ldr   w9, [x22, #0x40]
fffffe0009a1de2c  cmp   w9, #1
fffffe0009a1de34  ldr   x8, [x22, #0x30]
fffffe0009a1de38  ldr   w8, [x8]
fffffe0009a1de3c  stur  w8, [x29, #-0x58]
fffffe0009a1de40  ldr   w8, [x21]
fffffe0009a1de44  sturh w8, [x29, #-0x58]
...
fffffe0009a1de7c  mov   w4, #4
```

The 32-bit constant is copied first; `sturh` then replaces only the low 16
bits with the runtime argument, and the operation writes four bytes. Hence:

- `0x00800000` plus runtime `1` becomes `0x00800001`;
- `0x00000000` plus runtime `1` becomes `0x00000001`.

The statement that "`gpio-macsmc.c` ignores the ADT arg" describes the Linux
driver but cannot be used to infer that Apple ignores the argument. The
paired Apple implementation proves the opposite.

## J614s AMFM ownership is still incomplete

The paired WiFi stack does not simply expose an ordinary embedded platform
function on this machine:

- `AppleBCMWLANBusInterfacePCIe::deferredStart()` creates the OLYHAL platform
  function interface;
- `lowerWlanRegOn()` reaches its `setPowerEnable(false)` method;
- the paired DriverKit WLAN binary imports
  `AppleOLYHALPlatformFunction::setPowerEnableDK`;
- `AppleOLYHALPlatformFunction::withProvider()` checks
  `amfm-managed-port-control` and selects
  `AppleOLYHALPlatformFunctionEmbeddedAMFM`;
- `AppleOLYHALPlatformFunctionEmbeddedAMFM::setPowerEnable(bool)` at
  `0xfffffe00097ee7bc` logs the request, records a timestamp, returns zero,
  and performs no platform-function or SMC write itself.

The last function contains no call between its logging path and
`mach_continuous_time`/`absolutetime_to_nanoseconds`. This is consistent with
the ADT's explicit AMFM ownership: the actual rail/port sequencing actor is
elsewhere in the AMFM/DriverKit flow.

Therefore the static evidence has found the intended key and logical control,
but has **not** yet reproduced Apple's J614s ordering or established which
component issues the `pKW4` write.

## Safe next steps

1. Keep the CLKREQ function-1 correction.
2. Do not mark the current two-key WiFi+SD artifact reviewed or ready.
3. Continue the paired AMFM/DriverKit decode far enough to identify the actor,
   exact enable/disable values, and ordering relative to `PrtC`.
4. Compare against a paired T603x ADT if available. This can show whether the
   upstream predecessor also has nonzero `pKW4` template bits despite using
   generic `gpio-macsmc`.
5. If live observation is still needed, author a separate read-only ticket to
   inspect `gP13` direction/output state. Do not smuggle a write into that
   reader.
6. If a write is eventually justified and CJ approves it, test **WiFi
   `gP13` only** first. Do not also toggle the unrelated SD-reader `gP19`;
   a one-key artifact is smaller in scope and preserves attribution.

The failure mode under discussion is volatile endpoint power state and should
clear on a power cycle; there is no evidence of a persistent flash/OTP path.
That risk calibration does not waive the project's explicit SMC-write gate.
