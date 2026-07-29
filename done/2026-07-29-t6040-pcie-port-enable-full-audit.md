# T6040 PCIe port-enable audit: app-clock policy is missing from m1n1

No rig action was performed. This is a paired-driver decode, ADT check, and
offline build following the V1 result where both T6040 root ports enumerate
but neither endpoint link trains.

## Pinned inputs

```text
paired AppleT6040PCIe kext
  04dbbfcf7e2b2a43bc49132ca02942491e8b672bcf204986a51d0c726d96dff9
captured J614s ADT
  2fe477c613c67e44550ded1bbb6cad9cf4fffc62393b47b39edc6c11281df4ba
proven V1 m1n1 baseline
  source 04e8829cbc47ff6a05e872dd329cdabb83554ce0
  binary 28a4e0cf812d48ab40337be9578381d66c61b5ac91730bb0b950930f77a93299
```

The paired entry point is
`ApplePCIEBaseT8132Port::enablePortHardware()` at
`0xfffffe0009b397d0`. `AppleT6040PCIePort` inherits this method; its one
relevant port-enable override is `_setExpectedLinkWidth()`.

## Complete hardware-shaping order

Resolving the PAC vtable calls gives this condensed order:

1. `_resetPortHardware()`;
2. apply the bridge's `apcie-config-tunables`;
3. `setPortEnable(true)`, an RMW setting bit 0 at port `+0x800`;
4. `_setRootPortPerst(false)`, an RMW setting bit 0 at port `+0x82c`;
5. poll port `+0x804` bit 0 for RUN;
6. `initializeRefclkBuffer()`;
7. `_setAppclkAutoDis([this+0xc35])`;
8. `_initializeRootComplex()`;
9. write per-port Intr2AXI `+0x80 = 1`;
10. set the T6040 expected width, then counter/debug setup.

The earlier ticket-180 review covered item 1 and found the two fixed reset
value differences at port `+0x13c` and `+0x130`. Extending the comparison
through the whole port-enable method found three additional differences.

### 1. App-clock auto-disable — strongest new link-training lead

`[this+0xc35]` is initialized from the presence of the bridge ADT property
`appclk-auto-dis`. Paired `_setAppclkAutoDis(bool)` at
`0xfffffe0009b3b280` then RMWs exactly bit 8 at port `+0x800`: set when the
property exists, clear when absent.

Neither live J614s bridge has that property:

```text
/arm-io/apcie0/pci-bridge0  appclk-auto-dis ABSENT
/arm-io/apcie0/pci-bridge1  appclk-auto-dis ABSENT
```

Therefore paired macOS clears bit 8 on both ports. m1n1 writes the reset
constant `0x00100100`, sets bit 0 to enable the port, and never performs the
property policy; its final value retains auto-disable as `0x00100101`.

This is a direct semantic clock-retention difference immediately before root
complex setup. It is a stronger physical-link hypothesis than the opaque
reset constants, and it can be tested with one ADT-gated RMW.

### 2. Port-PHY settle delay — real but lower confidence

Paired `initializeRefclkBuffer()` at `0xfffffe0009b39634` performs the same
port-PHY bit sequence as m1n1:

- set bit 0, poll bit 2;
- set bit 1, poll bit 3;
- clear bit 4;
- set bits 9 and 10.

However, paired macOS inserts `IODelay(1)` after clearing bit 4 and before
setting bits 9/10. m1n1 has no delay there. This is an exact timing delta, but
one microsecond is a lower-confidence explanation than leaving a named clock
auto-disable policy in the wrong state. It was not mixed into the app-clock
candidate.

### 3. Intr2AXI enable — exact omission, unlikely to train the PHY

Paired `enablePortHardware()` calls `writeIntr2AxiReg(0x80, 1)` after root
complex setup. The accessor at `0xfffffe0009b40a88` writes through the
port's mapped Intr2AXI base. The captured ADT gives:

```text
port 0 Intr2AXI  0x410024000
port 1 Intr2AXI  0x411024000
```

m1n1 already parses those ADT entries, but writes `Intr2AXI+0x80=1` only for
T602x/T6031 and skips T8132/T6040. This is paired behavior that should
eventually be fixed. Its placement and name make it interrupt plumbing,
though, so it is not the next physical-link experiment.

## Bounded app-clock candidate

Source:

```text
worktree  /Users/damsleth/Code/m1n1-pcie-port-appclk
branch    codex/t6040-pcie-port-appclk
parent    04e8829cbc47ff6a05e872dd329cdabb83554ce0
commit    f62ed1338b6bce0d2faac18ac505594454aebef3
```

The change:

- is gated on the existing `APCIE_T8132` type;
- reads the current bridge's already-resolved ADT node;
- sets or clears only `APCIE_PORT_APPCLK_AUTO_DIS` (`BIT(8)`) at the existing
  ADT-derived port `+0x800` aperture;
- runs after the port RUN poll, matching paired ordering;
- adds no address or access to SPMI, SMC, PMU, charger, NVRAM, or firmware.

The linked binary contains the `appclk-auto-dis` property string and the
expected `adt_getprop` branch followed by either `orr #0x100` or
`bic #0x100`. Two clean builds were byte-identical:

```text
/Users/damsleth/Code/linux-build-out/t6040-pcie-appclk-f62ed133/m1n1.bin
size    1,097,728 bytes
sha256  482839cdbeb920ff2ed26c1478924288b16606056d853f65ffea6aeaf3a09388
tag     f62ed133
```

Ticket 182 pins that artifact. It is proposed only. Because this is still a
PCIe-port MMIO write, it requires Claude's exact-artifact review, CJ's
approval and presence, a fresh power cycle, and exactly one `pcie_init()`.

Run-order recommendation: ticket 182 before ticket 180. The app-clock
candidate changes one named, property-controlled policy with a direct
clock-retention interpretation. If it is negative, ticket 180 remains the
separate fixed-reset-value hypothesis; the one-microsecond delay and
Intr2AXI enable remain later isolated deltas. Do not combine them into an
unattributable first retry.
