# T6040 class-10 HPM2 rollback evidence — primary-evidence hunt for ticket 096

Date: 2026-07-25
Ticket: 096 (offline evidence hunt; verdict at the end)
Scope: 100% offline static analysis of the paired macOS 26.x (25F84) driver
binaries. No rig lease, no boot, no SPMI/MMIO transaction, no artifact built or
run. Nothing in `scripts/` was executed.

Supersedes nothing; **corrects** two load-bearing claims in
`done/2026-07-24-t6040-hpm-class10-host-transition.md` and
`done/2026-07-24-t6040-hpm2-detach-static-slice.md` (see "Corrections").

## Exact sources

```text
/private/tmp/t6040-usb-kexts-25F84/
  com.apple.driver.AppleHPM
    sha256 b6eab85a4478fe354c29d4a274fa1ea23ced1c051e3b320fdfad54d65dce381d
    __TEXT_EXEC __text vmaddr 0xfffffe00094fac80 fileoff 0x18000 size 0x581fc
    __DATA_CONST __const  addr 0xfffffe00080bb3e8 fileoff 0x78928
  com.apple.driver.AppleT6040TypeCPhy
    sha256 d0a766201c15bb01b8eeaf6617c91707562ae0c50511ebfccbd9d918acd499f3
  com.apple.driver.AppleTypeCPhy
    sha256 dfbf50c2f5179079b2fc9bcf573dbfd292608039ceb75bb8611731642c9f9ce8
  com.apple.driver.usb.AppleSynopsysUSBXHCI
    sha256 f8b96fabf19180125a1a545790e5d45bef96e9bbd28b7168fda536ed27383e44
  com.apple.driver.AppleSPMI
    sha256 707edb5eb41bcf7252853f8fb24fb2a454e7923dc363294b8e18a6373c284878
```

All 90,239 instructions of the AppleHPM `__text` were disassembled once
(`ipsw macho disass`) and analysed exhaustively rather than by sampling, so the
"never happens anywhere in the binary" statements below are complete for this
kext.

## Method note: how the vtables were decoded (independently)

`__ZTV<class>` addresses the vtable *object*, which begins with 16 bytes
(offset-to-top + RTTI). Slot numbers used in code (`vptr + 0xNNN`) therefore
live at `__ZTV + 0x10 + slot`. Entries are arm64e chained-fixup auth pointers:

```text
target_VA       = 0xfffffe0007004000 + (raw & 0xffffffff)
PAC diversifier = (raw >> 32) & 0xffff
```

The decode is self-checking: the diversifier stored in each entry must equal the
`movk x16/x17, #imm, lsl #0x30` at the call site. Every slot cited below was
verified that way. **This independently confirms Sol's Type10 slot table in
`done/2026-07-24-t6040-hpm2-detach-static-slice.md` as correct.** It also adds
the slots that table lacked, which is where the new evidence came from:

| Slot | Method |
|---|---|
| +0xa28 | `setAccessoryPower(bool,bool,bool,bool,bool)` |
| +0xaa8 | `turnOnVbus()` |
| +0xaf0 | `forceUSB23On(unsigned int)` |
| +0xaf8 | `readReg(reg, buf, len)` |
| +0xb00 | `readRegWithLength(reg, buf, len)` |
| +0xb08 | **`writeReg(reg, buf, len)`** |
| +0xb10 | **`execute4Cc(cmdreg, cc, data, len)`** |
| +0xb20 | `setInterruptMask()` |
| +0xb30 | `setPowerStateHPM(unsigned char)` |
| +0xba0 | `configureRecoveryStatus(unsigned char)` |
| +0xbb0 | `overrideHPMMode(bool,bool,unsigned,unsigned)` |

Knowing slot +0xb08 is `writeReg` is what makes a *complete* HPM write
inventory possible; knowing +0xb10 is `execute4Cc` is what exposed the command
channel.

### The command channel (not previously documented)

HPM commands are 4-character codes built as 32-bit immediates
(`mov w8,#lo ; movk w8,#hi,lsl #0x10`), written to **register 0x08 (CMD1)** with
a separate payload buffer, via `execute4Cc(0x08, &cc, &data, datalen)`. They are
invisible to `strings`. Extracting every such immediate pair and pairing it with
its call site gives the full command surface of the AppleTCController family:

| 4CC | Function | payload |
|---|---|---|
| `SCfg` | `disablePort(bool)` | 11 |
| `DRST` | `exitPDMode(unsigned int)` | 17 |
| `USBd` | `usbDataConnect/Detect/Monitor` | 1 |
| `USBw` | `configureUSBRemoteWakeup` | 1 |
| `EURr` | `repeaterReset(unsigned char)` | 1 |
| `SSPS` | `setPowerStateHPM(unsigned char)` | 1 |
| `DFUf` | `setCurrentModeFlags` (DFU-only branch) | 1 |
| `VDMs` | `isCableKartCapable` | 1 |
| `RDCl` | `rtPanicHandler` | 1 |
| `HChk` | `runHChk` | 64 |
| `VBSi` | `AppleHPMInterface::ignoreVbusLoss` | 1 |
| `UFPf` | `AppleHPMInterface::forceUSBDeviceMode` | 1 |

Firmware/DFU codes also present (`BFUp CFUp RFWs RFWd SFWd SFWi SFWs SFWv Gaid
GAID Grst PRGN ADFU`) are **prohibited** by `docs/SPMI_SAFETY.md` and are listed
only so they are recognised and avoided.

### Complete HPM register-write inventory (whole binary)

`writeReg` is reached only with these register numbers, anywhere in the kext:

| Reg | Len | Where |
|---|---|---|
| 0x08 / 0x09 | var | CMD1 / DATA1 — every `execute4Cc`, plus `challengeCrypto` |
| 0x16 | 8 | `setInterruptMask()` |
| 0x18 | 9 | `getAndClearInterrupt()`, `usbRemoteWakeupTriggered()` (W1C) |
| 0x50 | 4 | `clearDpIRQ()`, `resetDataControl()` |
| 0x53 | 9 | `AppleHPMInterfaceType15::processInterruptEvents` (other class) |
| 0x23 | 4 | `AppleHPMDeviceHALType5::setUSBConfig` (see item 5 — unreachable) |
| 0x55 | 2 | `AppleHPMDeviceHALType5::writeDataControl2` (see item 5 — unreachable) |

Registers **0x14, 0x20 and 0x24 are never written anywhere in the binary.**

