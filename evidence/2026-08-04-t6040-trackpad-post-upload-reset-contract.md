# T6040 trackpad: the post-upload "reset" is a power request, and J614s only speaks version 2

Date: 2026-08-04
Ticket: successor to 197/212 (trackpad HIDF)
Rig use: **none**. Static analysis only.

## Outcome in one line

Command `0x40` is not "reset interface" — it is the MTP coprocessor's
**interface power request**, and the J614s MTP firmware implements **only** the
nine-byte, version-2, two-phase form. Our four-byte, version-1 request is
rejected on the payload-length check, before any other field is examined, with
`kIOReturnBadArgument` (`0xe00002c2`) — byte-for-byte the observed failure.

Patch: `patches/t6040-dockchannel-hid-reset-contract.patch` (applies after
`t6040-dockchannel-trackpad-fw.patch`; verified with `git apply --check`).

## Artifacts and tools

| Artifact | Path | SHA-256 |
|---|---|---|
| macOS 25F84 kernelcache (raw MachO, MH_FILESET, symbol-rich) | `/Users/damsleth/Code/linux-build-out/t6040-kernelcache-25F84.raw` | (as pinned in ticket 212) |
| J614s MTP coprocessor firmware (decompressed IM4P payload) | `/private/tmp/wallace-offline-25F84/mtp/J614S_MtpFirmware.bin` | `6528799d227f2a78bc23ddd1870a70171587b3531da9e9950e6e402ac96763ed` |
| Live Linux driver | `/Users/damsleth/Code/linux/drivers/hid/apple-dockchannel-hid/apple_dockchannel_hid.c` | + `patches/t6040-dockchannel-trackpad-fw.patch` |

Tools: `nm`/`otool` (kernelcache is fully symbolised — 487k symbols), `ipsw`
for the fileset walk, `radare2 5.9.8` for bulk disassembly, plus a Python
annotator that resolves `adrp`/`add` string literals and chained-fixup vtable
slots. Every vtable-slot identification below was cross-checked against the
**PAC diversifier** in the calling `movk xN, #imm, lsl 48`, so the slot→symbol
mapping is verified, not guessed.

The MTP firmware is an arm64 `MH_PRELOAD` Mach-O at offset `0x50` inside the
`rkosftab` container; `vmaddr = fileoff + 0xFFF000` for the whole image.

**Note on a red herring in the brief:** the strings `resetInterface`,
`resetInterfaceHandler`, `resetInterfaceState` *are* present in this
kernelcache, but they belong to `AppleBCMWLAN*` / `IO80211*` / `WCL*`, not to
the HID transport. `AppleHIDTransport*` spells the operation `resetDevice`.
Searching for the wrong token would have led nowhere.

## Which classes matter

`com.apple.driver.AppleHIDTransportFIFO` holds the DockChannel transport:

- `AppleHIDTransportDeviceFIFO` — provider is `AppleDockChannelDevice`.
- `AppleHIDTransportProtocolSCMFIFO` — the wire protocol. This is the direct
  analogue of `apple_dockchannel_hid.c`.
- `AppleHIDTransportInterface` (base kext) — one per interface; owns power
  state, bootloader, AHTFunction sequences.
- `AppleHIDTransportManagement` — subclass of `AppleHIDTransportInterface`
  representing the `comm`/management interface (`kInterfaceTypeManagement`).

## The complete comm command table (both sides agree)

Decoded from the MTP firmware's own dispatch switch at `0x0104f0a0`
(`comm_cr.c`), corroborated by every `setReportWithInterface()` call site in
`AppleHIDTransportProtocolSCMFIFO`:

```
0x0104f0a0  ldrb w8, [x19, 8]      ; payload byte 0 = report ID
0x0104f0a4  cmp  w8, 0x40 -> 0x104f370   COMM_CR_PWR_REQ_SET
0x0104f0ac  cmp  w8, 0x41 -> 0x104f404   COMM_CR_PWR_REQ_GET
0x0104f0b4  cmp  w8, 0x42 -> 0x104f3c8   reset interface
0x0104f0bc  cmp  w8, 0x91 -> 0x104f108   release shared memory
0x0104f0c4  cmp  w8, 0x95 -> 0x104f274   register shared memory (firmware)
0x0104f0cc  cmp  w8, 0xb4 -> 0x104f224   enable interface
0x0104f0d4  cmp  w8, 0xc1 -> 0x104f0dc   (ack/no-op)
            else          -> 0x104f44c   unsupported
```

