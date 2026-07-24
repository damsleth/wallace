# T6040 ATC PHY paired-kext bank map

Date: 2026-07-24

Ticket: 023

Scope: host-only static analysis; no rig, proxy, MMIO, SPMI, PMU, charger,
target-memory, storage-device, or Boot Policy access

## Result

The paired 25F84 kernelcache closes the previous “unnamed 44-bank ATC PHY”
static blocker. Its dedicated `AppleT6040TypeCPhy` kext carries a
`_sRegisters[44][8]` physical-range table. For all four J614s ATC PHY nodes:

| ADT node | kext profile | Exact ranges matched |
|---|---:|---:|
| `/arm-io/atc-phy0` | 0 | 44/44 |
| `/arm-io/atc-phy1` | 1 | 44/44 |
| `/arm-io/atc-phy2` | 2 | 44/44 |
| `/arm-io/atc-phy3` | 3 | 44/44 |

The range order also matches exactly: kext bank index N is ADT `reg[N]`. No
address, offset, compatible alias, or cross-generation layout was guessed.

The same kext's `applyTunables` implementation proves the T6040 record format:
each 12-byte record is little-endian `<encoded, mask, value>`, where
`encoded[31:27]` is the bank index and signed `encoded[26:0]` is the byte
offset. The driver rejects bank 31 and above, bounds-checks `offset + 4`, then
performs a 32-bit masked read/modify/write.

The exact right-port host-mode property decodes to:

```text
tunable_USB2PHY_HOST[0]
bank 4 = ADT reg[4]
base 0x393000800
offset 0x8
address 0x393000808
mask 0x00007003
value 0x00000003
```

`tunable_USB2PHY_DFLT` has the same mask and value. Device mode instead uses
value `0x00007003`. Therefore replaying only the host property is not a useful
new discriminator: it is byte-identical to the default state and does not
supply HPM attach/role/orientation, repeater control, or downstream VBUS.

## Sources and reproducibility

| Item | Size | SHA-256 |
|---|---:|---|
| paired kernelcache IM4P | 31,827,787 | `4cc018b4ab925d879a0f039bf1f83cdbd11dc0bd906910afd1f9d15befabad1b` |
| decompressed arm64e fileset | 119,209,984 | `ed556fe62efc2c229f3d4c7ebbbcd21fd5c8d099fbb4d9b5ae636dd78b61d3f6` |
| extracted `AppleT6040TypeCPhy` kext | 480,520 | `d0a766201c15bb01b8eeaf6617c91707562ae0c50511ebfccbd9d918acd499f3` |
| captured J614s ADT | 606,208 | `7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84` |
| `scripts/t6040-atcphy-kext-map.py` | — | `a19e06a29d9b73674456b9d3b99400ae8a491c86644cdb49bcd16fa14662fcfb` |
| right-port TSV output | 13,625 | `1d60d039f3049ea2e6319258a8d9a3acc5d0c2b980f23af5227de35a624c79a5` |
| right-port JSON output | 42,933 | `b8de40ed71421c6b065feecbbfbba45ae897d6b51386ba2a65f187e90f7270a5` |

The Apple binaries, captured ADT, and generated maps remain host-local. They
are not committed.

Extraction:

```sh
pyimg4 im4p extract \
  -i /private/tmp/t6040-paired-fw-25F84/raw/kernelcache.release.mac16j.im4p \
  -o /private/tmp/t6040-kernelcache-25F84.raw

ipsw kernel extract /private/tmp/t6040-kernelcache-25F84.raw \
  com.apple.driver.AppleT6040TypeCPhy --imports --force \
  -o /private/tmp/t6040-usb-kexts-25F84
```

Reproduce the right-port map:

```sh
scripts/t6040-atcphy-kext-map.py \
  /private/tmp/t6040-usb-kexts-25F84/com.apple.driver.AppleT6040TypeCPhy \
  /Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.adt \
  > /private/tmp/t6040-atcphy-map.tsv
```

The tool is pinned to the exact extracted-kext SHA and the
`AppleT6040TypeCPhy::_sRegisters` symbol at VA `0xfffffe000c778920` / file
offset `0x500c8`. It refuses any other kext, non-T6040 node, non-44-range ADT,
or non-unique profile match. It emits the five out-of-range tail records that
Apple's own bounds check skips rather than silently treating them as valid.
For `atc-phy2`, 164 of 169 raw T6040 tunable records map in range.

## What this changes

The T6040 Linux resource table no longer needs to wait for an upstream author
to publish bank offsets: the exact paired Apple driver and exact target ADT
jointly prove all 44 bank identities and the raw tunable encoding. A reviewable
driver can initially use stable numeric bank IDs (`reg0` through `reg43`) and
add semantic aliases as individual Apple methods are decoded.

The kext also exposes symbolized `eusb2phy_init`, `initUSB2`,
`aciophy_phy_init`, and per-mode tunable methods. Static disassembly shows the
USB2 initialization sequence uses the already mapped bank objects rather than
an unseen address source. Decoding that direct sequence into a minimal,
reviewable implementation is now bounded work.

## What remains blocked

This does **not** authorize a live PHY write. The bus-powered stick still needs
the physical Type-C path, and the same paired fileset shows:

- `AppleSPMIController` with generation-specific handlers through Gen4;
- `AppleHPMARMSPMI` for `usbc,sn201202x,spmi`;
- explicit HPM sleep/wake, status, role, orientation, VBUS, and repeater-reset
  state transitions.

Those paths mutate SPMI/HPM state and remain absolutely forbidden. The next
offline work is to decode the minimal read/status and ownership sequence, then
separate any unavoidable SPMI mutation from the now-proven ATC register map.
No live ticket should be proposed until an upstream-derived or byte-proven
sequence has exact addresses/values, rollback, independent review, and explicit
maintainer authorization. Repeating ticket 063 or applying only the
HOST-equals-DFLT record would not add evidence.