Transport bound: `AppleTCController::writeReg` @0xfffffe000953b508 refuses any
length > 0x40 (`cmp w3,#0x40 ; b.hi`) and silently drops all writes when
`this+0xf6f` bit0 is set, then dispatches to the HAL object at `this+0xe40`.

---

# The six items

## Item 1 — VBUS-OFF / power-source-disable: **NOT FOUND**

Not merely "not located": the driver contains **no VBUS control primitive in
either direction**, so there is no inverse to find. Four independent lines of
evidence.

**(a) The accessory-power API is an unimplemented stub in both class families.**

```text
AppleTCController::setAccessoryPower(bool,bool,bool,bool,bool)  @0xfffffe0009545aec
  bti c
  mov  w0, #0x2c7
  movk w0, #0xe000, lsl #0x10        ; kIOReturnUnsupported (0xe00002c7)
  ret
AppleHPMInterface::setAccessoryPower(...)                       @0xfffffe000952562c
  ... identical 4-instruction stub ...
```

**(b) No VBUS/role/source command exists in the 4CC surface.** The complete
inventory above contains no power-role swap, no source enable/disable, no
VBUS assert/de-assert. The only VBUS-adjacent command is `VBSi`
(`AppleHPMInterface::ignoreVbusLoss` @0xfffffe000951aa50), which asks the PD
firmware to *tolerate* VBUS loss — it does not cause it.

**(c) No VBUS platform function exists.** The complete `function-*` set in
AppleHPM is: `LDCM_Mux_Sel0`, `LDCM_Mux_Sel1`, `LDCMpower`, `ldcmInvalid`,
`challenge_crypto`, `cio_mux`, `connect_DIG`, `hdmi_hpd`, `mux_flip_back`,
`mux_flip_front`, `orientation`, `recovery_status_output`, `usb_dconnect`,
`usb_dmonitor`. There is no accessory-power, load-switch or VBUS-enable pin.

**(d) `turnOnVbus()` on class 10 is not a power operation at all.**
`AppleTCControllerType10::turnOnVbus()` @0xfffffe000952c200 (232 bytes), whole
body after the optional log:

```text
0xfffffe000952c290  bl   IOEventSource::closeGate()
0xfffffe000952c294  strb wzr, [x19, #0xf6b]      ; fWaitingForUSB = false
0xfffffe000952c29c  bl   AppleTCControllerType10::stopUSBTimer()
0xfffffe000952c2b0  mov  x17, #0xb70             ; slot +0xb70
0xfffffe000952c2c4  blraa x8, x16                ; forcePortEvaluation()
0xfffffe000952c2d0  bl   IOEventSource::openGate()
0xfffffe000952c2d4  mov  w0, #0
```

Its own log string is
`"AppleTCControllerType10::turnOnVbus(0x%x) - setting fWaitingForUSB to false"`.
Its in-driver caller is `AppleTCController::driverStatusInterrupt`
(slot +0xaa8 @0xfffffe0009545a48), which first reads
`IOPortTransportStateUSB::getDataRole()` and
`IOPortTransportState::getDriverStatus()` and logs
`"driverStatusInterrupt: turnOnVbus"`. So on class 10 `turnOnVbus()` is the
**USB-host-driver-ready acknowledgement**: it clears the wait flag, stops the
10,000 ms timer that `forceUSB23On()` started, and asks the state machine to
re-evaluate.

**Why the absence is meaningful.** VBUS sourcing on this port is decided
autonomously by the SN201202x PD firmware under its own policy. The driver
*observes* it (`AppleHPMLDCM::getVbusPresent`) and can ask the firmware to
tolerate its loss, but never commands it. An R3 design premised on "assert VBUS,
then de-assert it to roll back" has no macOS precedent to copy, because macOS
never asserts it either.

### The nearest real power mutation — and it *is* reversible

Worth recording because it is Apple's own pattern for a reversible port power
change. `AppleTCController::disablePort(bool)` @0xfffffe000953d084, slot +0xb90,
4CC `SCfg` (`mov w8,#0x4353 ; movk w8,#0x6766,lsl#0x10` @0xfffffe000953d100 =
bytes `53 43 66 67`), 11-byte payload:

- `readReg(0x28, sp+0x40, 0x40)` @0xfffffe000953d0ec; aborts on non-zero status.
- `disablePort(true)` — guarded by `this+0xf62` bit0 (already disabled → no-op).
  **Saves** 10 bytes of the just-read register-0x28 image:
  ```text
  0xfffffe000953d12c  ldur x9,  [sp, #0x6e]     ; readbuf+0x2e
  0xfffffe000953d130  ldrh w10, [sp, #0x76]     ; readbuf+0x36
  0xfffffe000953d134  strh w10, [x8, #0x8]
  0xfffffe000953d138  str  x9,  [x8]            ; x8 = this->[0xf20]
  ```
  Builds payload `ee <4B> f4 <4B> ff` and minimises each 16-bit field:
  ```text
  0xfffffe000953d174  and w9, w9, #0x7c
  0xfffffe000953d178  orr w9, w9, #0x3
  ```
  (four times, at payload+1/+3/+6/+8), then `execute4Cc(0x08,'SCfg',payload,0xb)`
  @0xfffffe000953d32c and `strb w8(=1), [x19,#0xf62]`.
- `disablePort(false)` — writes the **saved bytes back unmasked**
  (@0xfffffe000953d1b8-0x953d1e0), reads `readReg(0x20, sp+0x2b, 1)`
  @0xfffffe000953d224 and uses that byte to index the saved table
  (`add x8,x8,x9,lsl #1 ; ldrh w8,[x8,#2]`) for payload+1, then
  `execute4Cc(0x08,'SCfg',payload,0xb)` @0xfffffe000953d280 and
  `strb wzr,[x19,#0xf62]`.
- Both directions run inside `closeGate()`/`openGate()`.

Its **only** callers are the liquid-detection / corrosion-mitigation paths:
`setLDCMLiquidDetected(bool)` (restore @0xfffffe000954301c `mov w1,#0`; disable
via @0xfffffe0009543078 `mov w1,#0x1`), `setLDCMMitigationsEnabled(bool)`
@0xfffffe0009543174, `setLDCMUserOverrideActive(bool)` @0xfffffe00095432c0.

**Honest limits.** The semantics of 4CC `SCfg` and of register 0x28 are *not*
proven — no log string names either, and `PDPowerRoleSource` is the only
adjacent string. That `SCfg` means source/sink configuration and that
`(x & 0x7c) | 0x03` minimises advertised capability is inference. It is **not**
VBUS de-assertion. What *is* proven is the structure: a guarded, gate-held,
byte-saving mutation with an exact byte-restoring inverse.

