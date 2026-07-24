# T6040 class-10 HPM detach/rollback static slice

Date: 2026-07-24
Ticket: 096 (remains open)
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
| `+0xc20` | `setUSB2PortObjectInactive()` |
| `+0xc28` | `configureUSB2PortObject()` |
| `+0xc30` | `createUSB3PortObject(IOPortTransportStateUSB3 **, unsigned int)` |

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

## Decision

Ticket 096 remains blocked. The paired code still does not prove:

- VBUS removal;
- safe clearing/restoration of the `0x14` mutation;
- USB3 object removal and detect-state restoration;
- a preserving `0x23` inverse or neutral `0x55` command;
- eUSB2 repeater and T6040 ATC shutdown ordering; or
- interrupt/cache quiescence before rollback.

The next static slice is PAC-aware caller tracing of
`removeUSB3PortObject()`, `setHPMInactive()`, actual detach branches in
`processStatusRegisters()`/`processModeFlags()`, and the Type-C PHY teardown.
No R3 artifact may be built until a forward and inverse sequence are both
proved.