The request frame the firmware sees is exactly our `struct dchid_subhdr`:

| offset | field | our name |
|---|---|---|
| `x19[0]` | flags (`0x80` feature/set, `0x81` feature/get, `0x40`/`0x41` output) | `flags` |
| `x19[1]` | unk | `unk` |
| `x19[2..3]` | payload length (u16) | `length` |
| `x19[4..7]` | return code (u32, written on reply) | `retcode` |
| `x19[8..]` | payload, byte 0 = report ID | payload |

That the length check at `x19[2]` yields 2 for `0xb4`, 4 for `0x41`, 15 for
`0x91` and 16 for `0x95` — matching macOS's `len` argument at each
`setReportWithInterface()` call site exactly — is what confirms this offset
interpretation.

| Report | Length | Payload | macOS sender |
|---|---|---|---|
| `0x40` | **9** | `{0x40, 0x02, iface, state, phase, u32 status}` | `setInterfacePowerWillChange` / `setInterfacePowerHasChanged` |
| `0x40` | 4 | `{0x40, 0x01, iface, state}` | `setInterfacePower` (**not accepted by J614s**) |
| `0x41` | 4 | `{0x41, 0x01, iface, 0}` then GET | `getInterfacePower` |
| `0x42` | 3 | `{0x42, 0x01, iface}` | `resetDevice` |
| `0x91` | 15 | `{0x91, type, 0, u64 addr, u32 size}` | `releaseSharedMemory` |
| `0x95` | 16 | `{0x95, type, 0, iface, u64 addr, u32 size}` | `registerSharedMemory` |
| `0xb4` | 2 | `{0xb4, iface}` | `AppleHIDTransportManagement::descriptorComplete` |

Device→host events (MTP firmware side): `0xf0` init/descriptor,
`0xf1` ready `{0xf1, iface, 0, 0}` (emitter at `0x0104ef6c`),
`0xa0` GPIO command, `0xa2` reset request `{0xa2, iface}` (emitter at
`0x0104efc8`, logs `"%hhu Reset Request: %u"`; macOS handles it in
`AppleHIDTransportManagement::handleResetRequest`). **We do not handle `0xa2`.**

## Q1 — the exact post-upload bytes

### What Apple sends

`AppleHIDTransportProtocolSCMFIFO::performCBORBootload(AppleHIDTransportInterface*)`
at `0xfffffe00094ac354`, fully decoded:

1. `bl = interface->getBootloader()` (iface vt+0xa70, div `0xb155`); cast to
   `AppleHIDTransportBootloaderCBOR` — else `kIOReturnError`.
2. If `!interface->supportsMemoryDumpState()` (vt+0xab8, div `0x46c4`):
   `createAndRegisterMemoryDumpSharedMemory(iface, bl->getMemoryDumpLevel(), bl->getReservedMemoryDumpSize())`.
3. `data = bl->getEncodedFirmware()` (CBOR vt+0xb38, div `0x93cb`).
4. `buf = _sharedMemoryManager->createSlaveBuffer(data->getLength(), 3, 0, 0)`.
5. `copyDataToSlaveBuffer(data, buf)`.
6. **`registerSharedMemory(iface, buf, buf->getLength(), /*type=*/2)`**
   (`mov w4, #2` at `0xfffffe00094ac634`) → report `0x95`.
7. `_sharedMemorySegments->setObject(buf)`; `bl->clearEncodedFirmware()`.
8. **`interface->setPower(kAIDPowerStateOff /*0*/)`** (iface vt+0x918, div `0x3d12`,
   `mov w1, #0` at `0xfffffe00094ac6d0`).
9. **`interface->setPower(kAIDPowerStateOn /*2*/)`** (`mov w1, #2` at `0xfffffe00094ac6fc`).
10. Log `"Waiting for ready report."` (`0xfffffe00074c4c04`), release `buf`, return 0.

The `0x95` message body, at `registerSharedMemory` (`0xfffffe00094a8a3c`):