## Item 2 — race-safe inverse for the 0x14 OR mutation: **premise is void; the W1C has no inverse**

### The hardware "0x14 OR mutation" does not exist

Proven three independent ways.

**(a) Disassembly.** `AppleTCControllerType10::forcePortEvaluation()`
@0xfffffe000952b6b0, non-cached branch:

```text
0xfffffe000952b86c  mov   w1, #0x14
0xfffffe000952b870  mov   w3, #0x9
0xfffffe000952b878  blraa x8, x16          ; slot +0xb28 getAndClearInterrupt(0x14, sp+0x30, 9)
0xfffffe000952b880  ldrb  w8, [sp, #0x31]  ; STACK buffer + 1
0xfffffe000952b884  mov   w9, #0xd
0xfffffe000952b888  orr   w8, w8, w9
0xfffffe000952b88c  strb  w8, [sp, #0x31]
0xfffffe000952b890  ldrb  w8, [sp, #0x37]  ; STACK buffer + 7
0xfffffe000952b894  orr   w8, w8, #0x8
0xfffffe000952b898  strb  w8, [sp, #0x37]
0xfffffe000952b8cc  mov   w2, #0x9
0xfffffe000952b8d8  blraa x9, x17          ; slot +0xb38 processInterruptEvents(sp+0x30, 9)
```

The two ORs target `sp+0x31` and `sp+0x37` — offsets 1 and 7 of the
**stack-local** 9-byte buffer at `sp+0x30`. The cached branch
(@0xfffffe000952b760-0x952b838) applies the same ORs to the software cache at
`this+0xf28`, OR-merges the 9 cache bytes into the stack buffer, calls the same
slot +0xb38, then zeroes the cache (`str xzr,[x8] ; strb wzr,[x8,#8]`).

**(b) The second call is a software dispatch, not a register write.** Slot
+0xb38 of `__ZTV17AppleTCController` resolves to
`AppleTCController::processInterruptEvents(unsigned char*, unsigned short)`
@0xfffffe0009537400, and the call-site diversifier `movk x16,#0xac51`
@0xfffffe000952b824 matches that entry's stored diversifier `0xac51`.

**(c) Exhaustive.** Across all 90,239 instructions, register 0x14 is never
passed to `writeReg`. The complete write set is {0x08, 0x09, 0x16, 0x18, 0x23,
0x50, 0x53, 0x55}.

So `forcePortEvaluation()` fabricates synthetic event bits **in software** so the
driver's own state machine re-evaluates the port. There is nothing to invert.

### What is genuinely irreversible

`AppleTCController::getAndClearInterrupt(uchar reg, uchar *buf, uchar len)`
@0xfffffe000953727c reads `reg` (slot +0xaf8) and writes the identical bytes to a
paired clear register (slot +0xb08):

```text
0xfffffe0009537318  cmp w22, #0x14
0xfffffe0009537330  mov w23, #0x19
0xfffffe0009537338  mov w23, #0x1d
0xfffffe0009537340  mov w23, #0x18      ; 0x14 -> 0x18
```

This W1C consumes pending event state and **has no inverse** — 0x14 is never
written. Mitigating context, now proven rather than assumed: it is the *same*
operation `hpmInterruptAction` @0xfffffe0009536f48 performs on every HPM
interrupt, and Apple's mechanism for not losing events across it is the deferral
cache. `AppleTCControllerType10::message` @0xfffffe000952b5e8-0x952b62c ORs the
freshly read 9 bytes into `this+0xf28` and sets the cache-valid flag
`this+0xf66` when the defer gate `this+0xf59` bit0 is set, processing them later
instead of dropping them.

**Verdict for item 2.** Two of its three sub-questions are answered: the OR
mutation needs no inverse, and the cached-event ownership protocol is now fully
decoded (`this+0xf28` cache, `this+0xf66` valid flag, `this+0xf59` defer gate,
with the exact merge loops). The third is a definitive negative: the W1C
consumption at 0x18 is irreversible and no inverse can exist. It is event
bookkeeping rather than port configuration, but **nothing in the corpus proves
that dropping one batch of pending events at an arbitrary moment is harmless.**

## Item 3 — exact interrupt mask / cable-detect restoration: **NOT FOUND**

**Mask.** `AppleTCController::setInterruptMask()` @0xfffffe00095370ec writes a
**fully synthesized constant**, never a read-modify-write:

```text
0xfffffe0009537184  mov  x8, #0xd07
0xfffffe0009537188  movk x8, #0x2,   lsl #0x20
0xfffffe000953718c  movk x8, #0xbc0, lsl #0x30
0xfffffe0009537190  stur x8, [fp, #-0x20]     ; whole 8-byte mask in one store
...
0xfffffe000953724c  mov  w1, #0x16 ; mov w3, #8 ; blraa   -> writeReg(0x16, ·, 8)
```

= `07 0d 00 00 02 00 c0 0b`, with two conditional patches: byte[7] becomes 0x8b
from a driver property (`ldrb w8,[x19,#0xf68]` @0xfffffe0009537194, `csel`), and
byte[5] becomes 0x10 only if `readRegWithLength(0x5d,·,6)` @0xfffffe00095371f4
succeeds and returns 5. **Register 0x16 is never read on this path and the
pre-existing mask is never saved anywhere.**

A genuine RMW does exist — `AppleHPMDeviceHAL::setHPMInterruptMask`
@0xfffffe000954c1a4 reads 0x16 @0xfffffe000954c22c, applies
`editHPMInterruptMask` (pure `ldrb/orr/strb`, preserves unmapped bits), and
writes back @0xfffffe000954c328 — but HAL slot +0x998 is invoked **only** from
`AppleHPMInterface::setInterruptMask` and its Type10/11/16/18 variants, **never
from any `AppleTCController` function**. Every reg-0x16 operation in the binary:
read len 11 @0xfffffe000952eaec (Type14 only); writes @0xfffffe000952eb50 (11,
Type14), @0xfffffe000953724c (8, base), @0xfffffe0009547b90 (8, Type11),
@0xfffffe000950d318 (11, Type15). The base/Type10 path has no read of 0x16.

`setHPMActive()` @0xfffffe000953dd4c re-runs the same fresh constant
(`ldr x9,[x16,#0xb20] ; blraa` @0xfffffe000953ddc8) — **Sol's claim confirmed**.
`setHPMInactive(bool)` @0xfffffe000953dc28 performs zero HPM register operations.
No symbol in the kext matches save/restore/resume semantics for the mask.

