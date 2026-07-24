# T6040 HPM/SPMI discovery boundary

Date: 2026-07-24

Ticket: 023

Scope: host-only static analysis of the captured J614s ADT and paired 25F84
`AppleHPM`/`AppleSPMI` kexts. No rig, proxy, MMIO, SPMI, PMU, charger,
target-memory, storage-device, or Boot Policy access.

Policy update later on 2026-07-24: the maintainer replaced the blanket SPMI
ban with `docs/SPMI_SAFETY.md`. This report's warning against replaying the
full Apple discovery path remains valid. Ticket 093 may instead test only the
separately hardened R0 selector plus one-byte logical `0x20` status read after
offline ticket 092 and exact review.

## Result

The right-side Type-C manager is not on an Apple SPMI Gen4 controller. The
captured target ADT explicitly has:

```text
/arm-io/nub-spmi-a1
  compatible = aapl,spmi
  gen = 3
  raw reg ranges =
    0x309198000 / 0x4000
    0x309194000 / 0x4000
    0x309190000 / 0x4000

/arm-io/nub-spmi-a1/hpm2
  compatible = usbc,sn201202x,spmi
  hpm-class-type = 10
  port-number = 3
  port-location = right
  port-type = 2
  rid = 2
  interrupts = 11, 17, 19
  interrupt-type = 0, 2, 3
  acio-parent = 196
```

References to Gen4 in earlier notes described handlers present in the paired
Apple driver, not the controller selected by this machine. The target
implementation boundary is Apple SPMI Gen3 plus the SN201202x class-10 HPM.

## Initial HPM read census

The paired `AppleHPMARMSPMI::publishHPMDevices()` is a 3,072-byte routine at
VA `0xfffffe0009529024`, file offset `0x463a4`. Its identity/classification
path invokes the class's `readRegs(address, buffer, length)` virtual method in
this order, branching to an error/class-selection path after each call:

| Order | HPM address | Length |
|---:|---:|---:|
| 1 | `0x0f` | 4 |
| 2 | `0x00` | 4 |
| 3 | `0x01` | 4 |
| 4 | `0x05` | `0x11` |
| 5 | `0x2c` | 1 |
| 6 | `0x2d` | `0x34` |

This is a useful bounded register census for future implementation review. It
does not make a live "read-only HPM probe" safe.

Before the census, a non-ready provider path calls a provider virtual method
with argument `2` and sleeps for 100 ms. The exact semantic name of that
provider transition is not yet proved. Read failures also take provider
recovery/state paths. Therefore `publishHPMDevices()` cannot be reduced to the
six reads or treated as observation-only.

## Why `readRegs()` is not a passive primitive

The exact four-argument
`AppleHPMARMSPMI::readRegs(unsigned char, unsigned char *,
unsigned long long)` implementation is 812 bytes at VA
`0xfffffe0009528464`, file offset `0x457e4`.

It:

- disables the HPM RTPC timer before the transfer;
- selects provider operation `0x02` or `0x12` from internal state;
- starts a provider transaction, polls a response tag for up to 1,000
  iterations with `IOSleep(1)` between iterations, and may perform a follow-up
  read at HPM address `0x1f`;
- uses a provider operation at `0x20` to fetch the requested payload; and
- invokes another HPM virtual operation on exit.

Those are driver/provider state transitions even when the requested HPM
payload is nominally read-only. A live replay would need the provider contract,
timer ownership, transaction tags, error recovery, and rollback. None is
authorized here.

## Sources and reproducibility

| Item | Size | SHA-256 |
|---|---:|---|
| captured J614s ADT | 606,208 | `7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84` |
| extracted `AppleHPM` kext | 836,032 | `b6eab85a4478fe354c29d4a274fa1ea23ced1c051e3b320fdfad54d65dce381d` |
| extracted `AppleSPMI` kext | 164,520 | `707edb5eb41bcf7252853f8fb24fb2a454e7923dc363294b8e18a6373c284878` |
| exact `AppleHPMARMSPMI::start` bytes | 1,816 | `b5b272d551ae3d4a283a50015a9c8c7d8edd6ed0709f7d215b9261cb0754f802` |
| exact four-argument `readRegs` bytes | 812 | `90763bfc20f68c519f077c7df9987c78a19bd98e02645f9522a2a2ef6a4d2cb6` |
| exact `publishHPMDevices` bytes | 3,072 | `84aae78c3ca4c2a1c521f9c92db04bebc062bffe5496fdc73f04f5b77f32bd13` |

The Apple binaries, function extracts, disassemblies, and captured ADT remain
host-local. Recreate the exact extracts from the paired `AppleHPM` Mach-O:

```sh
dd if=/private/tmp/t6040-usb-kexts-25F84/com.apple.driver.AppleHPM \
  of=/private/tmp/t6040-hpm-spmi-start.bin \
  bs=1 skip=$((0x449c8)) count=$((0x718))

dd if=/private/tmp/t6040-usb-kexts-25F84/com.apple.driver.AppleHPM \
  of=/private/tmp/t6040-hpm-spmi-readRegs.bin \
  bs=1 skip=$((0x457e4)) count=$((0x32c))

dd if=/private/tmp/t6040-usb-kexts-25F84/com.apple.driver.AppleHPM \
  of=/private/tmp/t6040-hpm-spmi-publish.bin \
  bs=1 skip=$((0x463a4)) count=$((0xc00))
```

`AppleHPMARMSPMI::start(IOService *)` begins at VA
`0xfffffe0009527648`; its next symbol is at `0xfffffe0009527d60`, proving the
1,816-byte boundary. The next symbol after `publishHPMDevices()` is
`sendHPMReset()` at `0xfffffe0009529c24`, proving its 3,072-byte boundary.

## Consequence for the bootable-stick experiment

The external image and direct eUSB2/XHCI branch are ready. The unresolved
right-port work is now specifically the Gen3 SPMI provider transaction
contract and SN201202x class-10 attach/orientation/source-role/VBUS/repeater
state machine. The paired discovery path demonstrates that even initial HPM
classification crosses a provider state boundary.

Do not turn the census above into a live probe, and do not synthesize HPM,
SPMI, charger, or VBUS writes. The next static task is to identify the exact
class-10 object selected from these reads and then trace its host-mode
transition and rollback. An untethered external-root attempt remains blocked
until that path is independently reviewed and explicitly authorized, or until
a powered/self-powered USB fixture becomes available.