```
0xfffffe00094a8af8  mov  w8, 0x95
0xfffffe00094a8afc  strb w8,  [sp, 0x50]   ; [0] = 0x95
0xfffffe00094a8b00  strb w19, [sp, 0x51]   ; [1] = type  (2 for firmware)
0xfffffe00094a8b3c  strb w0,  [sp, 0x53]   ; [3] = interface->getInterfaceId()
0xfffffe00094a8b40  strb wzr, [sp, 0x52]   ; [2] = 0
0xfffffe00094a8b44  stur x23, [sp, 0x54]   ; [4..11] = u64 slave address
0xfffffe00094a8b48  str  w22, [sp, 0x5c]   ; [12..15] = u32 size
0xfffffe00094a8b58  mov  w2, 0x95          ; reportID
0xfffffe00094a8b5c  mov  w4, 0x10          ; length = 16
0xfffffe00094a8b60  bl   setReportWithInterface(_management, 0x95, buf, 16)
```

That is **byte-identical to our `dchid_send_firmware()` struct**, `unk1 = 2`
included: `unk1` is the shared-memory *type* (log: `"Shared memory of type %d
registered for interface %d (%s) successfully"`), and 2 is the firmware type.
`unk2` is a hard zero.

`setPower()` reaches the wire through
`AppleHIDTransportInterface::setPowerGated` → one of two methods selected by
the interface's `_powerMethod` (offset `0xe1`), read from the **`PowerMethod`**
property in `AppleHIDTransportInterface::init` at `0xfffffe000943c0c4`
(default 1 when the property is absent, assert
`_powerMethod >= kPowerMethodTypeAtomic && _powerMethod < kPowerMethodTypeCount`):

- **method 1, Atomic** → `setPowerGatedAtomic` → `protocol->setInterfacePower(iface, state)`:

```
0xfffffe00094ad82c  mov   w8, 0x140
0xfffffe00094ad830  str   w8,  [sp, 0x2c]  ; [0]=0x40 [1]=0x01 [2]=0x00 [3]=0x00
0xfffffe00094ad86c  strb  w0,  [sp, 0x2e]  ; [2] = getInterfaceId()
0xfffffe00094ad870  strb  w20, [sp, 0x2f]  ; [3] = state
0xfffffe00094ad880  mov   w2, 0x40         ; reportID
0xfffffe00094ad884  mov   w4, 4            ; length = 4
0xfffffe00094ad888  bl    setReportWithInterface(_management, 0x40, buf, 4)
```

- **method 2, WillHas** → `setPowerGatedWillHas` →
  `protocol->setInterfacePowerWillChange(iface, state)` (protocol vt+0x950,
  div `0xde1c`), then the host-side work, then
  `setInterfacePowerHasChanged(iface, state, status)` (vt+0x958, div `0x3a2c`):

```
; WillChange, 0xfffffe00094ada5c
mov   w8, 0x240 ; sturh -> [0]=0x40 [1]=0x02
strb  w0,  [sp,0x39]   ; [2] = interfaceId
strb  w20, [sp,0x3a]   ; [3] = state
strb  wzr, [sp,0x3b]   ; [4] = phase 0
stur  wzr, [sp,0x3c]   ; [5..8] = u32 status 0
mov   w2, 0x40 ; mov w4, 9        -> setReportWithInterface(..., 0x40, buf, 9)

; HasChanged, 0xfffffe00094adc60
mov   w8, 0x240 ; sturh -> [0]=0x40 [1]=0x02
strb  w0,  [sp,0x49]   ; [2] = interfaceId
strb  w21, [sp,0x4a]   ; [3] = state
mov   w8, 1 ; strb -> [sp,0x4b] ; [4] = phase 1
stur  w20, [sp,0x4c]   ; [5..8] = u32 status (host-side result, 0 on success)
mov   w2, 0x40 ; mov w4, 9        -> setReportWithInterface(..., 0x40, buf, 9)
```

### Answers

- **How many bytes:** 9 for the form J614s accepts (4 for the legacy form).
- **The second byte is a version, not a length and not a subcommand.** Proved
  by `getInterfacePower`'s assertion string
  `"request.version == PowerRequest::Version::Vers1"` at `0xfffffe00074c5401`,
  and by the MTP firmware's `"Unsupported power state version %hhu!"`. Our `1`
  is `Vers1`; J614s wants `2`.
