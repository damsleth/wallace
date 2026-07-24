# T6040 class-10 HPM detach/rollback static slice

Date: 2026-07-24
Ticket: 096 (final static review; remains open with an R3 no-go)
Scope: host-only analysis; no rig, network, MMIO, SPMI, or file edits to the
paired firmware corpus

## Exact source

```text
/private/tmp/kernelcache.release.mac16j
AppleHPM SHA-256:
b6eab85a4478fe354c29d4a274fa1ea23ced1c051e3b320fdfad54d65dce381d
```

PAC-aware method decoding used the exact 25F84 image rather than guessing
targets from signed raw vtable pointers.

## Correct Type10 virtual mapping

Relevant `AppleTCControllerType10` slots:

| Slot | Method |
|---|---|
| `+0x9d8` | `IOAccessoryManager::handleDetectChange(bool)` |
| `+0xb28` | `getAndClearInterrupt(reg, buf, len)` |
| `+0xb38` | `processInterruptEvents(buf, len)` |
| `+0xb40` | `processStatusRegisters()` |
| `+0xb48` | `setCurrentModeFlags()` |
| `+0xb50` | `processModeFlags()` |
| `+0xb60` | `sendDpStatusUpdates()` |
| `+0xb68` | `clearDpIRQ()` |
| `+0xb70` | Type10 `forcePortEvaluation()` |
| `+0xb78` | `setPinConfiguration(unsigned int)` |
| `+0xb80` | `resetDataControl()` |
| `+0xb88` | `repeaterReset(unsigned char)` |
| `+0xb90` | `disablePort(bool)` |
| `+0xb98` | `printConnectedTransports()` |
| `+0xbb8` | `setHPMInactive(bool)` |
| `+0xbc0` | `setHPMActive()` |
| `+0xc18` | `removeUSB2PortObject()` |
| `+0xc20` | `setUSB2PortObjectInactive()` |
| `+0xc28` | `configureUSB2PortObject()` |
| `+0xc30` | `createUSB3PortObject(IOPortTransportStateUSB3 **, unsigned int)` |
| `+0xc38` | `removeUSB3PortObject()` |

This resolves an important ambiguity: `turnOnVbus()` really does stop the USB
timer and dispatch the Type10 `forcePortEvaluation()` override. Interim raw
vtable guesses that called `+0xb70` a DP-status method were wrong.

## Exact `forceUSB23On()` boundary

When its gates pass, `forceUSB23On(arg)`:

1. creates the USB3 port object at `object+0xff0` with argument zero once and
   records that state;
2. records USB-forced-on state;
3. calls `setPinConfiguration(arg)`;
4. conditionally sends `handleDetectChange(false)` when the cached states
   differ, then always sends `handleDetectChange(true)`;
5. stores `0x0101` in its wait/status bytes;
6. starts the 10,000 ms USB timer; and
7. calls `printConnectedTransports()`.

It does **not** directly access HPM logical `0x23`, `0x24`, or `0x55`, and it
does not directly call `clearDpIRQ()`, `repeaterReset()`, or
`setUSB2PortObjectInactive()`.

Type10 `stop()` is only a base-stop thunk. No Type10-local inverse was found.
The timeout path again clears the wait byte, dispatches
`forcePortEvaluation()`, and stops the timer; it is not rollback.

## Register boundaries and missing inverses

### Logical `0x14`

`forcePortEvaluation()` obtains nine event bytes through the interrupt
virtuals, applies:

```text
raw[1] |= 0x0d
raw[7] |= 0x08
```

and processes/writes the result. Its cached branch first OR-merges all nine
cached bytes, then clears the cache. The Type10 message path can OR fresh
event bytes into that cache. No inspected branch clears the two masks.

A save/write-back sequence is not yet a safe inverse: it can race live event
and cache ownership.

### Logical `0x23`

The getter gives the provider a `0x40`-byte capacity and decodes the first four
bytes. The setter writes exactly four zero-initialized bytes, mapping only the
known structure bits. It destroys unmapped raw bits, so it is not a
byte-preserving inverse. The known Type17 update path still does not supply a
general detach recipe.

### Logical `0x24`

The getter gives the provider capacity `0x40` and decodes nine status bytes.
There is no paired write wrapper. A Type16 consumer uses only a few decoded
bits; their semantic names and a detached-completion predicate remain
unproved.

### Logical `0x55`

`writeDataControl2()` is an exact two-byte full replacement. It maps selected
logical bits into the first raw byte and zeros raw bits 0/7 plus the whole
second byte. There is no readback wrapper or evidence that `00 00` means
neutral/detached, so zero is not an approved inverse.

`resetDataControl()` is unrelated: it operates logical `0x50`, not `0x55`.
`disablePort()` operates `0x28`/4CC state. `repeaterReset()` is a separate 4CC
path and is not invoked by `forceUSB23On()`.

## Final PAC-aware detach slice

The remaining Type10 paths have now been decoded from the same pinned
AppleHPM image.