**Cable detect.** `handleAccessoryDetect` @0xfffffe00095363e8 performs no
register access; it reports from the cached bit `this+0xf46`. Every
`handleDetectChange` site (slot +0x9d8 → `IOAccessoryManager::handleDetectChange`,
external to the kext) is @0xfffffe0009538744(false)/0xfffffe0009538768(true) in
`processStatusRegisters`, @0xfffffe000952c130(false)/0xfffffe000952c154(true) in
`Type10::forceUSB23On`, and @0xfffffe000952c6e0(true) in
`Type10::overrideHPMMode` — each preceded by a fresh `processModeFlags()` and a
live comparison of `this+0xf80` against `this+0xf7c`. **The only primitive
available is an unplug→plug re-advertisement; no path restores a previously
saved detect state.**

**Why the absence is meaningful.** Apple never needs to restore this mask
because it only ever writes one canonical value and treats HPM re-activation as
"reassert my known-good configuration", not "put back what was there". A Linux
R3 rollback cannot copy a restore sequence that does not exist; it would have to
invent one, and the value that was there before is not recorded by anything.

## Item 4 — restoration of the observed pre-SSPS power state 0x07: **NOT FOUND**

`AppleTCController::setPowerStateHPM(unsigned char)` @0xfffffe000953ac80 stores
its argument as the 1-byte payload (`sturb w1,[fp,#-0x21]` @0xfffffe000953aca0),
reads `readReg(0x20, [fp-0x22], 1)` @0xfffffe000953ad54 and uses that byte
**only as a redundancy gate** (`cmp w8,w20 ; b.eq` @0xfffffe000953ad60-64, plus
the `this+0xf6b` wait flag), then discards it — it caches the *requested* value
(`strb w20,[x19,#0xf32]`). The command is `SSPS`
(`mov w9,#0x5353 ; movk w9,#0x5350,lsl#0x10`) via
`execute4Cc(0x08,&cc,&arg,1)` @0xfffffe000953adb8.

All 18 slot-+0xb30 call sites were enumerated; there are no direct `bl`s.
Type10-reachable arguments are **{3, 2, 0}** — @0xfffffe0009537e7c /
@0xfffffe0009537ed8 / @0xfffffe0009537f18 in `processInterruptEvents`, and 3 at
@0xfffffe000953aac4 in `setPowerState` (sleep). `Type10::setupPowerManagement`
@0xfffffe000952c2e8 registers only two IOService power states (`mov w3,#0x2`);
the wake transition issues **no SSPS at all** (it runs `poweredStart` +
`forcePortEvaluation` only). `genericStart` seeds the cache to 2
(`mov w8,#0x2` @0xfffffe0009534188).

All four `SSPS` constructions in the binary live inside `*::setPowerStateHPM`
with the caller's argument as payload. **The value 0x07 is never passed to
`setPowerStateHPM` and never appears as an SSPS payload anywhere in the kext.**

`AppleTCController::setSleepState(bool)` @0xfffffe0009545fdc is a stub returning
`kIOReturnUnsupported`. **Register 0x20 is never written** — the only three
reg-0x20 operations in the binary are 1-byte reads (@0xfffffe000953ad54,
@0xfffffe0009549c90, and @0xfffffe000953d224 inside `disablePort`).

**Why the absence is meaningful.** `docs/SPMI_SAFETY.md` records the live
observation that right-HPM2 exposed power state `0x07` before ticket 095's
`SSPS 0x00`. macOS never requests 0x07, so there is no evidence that 0x07 is
even a legal SSPS argument, let alone that replaying it restores the prior
condition. 0x07 is plausibly a *status* encoding (a composite of what the
firmware currently is) rather than a *command* encoding. Writing it back would
be a guess.

## Item 5 — inverse / neutral value for 0x23, 0x24, 0x55: **NOT FOUND, and the registers are outside the class-10 surface**

This is a scope correction as much as a negative result.

**Reachability (proved).** Exactly four accesses to these registers exist
binary-wide, all inside `AppleHPMDeviceHALType5` wrappers:

| Op | Where |
|---|---|
| 0x23 read | @0xfffffe000950ed24 (`getUSBConfig`) |
| 0x23 write, 4 B | @0xfffffe000950eeb4 (`setUSBConfig`) — the only 0x23 write |
| 0x24 read | @0xfffffe000950ec68 (`getUSBStatus`) — **0x24 is never written** |
| 0x55 write, 2 B | @0xfffffe000950ebcc (`writeDataControl2`) — **0x55 is never read** |

Those wrappers have exactly six call sites (HAL vtable @0xfffffe00080c75c8:
+0xa30 `getBRDataControl`, +0xa38 `setBRDataControl`, +0xa40
`writeDataControl2`, +0xa48 `getUSBStatus`, +0xa50 `getUSBConfig`, +0xa58
`setUSBConfig`), and **all six are in `AppleHPMInterfaceType16` /
`Type17`**: @0xfffffe00094fe4ec (`Type17::receiveUFPMessage`),
@0xfffffe00094fe550 and @0xfffffe00094fe5b4 (`Type17::updateUSBConfig`),
@0xfffffe0009507ca8 (`Type16::processInterruptEvents`), @0xfffffe00095080e8
(`Type16::sendDataControl2`), @0xfffffe000950ea94 (internal). Their probes hard-
gate on `hpm-class-type == 16` / `== 17` (`Type16::probe cmp w8,#0x10`
@0xfffffe0009507620; `Type17::probe cmp w8,#0x11` @0xfffffe00094fde10), while
`AppleTCControllerType10::probe` requires `cmp w8,#0xa`. **A class-10 node can
never reach them.** (Type16/17 are C++ subclasses of `AppleHPMInterfaceType10` —
almost certainly the origin of the earlier "Type17 update path" phrasing — but
inheritance is not reachability.)

`AppleTCControllerType10::forceUSB23On` @0xfffffe000952bf5c is confirmed clean:
its only virtual calls are slots +0x8c8, +0xc30, +0xb78, +0x9d8 ×2, +0xb98 — no
`readReg`, `writeReg` or `execute4Cc` at all.

**0x23 is not byte-preserving.** `setUSBConfig` @0xfffffe000950edcc zeroes the
whole 4-byte buffer (`stur wzr,[fp,#-0x14]` @0xfffffe000950ede8) and never reads
0x23. Only 6 of 32 raw bits are mapped (b1 bits5/6/7 ← logical 13/14/15, b2 bit0
← 16, b3 bits1/2 ← 25/26); **all of b0, b1 bits0-4, b2 bits1-7, b3 bit0 and
bits3-7 are forced to zero.** The RMW lives in the caller
(`Type17::updateUSBConfig` @0xfffffe00094fe508), which is unreachable for us.