- **Which interface index:** the byte at payload offset 2 is the **target**
  interface's `getInterfaceId()` — the multi-touch interface. The message is
  *delivered to* the management/comm interface (`this->_management`, field
  `+0x730`), which is exactly what `dchid_comm_cmd()` does. Our driver is
  correct here; the console line "command 0x40 to iface 0 (comm)" is just
  `dchid_cmd()` naming the transport interface it wrote to.
- **State values:** `AHTPowerState` decoded from the name table at
  `0xfffffe00080a6cb0` (6 entries; `kAHTPowerStateCount == 6`, enforced by
  `getInterfacePower`'s `cmp w8, 6 / b.hs`):

```
0 Off    1 Sleep    2 On    3 Reset    4 Pre-Reset Memory Dump    5 Post-Reset Memory Dump
```

  So our `0` then `2` is **Off then On, which is right**. The state values were
  never the problem. The MTP firmware's own touch interface prints the same
  names (`SLEEP`, `RESET`, `PRE_RST_MEMDUMP`, `POST_RST_MEMDUMP` at
  `0x0105cccb`).

## Q2 — does Apple wait or poll between upload and reset?

**No delay, no status poll, no handshake between the `0x95` and the power
requests.** `performCBORBootload` issues `0x95`, then `setPower(Off)`, then
`setPower(On)` back to back on the command gate. Each `setReport` is itself
synchronous — `setReportGated` sleeps on `waitForControlComplete()` until the
coprocessor's control-report ack with the matching transfer ID arrives — but
there is no *extra* wait inserted by the caller.

What Apple waits for is **after** the power-on: the log line
`"Waiting for ready report."` and then the device-initiated
**ready event `0xf1`**. That is `EVENT_READY` in our driver, and
`dchid_open()` already blocks on `wait_for_completion_timeout(&iface->ready,
START_TIMEOUT_MS)`. **Our wait is in the right place already.** On macOS the
corresponding host path is `AppleHIDTransportInterface::handleDeferredBootload`
(`0xfffffe0009446f2c`), the only caller of `protocol->handleBootload()`
(protocol vt+0x930, div `0x15b3`), which runs the bootload on the workloop and
then calls `interface->ready()` (iface vt+0xa28, div `0x43da`).

One real difference: with `PowerMethod == 2` the *host* is expected to do work
between the two phases — `AHTFunctionSequence::runSequence()` for the
`power-sequence` / `reset-sequence` / `*-memory-dump-sequence` ARM function
sequences, `captureMemoryDump()`, and `AppleHIDTransportInterface::setInterfacePower(bool)`
— and then report the result in the `HasChanged` status word. For a plain
bring-up with no configured sequences that work is empty and status 0 is the
correct thing to send.

## Q3 — which bootloader variant, and are there extra upload commands?

Two distinct bootloader objects exist and must not be confused:

- **Device-level:** `AppleHIDTransportDeviceFIFO::newBootloader()`
  (`0xfffffe00094a3698`) instantiates `AppleHIDTransportBootloaderRTBuddy`
  (GOT slot `0xfffffe00080b1b68`). That is the *MTP coprocessor's own* image
  (`J614S_MtpFirmware`, loaded by iBoot) — not our concern.
- **Interface-level:** `AppleHIDTransportInterface::start()` builds a class
  name with `snprintf(buf, 0x40, "AppleHIDTransportBootloader%s", <bootloader-type>)`
  at `0xfffffe000943c768`, where `<bootloader-type>` comes from the
  **`bootloader-type`** registry/ADT property (string at `0xfffffe00074b732d`).
  `AppleHIDTransportProtocolSCMFIFO::performBootload` (`0xfffffe00094abc74`)
  then dispatches on the resulting object's class:

```
safeMetaCast(bl, AppleHIDTransportBootloaderCBOR)     -> performCBORBootload
safeMetaCast(bl, AppleHIDTransportBootloaderFlatPack) -> performFlatPackBootload
otherwise                                             -> kIOReturnUnsupported
                                                         ("Unsupported bootloader, skipping.")
```

For J614s multi-touch it is **`AppleHIDTransportBootloaderCBOR`**. Three
independent facts pin this down:

1. `performCBORBootload` is the only path that calls `registerSharedMemory`
   with type **2**, and the MTP firmware's `0x95` handler accepts type 2 (and
   4) only — and `performFlatPackBootload` is instead driven by
   `handleFlatPackBootloaderMessageReport`, an asynchronous device-initiated
   message flow that has no analogue in our driver and that we have never
   observed.
