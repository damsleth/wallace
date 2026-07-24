# T6040 direct eUSB2 initialization sequence

Date: 2026-07-24

Ticket: 023

Scope: host-only static analysis of the paired 25F84
`AppleT6040TypeCPhy` kext. No rig, proxy, MMIO, SPMI, PMU, charger, target
memory, storage device, or Boot Policy access.

## Result

`AppleT6040TypeCPhy::eusb2phy_init(bool, bool)` is an 8,580-byte function at
VA `0xfffffe0009dbc5f8`, file offset `0x14248`. It uses only the mapped
objects for ATC register banks 0 and 1. The driver's `start()` mapping loop
stores one bank object every `0x20` bytes beginning at object offset `0x210`;
therefore the function's object offsets `0x210` and `0x230` are bank 0 and
bank 1, respectively. This agrees with the independently proved
`_sRegisters[44][8]` table and captured ADT order.

For the right-side port, `/arm-io/atc-phy2`, the complete direct-access
surface is:

| Bank | ADT range | Offsets used | Right-port addresses |
|---:|---:|---:|---:|
| 0 | `reg[0]` = `0x392a90000`/`0x4000` | `0x0`, `0x4`, `0x8`, `0x1c` | `0x392a90000`, `0x392a90004`, `0x392a90008`, `0x392a9001c` |
| 1 | `reg[1]` = `0x392800000`/`0x4000` | `0x0`, `0x20` | `0x392800000`, `0x392800020` |

No other bank is read or written by this function.

## Exact host control inputs

The private `initUSB2(unsigned int mode)` wrapper derives the two booleans
without an additional access:

```text
primary   = ((mode & 0x00060000) == 0x00020000)
secondary = ((mode >> 19) & 1)
eusb2phy_init(primary, secondary)
```

The paired `AppleT8150USBXHCI::start(IOService *)` proves the host caller
contract. Its Type-C PHY interface `open()` call passes:

```text
powerLevel = 2
options    = 0x00040000
timeoutMs  = 500
```

That selects `primary = false`, `secondary = false`, and final USB mode `2`.
Thus the host path is the five-write `primary=false` branch below; this label
is proved by the paired host-controller caller rather than inferred from the
register effects.

## Exact register sequence

Every mutation below is a 32-bit read/modify/write. `B0` and `B1` mean bank 0
and bank 1. The ordered sequence is:

1. Configure `B0+0x8`:
   - when `primary` is true: clear bits 14, 13, and 12 in three writes, then
     set bits 0, 1, 2, and 3 in four writes;
   - when `primary` is false: set bits 14, 13, 12, 0, and 1 in five writes.
2. Sleep 10 ms.
3. Clear bit 3 at `B0+0x4`.
4. Delay 10 microseconds.
5. Clear bit 0 at `B0+0x4`.
6. Clear bit 1 at `B0+0x4`.
7. Set bits 3 and 0 at `B1+0x0` (`old | 0x9`).
8. Set bit 2 at `B0+0x4`.
9. Clear bit 29 at `B0+0x1c`.
10. Clear bit 30 at `B0+0x1c`.
11. Delay 30 microseconds.
12. Read `B1+0x20`; a zero value is logged, but does not branch to a retry or
    failure return.
13. Sleep 5 ms.
14. At `B0+0x0`, replace bits 2:0 with zero when both booleans are true, or
    with `2` otherwise:

```text
new = (old & ~0x7) | ((primary && secondary) ? 0 : 2)
```

The embedded field names identify the bank-0 accesses as USB2 signal,
USB2-PHY control/misc tuning, and USB mode, and the bank-1 accesses as the
USB2 event block. Those names corroborate the function boundary; they do not
prove unrelated caller modes.

For the XHCI host path specifically, step 1 takes the second branch and step
14 writes mode `2`.

## Reproducibility

| Item | Size | SHA-256 |
|---|---:|---|
| extracted `AppleT6040TypeCPhy` kext | 480,520 | `d0a766201c15bb01b8eeaf6617c91707562ae0c50511ebfccbd9d918acd499f3` |
| exact `eusb2phy_init` bytes | 8,580 | `dbcb646331558971195222da3d360c4f61c66e714e344ffd5abde3102f7be29d` |
| quiet `ipsw` disassembly | 115,258 | `906c1f541d72f5675c35ea46fc2d4ee51178b660e9340aa2bba3b2ee96776552` |
| extracted `AppleSynopsysUSBXHCI` kext | — | `f8b96fabf19180125a1a545790e5d45bef96e9bbd28b7168fda536ed27383e44` |
| exact `AppleT8150USBXHCI::start` bytes | 7,788 | `1c57011198f21227eae3f8cdca6baebb8b59f4aed186dc29d2d821f207ed667e` |

The binary and disassembly remain host-local and are not committed. Recreate
the exact function bytes:

```sh
dd \
  if=/private/tmp/t6040-usb-kexts-25F84/com.apple.driver.AppleT6040TypeCPhy \
  of=/private/tmp/t6040-eusb2phy-init.bin \
  bs=1 skip=$((0x14248)) count=$((0x2184))
```

Recreate the readable disassembly:

```sh
ipsw macho disass --no-color -q -d \
  -s '__ZN18AppleT6040TypeCPhy13eusb2phy_initEbb' \
  /private/tmp/t6040-usb-kexts-25F84/com.apple.driver.AppleT6040TypeCPhy \
  > /private/tmp/t6040-eusb2phy-init.dis
```

The bank identities and right-port bases can be reproduced with
`scripts/t6040-atcphy-kext-map.py` as documented in
`done/2026-07-24-t6040-atcphy-kext-bank-map.md`.

The host call is at VA `0xfffffe000b02c784` in
`AppleT8150USBXHCI::start`, whose function begins at VA
`0xfffffe000b02c4a0` / file offset `0x1f0c0`. The four argument-building
instructions at file offset `0x1f3a4` encode `w2=0x40000`, `w3=0x1f4`, and
the authenticated virtual call; `w1=2` is immediately before them.

## Consequence for the bootable-stick experiment

The direct PHY half is no longer an unknown address/value surface. It is
small enough for an independently reviewed implementation, but it is not a
standalone live experiment:

- the function never provides Type-C attach, cable orientation, source role,
  VBUS, or external repeater ownership;
- the paired stack assigns those operations to
  `AppleHPMARMSPMI`/SN201202x over SPMI.

The stick is bus powered, so replaying this now-exact host function without
the HPM sequence cannot establish that the port will source power. It could
also conflict with firmware ownership. No live PHY or SPMI write is
authorized. The next safe work item is a static HPM state-machine decode which
identifies the ordering boundary and separates read-only status from
unavoidable mutation.