**0x55 neutral value remains unproven.** `writeDataControl2` @0xfffffe000950eb58
is an exact 2-byte full replacement (`strh wzr,[sp,#0xe]` @0xfffffe000950eb6c);
raw bit0, bit7 and all of byte 1 are always 0. **Correction to the prior
write-up:** logical bits 3 and 4 are *transposed* on the wire — logical 3 → raw
bit 4 (`bfi w10,w9,#0x4,#0x1` @0xfffffe000950eb90) and logical 4 → raw bit 3
(`and w11,w11,#0x8` @0xfffffe000950eb88). There is no paired reader for 0x55
(`getBRDataControl` reads **0x50**, not 0x55 — `mov w1,#0x50`
@0xfffffe000950ea44), no constant table, no literal and no log string
establishing a neutral value. Circumstantially, the sole producer
`Type16::sendDataControl2` @0xfffffe0009507ee8 zero-initialises and its
no-DP/no-USB4/no-TBT fall-through leaves exactly `00 00` — suggestive, but that
is software provenance, not a hardware-proven neutral.

**No detach predicate in 0x24.** `getUSBStatus` performs no field decode, just a
raw copy with a lane swap (`ldur d0,[sp,#0x11] ; rev64 v0.2s ; str d0,[x19]`
@0xfffffe000950ec74-7c). Only three bits are ever consumed, all on the USB4
branch of `sendDataControl2`. **No "detached / disconnect complete" predicate
exists.**

**Practical implication.** Any plan relying on "write a neutral 0x55 to detach"
has *no in-driver precedent to copy on this class*. It would mean calling HAL
wrappers (or raw `writeReg`) ourselves, with a neutral value that is only
software-derived, on a register that is never read back, and that cannot even
express raw bit0/bit7/byte1.

## Item 6 — safe cross-layer teardown order: **NOT FOUND**

The HPM-layer ordering is found and fully specified (below), but the item as
asked — a safe composition order across HPM ↔ eUSB2 repeater ↔ ATC PHY ↔
ACIO/DWC3 — is **not found, and the absence is structural**: Apple performs no
cross-layer teardown on detach.

### HPM layer: **FOUND** — a fully specified, bidirectional, ordered primitive

`AppleTCControllerType10::overrideHPMMode(bool enforce, bool
keepRoleAndOrientation, unsigned dataStatus, unsigned status)`
@0xfffffe000952c3bc (960 bytes), slot +0xbb0. The base
`AppleTCController::overrideHPMMode` @0xfffffe000953dc1c is a 12-byte stub, so
this is specific to our class. Log string:
`"AppleTCControllerType10::overrideHPMMode -- enforce=%d, keepRoleAndOrientation=%d, dataStatus=%u, status=%u"`.

Reached by IOKit message selector **0xe3ff843f** in
`AppleTCControllerType10::message` @0xfffffe000952b454; the argument struct at
`x3` is fully decoded:

```text
0xfffffe000952b4ec  ldrh w8, [x3, #0xc]      ; +0xc u16 port number (0xff = any)
0xfffffe000952b4f0  cmp  w8, #0xff
0xfffffe000952b4fc  cmp  w8, w9              ; else must equal this->[0xf30]
0xfffffe000952b504  ldp  w8, w4, [x3, #0x4]  ; +0x4 u32 dataStatus, +0x8 u32 status
0xfffffe000952b524  ldrb w10, [x3, #0x1]     ; +0x1 bit0 keepRoleAndOrientation
0xfffffe000952b528  ldrb w11, [x3]           ; +0x0 bit0 enforce
0xfffffe000952b52c  and  w1, w11, #0x1
0xfffffe000952b530  and  w2, w10, #0x1
0xfffffe000952b538  mov  x3, x8
0xfffffe000952b540  blraa x9, x16            ; slot +0xbb0
```

Sibling selectors: **0xe3ff8449** → `forcePortEvaluation()` directly
(@0xfffffe000952b638); **0xe3ff8453** → `enableOptions(unsigned)`
(@0xfffffe000952b58c).

With `keepRoleAndOrientation` set, the live cached status words are merged in,
which is what makes a save/restore well defined:

```text
0xfffffe000952c41c  ldr w8, [x8]                   ; this->[0xee8] cached dataStatus
0xfffffe000952c424  and w8, w8, w9                 ; w9 = 0x50
0xfffffe000952c430  ldr w9, [x9]                   ; this->[0xef0] cached status
0xfffffe000952c438  and w9, w9, w10                ; w10 = 0x82
0xfffffe000952c440  and w10, w20, #0xffffffaf      ; caller status   & ~0x50
0xfffffe000952c454  and w8,  w21, #0xffffff7d      ; caller dataStat & ~0x82
```

Then `this+0xf71 = enforce`, and **both** directions run the same ordered chain
under `closeGate()`:

1. if any transport byte (`this+0xf4d/0xf4e/0xf50/0xf52/0xf53`) is set — teardown:
   - +0xb48 `setCurrentModeFlags(0, 0)`      @0xfffffe000952c5b0
   - +0xc08 `communicateDPStateChange()`     @0xfffffe000952c5ec
   - +0xb60 `sendDpStatusUpdates()`          @0xfffffe000952c628
   - +0xb50 `processModeFlags()`             @0xfffffe000952c664
2. if `(dataStatus | status) != 0` — (re)attach:
   - +0xb48 `setCurrentModeFlags(dataStatus, status)` @0xfffffe000952c698
   - +0xb50 `processModeFlags()`                     @0xfffffe000952c6d4
3. +0x9d8 `handleDetectChange(true)`   @0xfffffe000952c6f8 (`mov w1,#0x1`)
4. +0xb98 `printConnectedTransports()` @0xfffffe000952c718
5. +0xb70 `forcePortEvaluation()`      @0xfffffe000952c750
6. `openGate()`, return 0.

Re-entry guard: if `this+0xf5d` bit0 **and** `this+0xf71` bit0 are both set the
entire body is skipped (@0xfffffe000952c54c-0x952c558).

So a rollback at the HPM layer is expressible as
`overrideHPMMode(false, keep, saved_dataStatus, saved_status)`, and the values to
save are readable from `this+0xee8` / `this+0xef0`.