2. `AppleHIDTransportBootloaderCBOR` inherits `loadFirmware()` from
   `AppleHIDTransportBootloaderPassive`, and that method is literally
   `return kIOReturnUnsupported;` (`0xfffffe0009425c30`) — "passive" meaning
   the host publishes a buffer and the coprocessor pulls it, which is exactly
   the `0x95` + power-cycle shape.
3. The MTP firmware itself contains a CBOR bootloader
   (`bootloader_cbor_parser.c`, `"(*)New AFE[%d] cbor image received"`,
   `"CBOR Acquire Failure(%X)"`), and our `tpmtfw-j614s.bin` HIDF payload is
   the encoded CBOR image with a patchable interface-id byte
   (`hdr->iface_offset`).

**Are there commands before or after `0x95` that we never send?** For the
upload itself: **no.** The CBOR path is `0x95` → power-off → power-on → wait
for `0xf1`. Nothing else. What we skip is only Apple's optional decoration:
`createAndRegisterMemoryDumpSharedMemory` (another `0x95`, with a different
type, for crash dumps) and the `AHTFunction` sequences. Neither is required to
bring the interface up.

## Q3b (coordinator's question) — enable/start/report-mode, and ordering

**There is no enable, start, or set-report-mode command sent to the multi-touch
interface after the firmware upload.** The comm command set is closed
(`0x40/0x41/0x42/0x91/0x95/0xb4/0xc1`), and the only "enable" in it is `0xb4`,
which is sent **once at enumeration time, before any bootload** — from
`AppleHIDTransportManagement::descriptorComplete(AppleHIDTransportInterface*)`
at `0xfffffe000945b8a8`:

```
0xfffffe000945b8a8  mov  w8, 0xb4
0xfffffe000945b8ac  strh w8, [sp, 0x3e]   ; [0]=0xb4 [1]=0x00
0xfffffe000945b8d8  strb w0, [sp, 0x3f]   ; [1] = target getInterfaceId()
                    ... writeBytes(buf, 2) ...
0xfffffe000945b994  mov  w1, 0xb4
0xfffffe000945b998  mov  w3, 2            ; kIOHIDReportTypeFeature
0xfffffe000945b9a4  blraa -> AppleHIDTransportInterface::setReport(0xb4, memdesc, Feature)
```

Two bytes, `{0xb4, interfaceId}` — **identical to `dchid_enable_interface()`**.
And the MTP firmware's `0xb4` handler (`0x0104f224`) requires flags `0x80`,
payload length 2 (outlined check at `0x1056d7c`), and reads the interface id at
payload byte 1 — matching.

Ordering, Apple vs ours:

| Step | Apple | apple_dockchannel_hid |
|---|---|---|
| descriptor received | `handleDescriptor` → `processDescriptor` → `descriptorComplete` | `dchid_handle_init` |
| enable | `0xb4 {iface}` at descriptorComplete | `dchid_enable_interface()` in `dchid_create_interface_work()` |
| firmware register | `0x95` type 2, in `performCBORBootload` via `handleDeferredBootload` | `dchid_send_firmware()` in `dchid_start_interface()` (first open) |
| power cycle | `setPower(Off)` then `setPower(On)` | `dchid_reset_interface(iface,0)` then `(iface,2)` |
| wait | "Waiting for ready report" → `0xf1` → `interface->ready()` | `wait_for_completion(&iface->ready)` on `0xf1` |

**The ordering is the same. The gap is purely the encoding of the power
request.** So the coordinator's alternative hypothesis — that we are missing a
separate streaming-enable step — is not supported: there is no such step in the
transport protocol, and the touch pipeline in the MTP firmware
(`touch_iface.c`, `touch_mgr.c`: `"Grape interface configuration completed"`,
`"Touch interface ready"`, `"Touch MT ready"`) is driven by the interface power
transition, not by a host report. `hid-magicmouse`'s `BUS_HOST` early return is
therefore correct; the missing enable *is* the power-on that never happened.

## Q4 — where `kIOReturnBadArgument` comes from

