# T6040 `atcrt` owner correction: monitoring, not link-mode programming

Date: 2026-07-29
Author: sol
Scope: paired-kernelcache static analysis only; no rig or hardware access

## Result

The earlier ticket-170 statement that
`AppleHPMInterface::enableOptions()` calls the `atcrt%u` service for a
retimer-mode transition is wrong.

The paired 25F84 kernelcache contains a dedicated
`com.apple.driver.AppleTypeCRetimer` kext. Its normal start, HPM-message,
state, and power paths monitor retimer health; they do not program a USB2,
USB3, orientation, or accessory mode. The `atcrt` service pointer cached by
AppleHPM is used only to publish/increment a panic counter.

This removes a presumed Linux mode-control prerequisite from ticket 170. It
does **not** prove that the physical retimer needs no power, clock, reset, or
firmware ownership, and it does not identify a safe Linux compatible. The
three ADT children should remain disabled inventory, but lack of an
`AppleTypeCRetimer` Linux clone is not evidence that USB data lanes cannot
work.

## AppleHPM proof

The entire paired AppleHPM `__TEXT_EXEC.__text` was searched for accesses to
the cached retimer pointer at object offset `0x1128`. There are exactly three:

1. `getRetimerNode()` stores the located service;
2. `getRetimerNode()` reloads it to publish the initial `"C Count"` property;
3. `incrementRTPanicCount()` reloads it to update `"C Count"` and deliver a
   notification.

There is no access from `enableOptions()`.

### `getRetimerNode()`

At `0xfffffe000951c5b8`, this function:

- formats the service name `atcrt%u`;
- locates/caches the matching service at `this+0x1128`;
- sets that service's `"C Count"` 32-bit property from `this+0x1238`.

It performs no I2C register access and selects no retimer mode.

### `incrementRTPanicCount()`

At `0xfffffe000951c4f4`, this function:

- increments `this+0x1238`;
- republishes it as the retimer service's `"C Count"` property;
- sends message `0xe0000130`.

That is crash/health accounting, not a connector transition.

### `enableOptions(unsigned)`

At `0xfffffe000951c748`, this function manipulates AppleHPM's own
`"Kart Device"`, `"Kart Error Status"`, and `"Kart Mode Enabled"` properties.
When the relevant state changes, it sends message `0xe0000130` to interested
clients. It never loads or calls the `atcrt` service pointer at `0x1128`, and
contains no I2C transaction.

The previous write-up conflated this notification with a direct call into the
retimer service.

## The actual `atcrt` owner

`ipsw kernel kexts` identifies:

```text
com.apple.driver.AppleTypeCRetimer (1.0.0)
```

The kext exports `AppleTypeCRetimer::{start,messageReceived,setPowerState,
setState,readReg,writeReg,...}` and binds the `atcrt` nodes.

### Normal start path

`AppleTypeCRetimer::start()` at `0xfffffe0009df7f8c` makes one direct local
`readReg()` call:

```text
register = 0x11
length   = 8
locked   = false
```

It chooses initial state 4 when bit 0 of that value is set, otherwise state 3,
then schedules its timer. There is no call to local `writeReg()` in `start()`.

### HPM notification path

`AppleTypeCRetimer::messageReceived()` at `0xfffffe0009df8e20` explicitly
recognizes `0xe0000130`, the message emitted by AppleHPM. It queries registry
state and schedules an action that starts/stops the polling timer. It contains
no call to local `readReg()` or `writeReg()`.

### State and power paths

- `setState(RetimerState)` at `0xfffffe0009dfa0d0` stores the enum at object
  offset `0xb8` and invokes panic/report handling. It does not touch I2C.
- `setPowerState(unsigned long, IOService *)` at
  `0xfffffe0009df9dac` logs and tail-calls the superclass implementation. It
  does not touch I2C.

Whole-text direct-call analysis finds `writeReg()` only in NOR-access,
memory-dump, and reporting/user-client paths. It is absent from normal start,
HPM notification, state, and power handling. The paired macOS driver is
therefore a health/crash reporter for an autonomous retimer, not the owner of
normal USB lane selection.

## Reproducibility

Paired binaries:

```text
b6eab85a4478fe354c29d4a274fa1ea23ced1c051e3b320fdfad54d65dce381d  AppleHPM
8652f44c5aa647cb3b8cbe420ee98a416c5c7cd978bf784785daebf41e2190eb  AppleTypeCRetimer
```

Exact function slices:

```text
03e8ac92ddda5a9c3a462254907ef9f0a3573861a1058d492ced7b7d7b8b3755  AppleHPM::incrementRTPanicCount, 196 bytes
91d7a9b20eab52f91bb8b5b8e3215f1f9bfce350604e58775f12cdf977f7cc2e  AppleHPM::getRetimerNode, 400 bytes
bc5f0c98a396311390c8d48997b6a039d172d00f523a2d92e4895077d47812f4  AppleHPM::enableOptions, 1336 bytes
755488f49feb0707c3a5ea597491373d39e5135a0b3d9349b1969026e9cc73d8  AppleTypeCRetimer::start, 2528 bytes
5bdcbf7cfd5d6d1f4e7ebe1fbc83b1306579023213d6f1d1fb886f69fc808dc1  AppleTypeCRetimer::messageReceived, 1724 bytes
0ca9ee3ec86d8cf963d04b451e3ff9e16b6fc5c78bb6ebc62a0b2615452df450  AppleTypeCRetimer::setPowerState, 376 bytes
92e71ebc21012f086043f283a14b37b84b2baf8d5a2b2af1b6501f206da648f2  AppleTypeCRetimer::setState, 356 bytes
```

The AppleTypeCRetimer extraction is retained host-locally at:

```text
/Users/damsleth/Code/linux-build-out/t6040-usb-kexts-25F84/com.apple.driver.AppleTypeCRetimer
```

## Consequence for USB read/write

The current blockers narrow to:

1. establish the SPMI-HPM source/VBUS state using paired evidence;
2. implement or hand off the native T6040 ATC path, starting with the already
   decoded bank-0/bank-1 eUSB2 host sequence;
3. use the already live-proven DWC3/DART host controller and built-in
   `usb-storage`/UAS stack.

Do not add a guessed Linux compatible for `atcrt`, but do not require a
retimer-mode driver before attempting a separately reviewed USB2 data-path
candidate. The disabled inventory remains useful for future health/reporting
support.