For completeness, the transition itself is gated in `processStatusRegisters()`:
`setCurrentModeFlags(dataStatus, status)` @0xfffffe00095384fc, then require
`this+0xf48` bit0 set, `this+0xf32` non-zero, `this+0xf6c` bit0 clear and
`this+0xf6d` bit0 clear (@0xfffffe0009538500-0x9538544) before
`forceUSB23On(dataStatus)` @0xfffffe0009538568.

### But the teardown contains one blind, unsaved, non-restorable register write

`setCurrentModeFlags(0, 0)` @0xfffffe0009538864 enters its reset block
unconditionally when `status` bit0 is clear (`tbz w2,#0` @0xfffffe0009538890),
zeroes ~20 bytes of cached transport state, stops the analytics timer, clears the
SOP/SOP' VID/PID caches (slots +0xcf8, +0xd00, +0xd28, +0xd30), and then calls
slot +0xb68 `clearDpIRQ()` @0xfffffe00095389f4.

`AppleTCController::clearDpIRQ()` @0xfffffe000953a4a4 performs **no read**:

```text
0xfffffe000953a52c  mov   w0, #0x4
0xfffffe000953a530  bl    _IOMallocData
0xfffffe000953a53c  mov   w8, #0x2000
0xfffffe000953a540  str   w8, [x0]        ; buffer = 0x00002000
0xfffffe000953a564  mov   w1, #0x50
0xfffffe000953a56c  mov   w3, #0x4
0xfffffe000953a574  blraa x8, x16          ; slot +0xb08 writeReg(0x50, buf, 4)
```

— a **blind full-word replacement of register 0x50 with 0x00002000**, no prior
read, no saved value.

The sibling `resetDataControl()` @0xfffffe000953a610 shows Apple knows how to do
this preservingly, but only partially: `readReg(0x50,buf,4)` @0xfffffe000953a6e0,
test `buf[1]` bit5 (= word bit 13 = 0x2000) @0xfffffe000953a6e4; if clear it
writes nothing at all; if set it does `strh wzr,[x20]` (zero the low 16 bits,
**preserve the high 16 as read**) then `writeReg(0x50,buf,4)`
@0xfffffe000953a798. Even the preserving variant discards the low 16 bits
without saving them.

**This is the concrete irreversibility in the detach path.** Register 0x50 is
mutated with no saved prior value and no inverse, and the mode-flag reset that
`overrideHPMMode` uses hits it unconditionally. Register 0x50 *is* readable
(`resetDataControl` proves it), so an R3 artifact could save and restore it — but
whether writing a saved value back to 0x50 is legal is unproven, because 0x50
has at least one W1C-style bit (bit 13) and re-writing a saved word could
re-assert bits the firmware has since cleared.

The one other command in this chain, 4CC `DFUf` @0xfffffe0009539498, is
unreachable on a healthy port: it requires register 0x03 to literally read
`"DFU"` (`cmp w9,#0x44 ; cmp w9,#0x46 ; cmp w8,#0x55` @0xfffffe0009539428-0x9539444)
**and** `this+0xf5d` bit0 set. It is a firmware-update exit and is prohibited by
`docs/SPMI_SAFETY.md` regardless.

**Net HPM-layer mutation surface of the complete detach + reattach chain, on a
normally-operating port: exactly two operations** — the blind `writeReg(0x50,
00 20 00 00, 4)` in `clearDpIRQ()`, and the `getAndClearInterrupt(0x14 → 0x18,
9)` W1C in `forcePortEvaluation()`. Neither has an inverse in Apple's code.

### Where the attach/detach ordering actually lives

`processModeFlags()` @0xfffffe0009539728 is a **pure software port-object
reconciler**: it performs `readReg(0x48, 37)` @0xfffffe00095397c0 and
`readReg(0x49, 37)` @0xfffffe0009539a90 and **no register write at all**, and it
contains no call to `repeaterReset`, `resetDataControl`, `clearDpIRQ`,
`setPinConfiguration`, `disablePort`, `handleDetectChange`,
`sendDpStatusUpdates` or `printConnectedTransports`. Its detach order is
object-removal only:

```text
configureBasePort()        (+0xbe8) @0xfffffe0009539770
removeUSB3PortObject(&this+0xff0, false) (+0xc38) @0xfffffe0009539d50
removeUSB2PortObject(&this+0xfd8)        (+0xc18) @0xfffffe0009539dac
removeDPPortObject(&this+0xfb8, false)   (+0xbf8) @0xfffffe0009539e04
removeTBTPortObject()                    (+0xc70) @0xfffffe0009539e60
messageClients(0xe0000130)               (+0x770) @0xfffffe0009539fd0
```

The natural (non-forced) ordering lives in `processStatusRegisters()`
@0xfffffe00095383fc, whose tail is:

```text
setCurrentModeFlags()      @0xfffffe00095384fc   (-> clearDpIRQ -> blind write 0x50)
bail if this[0xf6e] & 1    @0xfffffe0009538698
processModeFlags()         @0xfffffe00095386b8
log "advertise unplug" + handleDetectChange(false) @0xfffffe000953875c
                                          (only if this[0xf80] != this[0xf7c])
handleDetectChange(true)   @0xfffffe0009538780   (unconditional)
printConnectedTransports() @0xfffffe00095387a0
resetDataControl()         @0xfffffe00095387d8   (conditional RMW of 0x50)
communicateDPStateChange() @0xfffffe0009538810
sendDpStatusUpdates()      @0xfffffe0009538848
```

with an earlier bail-out @0xfffffe0009538484 if `this[0xf6b] | this[0xf71]` is
set. So register 0x50 is written twice in this chain — once blind by
`clearDpIRQ`, once conditionally-preserving by `resetDataControl`.

`setPinConfiguration(unsigned int)` @0xfffffe000953b7a8 **drives no other
layer**: it writes six software bytes at `this+0x1090..0x1095` and publishes an
OSDictionary (`tx1/rx1/tx2/rx2/sbu1/sbu2`) under the `"Pin Configuration"`
property (`setProperty` @0xfffffe000953bc98). Its argument is the mode-flags
word: bit0 = data connection (if clear it logs
`"No pin config set, no data connection"` and **leaves the stale pin bytes**),
bits[11:10] = DP pin assignment (`ubfx w9,w1,#0xa,#2` @0xfffffe000953b86c),
`this[0xf60]` bit0 = orientation.

### Cross-layer (eUSB2 repeater / ATC PHY / ACIO / DWC3): **NOT FOUND — structurally**

There is no cross-layer teardown *order* to find, because on USB-C disconnect
**the four layers are not sequenced against one another at all.** The HPM detach
path never touches the PHY, repeater or xHCI; the PHY teardown is triggered by
driver stop / power state, not by cable detach, and never touches the HPM.