Three independent generators, all decoded:

**(a) The one we are hitting — the MTP firmware.** `comm_cr.c`, report `0x40`
handler at `0x0104f370`:

```
0x0104f370  ldrb w8, [x19]          ; transport flags
0x0104f374  mov  w21, 0x2c2
0x0104f378  movk w21, 0xe000, lsl 16 ; w21 = 0xE00002C2 kIOReturnBadArgument
0x0104f37c  cmp  w8, 0x80
0x0104f380  b.ne 0x104f470           ; wrong flags -> w21|5 = 0xE00002C7 Unsupported
0x0104f384  ldrh w1, [x19, 2]        ; payload length
0x0104f388  cmp  w1, 9
0x0104f38c  b.ne 0x104f50c           ; -> "COMM_CR_PWR_REQ_SET unexpected payload size %hu"
0x0104f390  ldrb w1, [x19, 9]        ; version
0x0104f394  cmp  w1, 2
0x0104f398  b.ne 0x104f5c8           ; -> "Unsupported power state version %hhu!"
0x0104f39c  ldrb w20, [x19, 0xa]     ; interface id
0x0104f3a4  bl   0x104e9c0           ; table lookup, ids 0..6
0x0104f3a8  tbz  w0, 0, 0x104f670    ; -> "Unsupported interface %hhu!"
0x0104f3ac  ldrb w1, [x19, 0xb]      ; power state
0x0104f3b0  cmp  w1, 6
0x0104f3b4  b.lo 0x104f6a8           ; else -> "Unsupported power state %hhu!"
0x0104f6a8  ldrb w8, [x19, 0xc]      ; phase
0x0104f6ac  cmp  w8, 2
0x0104f6b0  b.lo 0x104f70c           ; else -> "Unsupported transition %hhu!"
0x0104f70c  x9 = *(u64*)(0x10c8fb0 + iface*0x78 + 0x628)   ; per-interface handler
0x0104f724  w2 = *(u32*)(x19+0xd)    ; status
0x0104f730  blr  x9                  ; handler(state, phase, status)
0x0104f734  cbz  w0 -> success (retcode 0)
0x0104f738  w21 += 8 -> 0xE00002CA kIOReturnIOError
```

and every one of those five rejection branches converges on:

```
0x0104f680  add  x2, sp, 0x48
0x0104f684  bl   0x1056630           ; log
0x0104f688  mov  w8, 1
0x0104f68c  str  w21, [x19, 4]       ; retcode = 0xE00002C2
0x0104f690  strh w8, [x19, 2]        ; reply payload length 1
```

Our request has length 4 and version 1, so it fails at the **very first**
check, `cmp w1, 9`. The reply carries `0xe00002c2` in the `retcode` field,
`dchid_cmd()` prints it and returns `-EIO`. That is the observed line, exactly.

There is **no second, legacy code path** for report `0x40` in this firmware: the
dispatch has one `cmp w8, 0x40` and the handler has one length check. The
four-byte version-1 request cannot succeed on J614s.

Interface-id validation for reference (`0x0104e9c0` walks the table at
`0x1066470`, stride `0x10`):

```
0 comm   1 multi-touch   2 keyboard   3 stm   4 actuator   5 tp-accel   6 mtp
```

which confirms `multi-touch == 1`, matching our `iface->index`. Two neighbouring
handlers are stricter still: `0x95` requires payload `[2] == 0` **and
`[3] == 1`** (multi-touch only) with length 16, and `0x42`/`0x41` accept only
interfaces 1 and 3.

**(b) macOS host-side, same error code, different reasons** — worth recording so
a future reader does not misattribute a log line:
- `AppleHIDTransportProtocolSCMFIFO::resetDevice(iface)` returns `0xe00002c2`
  when `iface == NULL` (`cbz x1` at `0xfffffe00094ad4b8` → `mov w21, #0x2c2`).
- `AppleHIDTransportProtocolSCMFIFO::getInterfacePower` initialises its return
  to `0xe00002c2` and keeps it when `outState == NULL` or when the reply's
  state byte is `>= 6`.
