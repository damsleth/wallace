# T6040 SN201202x class-10 host-transition checkpoint

Date: 2026-07-24

Ticket: 023

Scope: host-only static analysis of the paired 25F84 `AppleHPM` kext and the
captured J614s ADT. No rig, proxy, MMIO, SPMI, PMU, charger, target-memory,
storage-device, or Boot Policy access.

Policy update later on 2026-07-24: `docs/SPMI_SAFETY.md` now permits exact
staged right-HPM2 transactions. The address-`0x14` mutation remains outside
R0/R1/R2 and is not approved; offline ticket 096 must prove attach and
detach/rollback before R3 ticket 097 can be reviewed.

## Exact class selection

The right-port class path is proved at both layers:

1. `AppleHPMARMSPMI::publishHPMDevices()` compares its provider's
   `compatible` property with `usbc,sn201202x,spmi` and constructs
   `AppleHPMDeviceHALType5`.
2. `AppleTCControllerType10::probe(IOService *, int *)` fetches
   `hpm-class-type`, requires the value `10`, and otherwise refuses the
   provider.

The J614s `hpm2` node has exactly that compatible and `hpm-class-type = 10`.
The relevant target stack is therefore:

```text
Apple SPMI Gen3
  -> AppleHPMARMSPMI
  -> AppleHPMDeviceHALType5
  -> AppleTCControllerType10
```

This removes ambiguity between the several HPM HAL and controller classes in
the paired driver.

## Exact `turnOnVbus()` mutation

`AppleTCControllerType10::turnOnVbus()` is 232 bytes at VA
`0xfffffe000952c200`, file offset `0x49580`. It does not contain a direct
SPMI transaction. Under the controller lock it:

1. clears the object's `waitingForUSB` byte;
2. stops its USB timer; and
3. dispatches the class's `forcePortEvaluation()` override.

`AppleTCControllerType10::forcePortEvaluation()` is 720 bytes at VA
`0xfffffe000952b6b0`, file offset `0x48a30`. Its non-cached path performs this
exact HPM operation:

```text
read  address 0x14, length 9
raw[1] |= 0x0d
raw[7] |= 0x08
write address 0x14, length 9
```

The cached path applies the same two OR masks to the cached nine-byte block,
OR-merges that block with a fresh nine-byte read, writes the merged result to
address `0x14`, then zeros the cache. No branch in this function clears those
bits or restores the pre-write bytes.

This is the first exact state-changing HPM command below the high-level
right-port VBUS path. The register's semantic bit names are not present in the
binary, so the masks must remain raw rather than being assigned guessed Type-C
meanings.

## HALType5 USB register boundary

Four symbolized `AppleHPMDeviceHALType5` methods expose the SN201202x USB
register interface:

| Method | HPM operation |
|---|---|
| `getUSBConfig` | read address `0x23`; parse a four-byte config |
| `setUSBConfig` | write four bytes to address `0x23` |
| `getUSBStatus` | read address `0x24`; parse a nine-byte status |
| `writeDataControl2` | write two bytes to address `0x55` |

The config packing is also exact. `getUSBConfig` maps raw byte 1 bits 5, 6,
and 7 to structure bits 13, 14, and 15; raw byte 2 bit 0 to structure bit 16;
and raw byte 3 bits 1 and 2 to structure bits 25 and 26. `setUSBConfig`
performs the inverse mapping into a zero-initialized four-byte payload.

These methods prove the register numbers, transfer lengths, and packing. They
do not prove that a minimal host transition consists only of writing those
registers.

## Remaining state machine

`AppleTCControllerType10::forceUSB23On(unsigned int)` is a separate 676-byte
routine at VA `0xfffffe000952bf5c`, file offset `0x492dc`. It modifies
controller state, invokes several virtual HPM/transport operations (including
separate calls with arguments 0 and 1), starts a 10,000 ms USB timer, and
invokes another virtual operation. Those virtual callees and the
disconnect/rollback path still need to be named before this becomes an
implementation recipe.

Most importantly, neither `turnOnVbus()` nor `forcePortEvaluation()` contains
a local inverse for the OR-only `0x14` mutation. A candidate that merely saves
and writes back nine bytes would be speculative: the block can contain live
status/command state and the paired driver uses cached merge and interrupt
coordination around it.

## Sources and reproducibility

| Item | Size | SHA-256 |
|---|---:|---|
| extracted `AppleHPM` kext | 836,032 | `b6eab85a4478fe354c29d4a274fa1ea23ced1c051e3b320fdfad54d65dce381d` |
| exact Type10 `probe` bytes | 184 | `f09c1325c6d0b70b91890a09d97aba6322b2e3c5443d41fabb1b48cf844ff737` |
| exact Type10 `forcePortEvaluation` bytes | 720 | `c3068687c33afe20625a4e13c1f1b5280f580f7a4f938cfe5ce39e1ef2fc7c24` |
| exact Type10 `forceUSB23On` bytes | 676 | `cfadbe6e7e52dddd9b536525738dae341829e7515e62144ec376e22a0c5a7ad6` |
| exact Type10 `turnOnVbus` bytes | 232 | `66bd1875ad2e7650b84476a51d4dd502db1db96d1e1dd05bd6cb10389d395bb9` |
| exact HALType5 `writeDataControl2` bytes | 164 | `10ccd69d005de6b60bcc2cbb211bb7c71e0e401ad43f82ca65b619af0e7226de` |
| exact HALType5 `getUSBStatus` bytes | 188 | `c1f20bf85b5e7e842585ddd9ca096bee2a0aedaea13df5ab0d138b422a712ae3` |
| exact HALType5 `getUSBConfig` bytes | 276 | `d8f728b7eabc3e05aa2b247af0248aef607c178681ed737319522bf9ce0df21e` |
| exact HALType5 `setUSBConfig` bytes | 280 | `db11df27faeb72b9bd7e5ecfa90e5868f9bc9058505bd927249d7502af0b6251` |

The Apple binary, function extracts, and disassemblies remain host-local.
Every file offset above is derived from the Mach-O `__TEXT_EXEC` mapping
(`vmaddr 0xfffffe00094fac80`, file offset `0x18000`).

## Decision

Do not replay the address-`0x14` mutation and do not call it a VBUS-enable
recipe. It is a proven piece of the class-10 path, but it lacks a proven
disconnect inverse and still depends on Gen3 SPMI provider ownership,
interrupt/cached-command coordination, USB config/status handling, and the
external repeater transition.

The next safe work is static: resolve the virtual callees in
`forceUSB23On()`, trace the paired detach/power-down path, and require an
independent review of both directions. The bus-powered stick remains blocked
from a useful untethered external-root test until that boundary is closed.