**The repeater boundary is orphaned.** `AppleTCController::repeaterReset(unsigned
char)` @0xfffffe000953c684 builds 4CC `EURr`
(`mov w8,#0x5545 ; movk w8,#0x7252,lsl#0x10` @0xfffffe000953c714), passes the
caller's byte through verbatim (`sturb w20,[fp,#-0x25]`) and issues
`execute4Cc(0x08,'EURr',&target,1)` @0xfffffe000953c774 under the gate. Its
**only** caller is the `callPlatformFunction` tail-branch @0xfffffe000953c634,
reached when the OSSymbol is `_gAppleARMFunctionCall` and the OSData 4CC at +4 is
`prst` (0x70727374). Payload domain is exactly {0,1,2} (client `0`→1, `1`→2,
`255`→0; anything else refused with 0xe00002c2). **No caller of `prst` exists in
any of the four binaries** — so the eUSB2 repeater reset is never invoked by the
HPM driver's own attach or detach path, and its owner is outside this corpus.

**The eUSB2 PHY shutdown is "known-off", not an inverse.**
`shutdownUSB2()` @0xfffffe0009df6e7c is a bare branch to `eusb2phy_shutdown`
@0xfffffe0009dbe77c, whose exact sequence (bank 0 only, via `_ml_io_write32`) is:

```text
B0+0x04 |= 0x2            @0xfffffe0009dbe7c0
IOSleep(5)                @0xfffffe0009dbe924
B0+0x00  = (old & ~7) | 4 @0xfffffe0009dbe940
B0+0x04 |= 0x8            @0xfffffe0009dbeab8
B0+0x04 |= 0x1            @0xfffffe0009dbec30
B0+0x1c |= bit29          @0xfffffe0009dbeda8
B0+0x1c |= bit30          @0xfffffe0009dbef20
IOSleep(500)
```

Compared with `eusb2phy_init`, it inverts bits 3/0/1 of `B0+0x04` and bits 29/30
of `B0+0x1c`, but **never clears `B0+0x04` bit 2** (which init sets), writes mode
**4** where init writes 0 or 2, and **never touches `B0+0x08` or bank 1**. It
saves nothing. It is idempotent in effect (all OR-sets), and `shutdownACIO`
@0xfffffe0009df6f3c is explicitly guarded by an already-off flag at
`this+0x798`. So it is a known-off sequence, not byte-preserving restoration and
not even a complete bit inverse of init.

**Composition is emergent, not scripted.** The shutdown hooks are reached only
from `configureUSB2` (+0x920) / `configureLanes` (+0x918), themselves called from
the `AppleTypeCPhy::close` block @0xfffffe0009daa45c after `isInterfaceOpen`,
then `assignLaneClient` / `assignUSB2Client`. The ordering falls out of
reference-counted client arbitration.

**xHCI orders itself against the PHY only on driver stop.**
`AppleT8150USBXHCI::stopThreadCallGated()` @0xfffffe000b02e710 is the only xHCI
path touching the PHY: quiesce its own provider chain (@0xfffffe000b02e74c,
@0xfffffe000b02e7c4) → USB2 interface `close()` @0xfffffe000b02e81c → release and
null → lane/CIO interface `close()` @0xfffffe000b02e89c → release and null. That
is a real order, but for driver stop, not detach, and no HPM is involved. There
is no PHY→xHCI callback.

**String evidence supports the absence.** `AppleTypeCPhy` and
`AppleSynopsysUSBXHCI` contain **zero** detach/disconnect/teardown/unplug/quiesce
strings; `AppleT6040TypeCPhy` has only function names. AppleHPM has
`"advertise unplug"`, `"Adjusting HPM power state to active unplugged"`,
`"Kart mode skipping message due to forced disconnect"`,
`-hpmUnplugForceUpdateMode` and the bare token `ForceCIOTeardown`, but no prose
anywhere describing a sequence or a precondition. Given how heavily Apple
instruments the attach direction, that silence is itself evidence.

**Why the absence is meaningful.** A reimplementation cannot follow Apple's
cross-layer teardown order because Apple does not perform one on detach. The
layers are decoupled: HPM reconciles software port objects and notifies clients;
the PHY tears down when its last client closes. Any R3 rollback that must
sequence HPM, repeater, PHY and DWC3 would be inventing an order, not copying
one — and the corpus gives no way to validate the invention.

---

# Verdict on ticket 096

**Items 1, 2 and 6 are NOT all FOUND. Ticket 096 stays OPEN and R3 remains a
NO-GO.** Do not build or run tickets 102–108, and do not treat anything in this
document as authorisation to attempt the right-port host transition.

Summary against the six items:

| # | Item | Result |
|---|---|---|
| 1 | VBUS-off / power-source-disable | **NOT FOUND** — no VBUS primitive exists in either direction |
| 2 | Race-safe inverse for the 0x14 OR + W1C/cache state | **Premise void** for the OR (software-only); **NOT FOUND** for the 0x18 W1C, and provably cannot exist |
| 3 | Interrupt mask / cable-detect restoration | **NOT FOUND** — mask is a synthesized constant, never saved; no detect restore path |
| 4 | Restoration of pre-SSPS state 0x07 | **NOT FOUND** — 0x07 is never a macOS SSPS argument; reg 0x20 is read-only to the driver |
| 5 | Inverse / neutral for 0x23 / 0x24 / 0x55 | **NOT FOUND** — and these registers are unreachable from the class-10 path entirely |
| 6 | Safe cross-layer teardown order | **NOT FOUND** — structurally: Apple performs no cross-layer teardown on detach. HPM-layer order IS found and fully specified, but it still contains one blind unsaved write (reg 0x50) |

## Risk framing (read with `done/2026-07-25-t6040-r3-risk-calibration.md`)

This NO-GO is a **completeness verdict about the reversal decode**, not a danger
claim, and it does not reinstate the withdrawn "unrecoverable port" overstatement.

This analysis independently corroborates the risk calibration's central point.
The exhaustive write inventory above is the whole class-10 mutation surface:
registers 0x08/0x09 (CMD1/DATA1), 0x16, 0x18, 0x50 — plus 0x23/0x55 which are
unreachable from this class. **There is no flash, OTP, patch-bundle or other
non-volatile write path in it.** The firmware-update 4CCs
(`BFUp CFUp RFWs RFWd SFWd SFWi SFWs SFWv Gaid GAID Grst PRGN ADFU`) exist in the
binary but sit behind DFU-mode gates and are prohibited by policy; the only one
reachable from the mode-flag path, `DFUf`, requires register 0x03 to literally
read `"DFU"`.