- `AppleHIDTransportInterface::setPowerGated` returns `0xe00002c2` for a power
  state outside the accepted transitions (`sub w26, w22, 0x15` at
  `0xfffffe000943f728`, from `w22 = 0xe00002d7` kIOReturnOffline), **and** for
  an unknown `_powerMethod` (`"ERROR!! Unknown power method %u"`).
- `AppleHIDTransportInterface::setPowerGatedAtomic` initialises its return to
  `0xe00002c2` and keeps it for an out-of-range state.

None of (b) can produce our failure: state 0 is always a legal request
host-side, and the code we saw arrives in the coprocessor's `retcode` field.

## Side-by-side

```
                          ours (now)                    Apple / J614s MTP
--------------------------------------------------------------------------------
enable          0xb4 {0xb4, iface}          len 2   IDENTICAL
firmware        0x95 {0x95,2,0,iface,
                      u64 addr,u32 size}    len 16  IDENTICAL (type 2 = firmware)
power off       0x40 {0x40,0x01,iface,0}    len 4   0x40 {0x40,0x02,iface,0,0,u32 0}  len 9
                                                    0x40 {0x40,0x02,iface,0,1,u32 st} len 9
power on        0x40 {0x40,0x01,iface,2}    len 4   0x40 {0x40,0x02,iface,2,0,u32 0}  len 9
                                                    0x40 {0x40,0x02,iface,2,1,u32 st} len 9
wait            wait_for_completion(ready)          "Waiting for ready report" -> 0xf1
                on EVENT_READY 0xf1                 IDENTICAL in effect
```

So: two messages become four, the version byte becomes 2, and a phase byte plus
a 32-bit status are appended. Nothing else changes.

## Recommended change

`patches/t6040-dockchannel-hid-reset-contract.patch`. Applies to
`drivers/hid/apple-dockchannel-hid/apple_dockchannel_hid.c` **after**
`t6040-dockchannel-trackpad-fw.patch` (that is the code that actually produced
the failure; the log string `"sending firmware for %s"` is its). Verified:

```
git apply t6040-dockchannel-trackpad-fw.patch
git apply --check t6040-dockchannel-hid-reset-contract.patch      # clean
git apply --check t6040-dockchannel-hid-type.patch                # still clean
git apply --check --exclude='drivers/mailbox/*' \
    t6040-dockchannel-hid-state-trace.patch                       # HID hunks still clean
```

(`t6040-dockchannel-hid-state-trace.patch`'s `drivers/mailbox/apple-dockchannel.c`
hunks do not apply to a bare tree either — that is pre-existing and unrelated to
this patch; it needs the dockchannel mailbox patches first.)

What it does:

- renames `CMD_RESET_INTERFACE` → `CMD_SET_POWER`, documents `0x41`/`0x42`;
- adds `struct dchid_power_req` (9 bytes packed) and the version/phase/state
  constants;
- rewrites `dchid_reset_interface()` — same name and signature, so the call
  sites in the trackpad-fw patch keep working — to send the version-2 pair,
  falling back to the version-1 request (once, remembered in
  `dchid_dev.power_req_v1`) if the coprocessor rejects it;
- uses `PWR_STATE_OFF` / `PWR_STATE_ON` at the two call sites instead of bare
  `0` and `2`.

The fallback exists because this driver is shared with M1/M2 machines whose MTP
firmware I could not inspect offline. On T6040 the v2 request should succeed
first try, so the fallback path — and its one `dev_err` from `dchid_cmd()` —
should never be exercised. If a maintainer dislikes that stray `dev_err` on
older SoCs, the clean fix is to plumb the raw `retcode` out of `dchid_cmd()`
and probe quietly; I kept the diff small instead.

Not recommended: sending `0x42`. It is the real reset-interface command and
Apple does **not** use it in the bootload path.

## What is decoded fact vs inference

**Decoded fact (byte- and address-level, both sides):**
- The comm command table, its report IDs, payload lengths and field layouts.
- The `0x95` message is byte-identical to ours, `unk1 = 2` is the shared-memory
  type, and the MTP accepts types 2 and 4 and requires `[2]==0`, `[3]==1`,
  length 16.
- `0x40` payload byte 1 is a **version** (`PowerRequest::Version::Vers1`), not a
  length or subcommand.
- The J614s MTP firmware requires `0x40` payload length **9** and version **2**
  and rejects anything else with `0xE00002C2` at its first check.