`hpmInterruptAction` at VA `0xfffffe0009536dfc`, file offset `0x5417c`,
size `0x1cc`, SHA-256
`d31c9d85a82dc6ee3e1b271be5fcfe6f7b65cddd59b229ebd42641144f3b6500`
closes the controller event gate, invokes `getAndClearInterrupt(0x14, ..., 9)`,
then dispatches `processInterruptEvents()`.

`getAndClearInterrupt` at VA `0xfffffe000953727c`, file offset `0x545fc`,
size `0x184`, SHA-256
`d13edef5571508aa09d5992c7dab11e94ef3a5b71a70dec0b6a9fc53a2f044ef`
reads logical `0x14` and writes the identical bytes to paired clear register
`0x18`. This consumes W1C event state and has no inverse. The Type10 message
path at VA `0xfffffe000952b454`, file offset `0x487d4`, size `0x25c`,
SHA-256
`9b12acb40c1c86f5869473655d28e342622c984c96b1d29ff7afe0f39b495cbd`
uses the same gate and get/clear sequence. While active it OR-accumulates the
nine bytes in the cache at `this+0xf28`; otherwise it processes them
immediately.

`processStatusRegisters()` at VA `0xfffffe00095383fc`, file offset `0x5577c`,
size `0x468`, SHA-256
`8bae2cdec32b13f3464aa9a6049efcee5830c39a55adb25d4fc968f1075db012`
calls `setCurrentModeFlags()` then `processModeFlags()`. It conditionally
sends `handleDetectChange(false)`, always sends `handleDetectChange(true)`,
prints transports, resets logical data control `0x50`, and sends DP status
notifications. That is a new detect notification sequence, not restoration
of a saved detect state.

`processModeFlags()` at VA `0xfffffe0009539728`, file offset `0x56aa8`,
size `0xa98`, SHA-256
`c6dff58e6cd06c388bf909db9c13de69a8a32231acf80b5aa6571ef4676bb234`
contains the actual paired detach branches. Absent mode flags remove the
USB3 object through `+0xc38`, USB2 through `+0xc18`, then DP and TBT; remaining
flags only reconfigure the existing objects false.

`removeUSB3PortObject()` at VA `0xfffffe00095409c4`, file offset `0x5dd44`,
size `0xd8`, SHA-256
`93515c70cd7b6703eee09afb6f2be6b02e6bdec190b4892d2eb52536c020008a`
removes tunnelling/helper and IOPort software state, releases the object, and
zeros its slot. `removeUSB2PortObject()` has the same software-object
boundary. Neither performs an HPM logical write, VBUS removal, detect-state
restoration, or eUSB2/ATC teardown.

`setHPMInactive(bool)` at VA `0xfffffe000953dc28`, file offset `0x5afa8`,
size `0x124`, SHA-256
`1954b81bd66fbf5006f5339d902ac1067bb65d5501f817a4ce80396ac973e841`
calls `IOService::PMstop()` under the gate, then either decrements the shared
active-HPM count or disables its interrupt event source. It does not
drain/zero the Type10 cache or save hardware masks/events. Its paired
`setHPMActive()` at VA `0xfffffe000953dd4c`, file offset `0x5b0cc`, size
`0x1d4` (function SHA-256 prefix `3bd872…`)
re-runs power setup and synthesizes a fresh eight-byte logical-`0x16`
interrupt mask rather than restoring a saved mask.

`setPowerStateHPM()` at VA `0xfffffe000953ac80`, file offset `0x58000`, size
`0x254`, SHA-256
`47e807c4254b4f136c483fd93a1607a2177bf05ac0c7e6b1400eeff66226f196`
can request SSPS states `0`, `2`, and `3` in the decoded Type10 paths. No
paired path restores the live pre-ticket-095 value `0x07`, and there is no
proof that replaying `0x07` is a valid inverse. Framework RTPC sleep/wake
semantically pairs SPMI transport state, but does not restore that logical
power state.

## Type-C PHY teardown correction

Paired semantic eUSB2 and ACIO shutdown routines do exist. The exact
AppleT6040TypeCPhy eUSB2 initializer begins at VA
`0xfffffe0009dbc5f8` (file `0x14248`, size `0x2184`, function SHA-256
prefix `dbcb6463…`);
its shutdown begins at VA `0xfffffe0009dbe77c` (file `0x163cc`, size
`0x92c`, function SHA-256 prefix `faa87c89…`).
ACIO has matching framework-managed teardown.

This corrects the earlier wording that teardown was absent. It does not clear
the gate: these are client-aggregated semantic shutdowns, not byte-preserving
restoration, and their ordering with HPM event/cache ownership, port objects,
VBUS, and detect notifications remains unproved.

## Final decision

Ticket 096 remains open and **R3 is a no-go**. The static corpus does not
prove:

- a VBUS-off operation;
- race-safe inverse handling for the `0x14` OR mutation or its W1C events;
- exact restoration of interrupt mask, cached events, or detect state;
- restoration of the observed pre-SSPS logical power state `0x07`;
- a preserving `0x23` inverse or neutral `0x55` command; or
- a safe composition order for HPM, object, eUSB2, ACIO, and ATC teardown.

Do not build or run tickets 102–108 from this evidence. A later R3 candidate
needs new primary evidence for those missing boundaries, not another guessed
inverse.