So the two irreversible operations identified here — the blind 0x50 word write
and the 0x18 W1C event consumption — are **volatile state that a power cycle
re-establishes**, which per the calibration is routine in this workflow rather
than an incident. What remains unproven is narrower and more precise than
before: not "is this dangerous" but "can we put the port back without a power
cycle, and do we know the values to put back". The answer to both is still no.

## Corrections to earlier write-ups

1. **`done/2026-07-24-t6040-hpm-class10-host-transition.md`** states the
   `forcePortEvaluation()` operation as
   `read 0x14 / raw[1] |= 0x0d / raw[7] |= 0x08 / write address 0x14, length 9`.
   The final step is **not** a register write. It is the virtual call at slot
   +0xb38, `processInterruptEvents(buf, 9)` — verified by symbol, by PAC
   diversifier, and by the fact that register 0x14 is never passed to `writeReg`
   anywhere in the kext. The two ORs land on a stack buffer, not on hardware.
2. **`done/2026-07-24-t6040-hpm2-detach-static-slice.md`** carries the same
   mis-decode forward ("and processes/writes the result"), and its final-decision
   bullet "race-safe inverse handling for the `0x14` OR mutation" rests on it.
   That specific blocker is void; the real one is the 0x18 W1C, plus the blind
   0x50 write documented above.
3. Same document, logical `0x55`: the bit map is off by a transposition. Logical
   bit 3 maps to **raw bit 4** and logical bit 4 maps to **raw bit 3**
   (`bfi w10,w9,#0x4,#0x1` @0xfffffe000950eb90 and `and w11,w11,#0x8`
   @0xfffffe000950eb88).
4. Same document, logical `0x23`: "the known Type17 update path" is accurate but
   understates the result — `Type16`/`Type17` gate on `hpm-class-type` 16/17 and
   are **unreachable from a class-10 node**, so 0x23/0x24/0x55 are outside our
   mutation surface entirely rather than merely lacking a recipe.
5. Not a correction: that document's Type10 vtable slot table is **confirmed
   correct** by independent PAC-diversifier-checked decoding, as is its finding
   that `setHPMActive()` synthesizes a fresh mask rather than restoring one.
6. `AppleTCController::setUSBConfig`'s error log is an Apple copy-paste bug — it
   prints `"...writeDataControl2 returned 0x%x"` (@0xfffffe000950eec8). Do not
   attribute that log line to a 0x55 write.

Consequently `docs/SPMI_SAFETY.md`'s Class-R3 wording ("HPM logical addresses
`0x14`, `0x23`, `0x24`, and `0x55`") names three registers the class-10 path
never writes and omits the two it does (`0x50`, and `0x18` as W1C). That is a
maintainer decision, not an edit I have made here.

## What did change, and why it matters

The risk picture is materially different from the 2026-07-24 conclusion, in both
directions.

**Smaller than believed.** The class-10 host transition does not write HPM
address 0x14, does not touch 0x23/0x24/0x55 at all, and contains no VBUS
operation — because macOS has none. `turnOnVbus()` is a software
driver-ready acknowledgement. The entire detach/attach chain's hardware surface
is two operations, both now exactly characterised. The R3 class as written in
`docs/SPMI_SAFETY.md` ("HPM logical addresses 0x14, 0x23, 0x24, and 0x55") names
three registers that the class-10 path never writes.

**Different, not gone.** The remaining irreversibility is real and specific:
a blind unsaved word write to register 0x50, and a W1C event consumption at
0x18. Neither has an inverse in Apple's code. Restoration of the interrupt mask,
the detect state, and power state 0x07 is not merely undocumented — macOS never
does it, so there is no correct sequence to copy for any of them.

**And one assumption behind R3 is simply wrong.** The plan implicitly assumed
Apple sequences HPM, eUSB2 repeater, ATC PHY and DWC3 on detach, and that we
needed to find that sequence. Apple does not sequence them: the HPM reconciles
software port objects and notifies clients, the PHY tears down when its last
client closes, the repeater reset is never invoked by this driver at all, and
xHCI orders itself against the PHY only on driver stop. There is no order to
copy. An R3 rollback that needs one would be inventing it, with nothing in the
corpus to validate the invention against — which is a materially worse position
than "the order exists but we have not decoded it yet".

## What an R3 artifact would need to implement

Recorded so the next candidate is designed against evidence rather than
guesswork. **This is not authorisation to build or run it.** A separate,
reviewed ticket and explicit maintainer approval are required, and the open
items above would have to be closed first.

1. Drive the transition through the decoded mode-flag path, not through invented
   register writes: read the status registers, derive `(dataStatus, status)`, and
   use the `overrideHPMMode` chain's ordering
   (`setCurrentModeFlags` → `communicateDPStateChange` → `sendDpStatusUpdates` →
   `processModeFlags` → `handleDetectChange(true)` → `forcePortEvaluation`).
2. Save, before any mutation: the full 4-byte register 0x50 word; the 8-byte
   register 0x16 mask if it proves readable at length 8 on this part (only
   Type14 reads 0x16, at length 11 — unproven for class 10); the observed
   register 0x20 byte; and the `(dataStatus, status)` pair.
3. Provide the inverse explicitly, because Apple does not: restore register 0x50
   and re-issue `overrideHPMMode(enforce=false, …, saved_dataStatus,
   saved_status)`. Both need review — re-writing a saved 0x50 word may re-assert
   a W1C bit, and that must be reasoned about before it is attempted.
4. Bound everything: `writeReg` length ≤ 0x40 (Apple's own limit), all commands
   through CMD1 = register 0x08, and no firmware/DFU 4CC ever
   (`DFUf BFUp CFUp RFWs RFWd SFWd SFWi SFWs SFWv Gaid GAID Grst PRGN ADFU`).
5. Accept, and state in the manifest, that the 0x18 W1C event consumption is
   irreversible, and that no restoration exists for the interrupt mask, the
   detect state, or power state 0x07.
6. Not touch the eUSB2 repeater (`EURr`/`prst`, payload domain {0,1,2}) or the
   ATC PHY as part of the transition. Apple's own path does not, the PHY
   shutdown is known-off rather than restoring, and there is no validated
   composition order to follow.

Closing 096 would require, at minimum: primary evidence that a saved register
0x50 word can be safely written back; a decided position on the 0x18 W1C
(either proof it is harmless at a chosen quiescent point, or a design that never
issues it); and the cross-layer composition order below.