- Apple's version-2 form is `{0x40, 0x02, iface, state, phase, u32 status}` with
  phase 0 then phase 1, from `setInterfacePowerWillChange` /
  `setInterfacePowerHasChanged`.
- `AHTPowerState`: Off 0, Sleep 1, On 2, Reset 3, Pre/Post-Reset Memory Dump
  4/5; count 6. Our `0` then `2` is correct.
- `PowerMethod` selects Atomic (1, 4-byte) vs WillHas (2, 9-byte); default 1
  when the property is absent.
- The interface-id table: multi-touch = 1.
- `0xb4` enable is `{0xb4, iface}`, sent at descriptor-complete, i.e. before the
  bootload — same ordering as ours.
- The `0x95`→power-off→power-on→wait-for-`0xf1` sequence has no intervening
  delay, poll or handshake.
- `0xf1` ready `{0xf1, iface, 0, 0}` is device-initiated; `0xa2` reset-request
  exists and we do not handle it.

**Inference (reasoned, not directly decoded):**
- That J614s multi-touch is configured `PowerMethod = 2`. I did not find the
  property's value: it comes from the interface config dictionary
  (`"Interfaces"` array → `interfaceInfo`), which is assembled at runtime from
  the ADT/IORegistry. It is *implied* by the firmware only implementing v2 —
  otherwise macOS itself would fail the same way — but it is an inference.
- That the interface bootloader class is `CBOR` rather than `FlatPack`. Strongly
  supported (type-2 shared memory, Passive `loadFirmware`, the firmware's own
  CBOR parser, the absence of any FlatPack message traffic) but the deciding
  input is the `bootloader-type` property, which I likewise could not read
  offline.
- That pre-T6040 MTP firmware accepts the 4-byte v1 request. Implied by the
  existing driver working on M1/M2, not verified — I did not have an M1 MTP
  firmware image to disassemble. This is the sole reason the patch keeps a
  fallback.
- That nothing further is needed to make touch reports flow. The transport
  protocol contains no other enable, and the firmware's touch pipeline is
  power-driven, but I did not decode `AppleMultitouchDriver` /
  `AppleTopCaseHIDEventDriver`, so a higher-level (non-transport) report on the
  multi-touch interface itself cannot be excluded.
- The exact meaning of the `HasChanged` status word beyond "0 on success".

## What would falsify this

1. **The direct test.** Apply the patch and open the trackpad. If the two `0x40`
   pairs return 0 and an `Interface multi-touch is now ready` line follows, the
   core claim holds. If the *first* v2 request still returns `0xe00002c2`, my
   field layout is wrong somewhere and the size/version reading must be redone.
2. **A different error code.** If v2 comes back `0xe00002ca`
   (`kIOReturnIOError`) instead, the encoding is accepted and the failure has
   moved into the per-interface handler — i.e. the DMA buffer is not reachable
   through `mtp_dart`, or the CBOR payload is not what the coprocessor expects.
   That would falsify "encoding is the whole story" while confirming the
   encoding itself. Next step then: DMA reachability, as ticket 212 flagged.
3. **`0xe00002c7` (`kIOReturnUnsupported`).** Means the flags byte is not `0x80`
   — i.e. `dchid_comm_cmd`'s `HID_FEATURE_REPORT`/`REQ_SET_REPORT` encoding is
   not producing `0x80` on the wire. Cheap to instrument.
4. **Ready arrives but no motion.** Then the transport contract is satisfied and
   the remaining gap is above it — the inference in the last bullet of the
   previous section is what breaks, and the next place to look is
   `magicmouse_raw_event_mtp`'s `46 + N*30` length filter against what the
   interface actually emits.
5. **An M1/M2 regression.** If an M1 machine logs `"v2 power request rejected,
   using v1 requests"` and then works, the fallback did its job and the
   "protocol was extended after t8103" inference is confirmed. If an M1 machine
   *accepts* v2, the fallback is dead code and the version could be raised
   unconditionally.
6. **A `PowerMethod` or `bootloader-type` value from the ADT.** Dumping the
   T6040 ADT `dockchannel`/MTP interface nodes and finding
   `PowerMethod = 1`, or `bootloader-type` naming something other than `CBOR`,
   would contradict the two named inferences above — though note that the
   firmware-side length check stands regardless of what any property says.
