# T6040 hpm2: what macOS does from S0 to "sourcing VBUS to a sink" (25F84, offline RE)

Date: 2026-10-24. Author: claude (offline static RE). Ticket context: 305
"PARTIAL" outcome (tps6598x-spmi binds and reaches S0, but no VBUS).

Scope: 100% offline. No rig lease, no boot, no SPMI/SMC/PMU/MMIO transaction,
no build, nothing posted. Read-only tools only (`ipsw`, `nm`, `c++filt`,
`python3`, `grep`) over the paired 25F84 kexts, the captured J614s ADT, the
Linux tree at `4f2429104009` plus the two Wallace patches, and
`~/code/m1n1-hpm2 @ baf2c20d`.

## 0. Headline

**Between HPM power state S0 and "VBUS present on the right port" macOS issues
no VBUS, power-path, power-role or port-configuration write of any kind.** The
AP's whole post-S0 register mutation surface on this class/HAL is: the
`INT_MASK1` (`0x16`) constant, the `INT_EVENT1 -> INT_CLEAR1` (`0x14 -> 0x18`)
W1C consumption, the `SSPS` command (with argument 0, 2 or 3), and two
IOKit-bookkeeping writes to Data Control `0x50`. Sourcing is decided by the
SN201202x PD firmware under its own (flash-resident) policy once it sees a
sink's Rd. Everything Linux's signed-off envelope already does (`WAKEUP`,
reads, `SSPS -> S0`, `0x16` write, `0x18` W1C) is a superset of what macOS
does for the source path, and the only macOS operations Linux does **not**
replay (`SSPS 2`, the `0x50` writes, Apple's mask value) have nothing to do
with sourcing.

So if 305 binds, reaches S0 and still shows no VBUS, the discriminator is not
a missing write. It is the connector state the part reports, which is an R0
read set (§6), plus the four unknowns in §7 (window-width validation,
`SSPS 2` vs `0`, the unexplained live `0x07`, and the two unnamed registers
`0x5d`/`0x2c`).

Two prior conclusions are corrected along the way (§8): the HAL class that
binds on J614s is `AppleHPMDeviceHALType3`, not `Type5`; and Apple's SPMI
*write* path stages the payload at window `0xa0` and re-selects, which is not
what the Linux transport mirrors.

## 1. Sources

```text
com.apple.driver.AppleHPM          (~/code/linux-build-out/t6040-usb-kexts-25F84/)
  sha256 b6eab85a4478fe354c29d4a274fa1ea23ced1c051e3b320fdfad54d65dce381d
  __TEXT_EXEC.__text vmaddr 0xfffffe00094fac80 fileoff 0x18000 size 0x581fc
  file offset = VA - 0xfffffe00094fac80 + 0x18000 (every citation below)
  symbol cache  com.apple.driver.AppleHPM.a2s (2771 symbols)
com.apple.driver.AppleSPMI         (ipsw kernel extract from t6040-kernelcache-25F84.raw)
  sha256 31129f778926e679db8588fce6c5b43d39191e5299eb29b1bc13cfc52d32d24d
com.apple.driver.AppleARMPlatform  (same extraction; holds AppleARMSPMIDevice)
  sha256 689807c6304b63e9426e42b63e39869dfb42cae6dee4c10d097712ec414b8816
kernelcache  ~/code/linux-build-out/t6040-kernelcache-25F84.raw  (119,209,984 B,
  Darwin 25.5.0 xnu-12377.121.10~1/RELEASE_ARM64_T6041 - verified by strings)
ADT          ~/code/linux-build-out/j614s-usb-port-map-20260721.adt
  sha256 7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84
Linux        ~/code/linux @ 4f2429104009, drivers/usb/typec/tipd/{core.c,tps6598x.h}
             + patches/0001-usb-typec-tps6598x-add-SPMI-transport-for-T6040-SN20.patch
             + patches/t6040-spmi-wakeup-and-tipd-probe-diag.patch
m1n1         ~/code/m1n1-hpm2 @ baf2c20d  src/t6040_hpm2.c (the live-proven paging)
```

Method: the whole AppleHPM `__text` was disassembled once
(`ipsw macho disass --section __TEXT_EXEC.__text --cache ... --no-color`,
99,488 lines) and every vtable slot cited was decoded from `__ZTV<class>`
with the arm64e chained-fixup formula (`target = 0xfffffe0007004000 +
(raw & 0xffffffff)`, diversifier `(raw >> 32) & 0xffff`) and checked against
the `movk x16/x17, #div, lsl #0x30` at each call site. The decoded tables, a
per-function register inventory and the scripts are in
`evidence/2026-10-24-t6040-hpm2-source-vbus-re/` (derived data only; no Apple
code is committed).

Class stack on this machine (proved below, §2):

```text
AppleARMSPMIDevice (hpm2 nub, AppleARMPlatform)
  -> AppleHPMARMSPMI (bus transport, AppleHPM)
     -> AppleHPMDevice + AppleHPMDeviceHALType3 (HAL)          <- Type3, not Type5
        -> AppleTCControllerType10 (hpm-class-type 10 port controller)
```

## 2. Topology facts that gate the sequence

Captured ADT, `/arm-io/nub-spmi-a1/hpm2` (phandle 346):

```text
compatible          usbc,sn201202x,spmi
reg                 SID 0x0c (reg[0]=0x0c, type 3)
hpm-class-type      10          port-type 2        port-number 3     port-location right
rid                 2           tag-number 2       dock -> phandle 469 (/port-usb-c-3)
interrupts          11, 17, 19  interrupt-type 0, 2, 3     interrupt-parent 345 (nub-spmi-a1)
acio-parent         196 (/arm-io/acio2)   spi-flash-parent 63 (/arm-io/i2c6/uatcrt2)
NOT present:        acc-hal-type, hpm-exit-dfu
/port-usb-c-3:      dock,usb-c, acc_bm3-current-limit 1300, primary-port-id 259
```

Three facts from the kext that these properties select:

1. **HAL class.** `AppleHPMARMSPMI::publishHPMDevices` @`0xfffffe0009529024`
   (file `0x463a4`) matches `compatible` against `usbc,cd3217`,
   `usbc,sn201202x,spmi`, `usbc,cbtl1702,spmi` (@`0x9529644`..`0x952966c`).
   On the `sn201202x` match it reads `acc-hal-type` (@`0x95296dc`); if the
   property exists it builds `AppleHPMDeviceHALType5::withHPMBus`
   (@`0x9529704`), **if it is absent it builds
   `AppleHPMDeviceHALType3::withHPMBus`** (@`0x95299b4`, the `cbz x0`
   @`0x95296fc`). The ADT has no `acc-hal-type`, so hpm2 runs on **HALType3**.
   `HALType5` is a subclass of `HALType3` (its `parseInterrupts` and
   `editHPMInterruptMask` tail-call `__ZTV22AppleHPMDeviceHALType3` slots,
   @`0x950e984`/`0x950e9b8`) that only adds the USB-config wrappers
   (`0x23`/`0x24`/`0x55`) and one extra interrupt bit. `HALType3` itself
   overrides only `setHPMInterruptMask` (sets struct bit 14 then calls the
   base, @`0x9549110`), `getAndClearInterrupts`, `parseInterrupts`,
   `getMuxConfig` (`0x2a`) and `getSMPTEStatus` (`0x5b`); every other HAL
   method, including `ackDPIRQ`/`resetDataControl` on `0x50`, is the base
   `AppleHPMDeviceHAL` version (slot table in the listings directory).
   What this does *not* change: the class-10 controller's register I/O never
   goes through the HAL at all. `AppleTCController::readReg` @`0x953b050`,
   `writeReg` @`0x953b508` and `execute4Cc` @`0x953b668` dispatch on the bus
   object at `this+0xe40` through slots `+0xa18`, `+0xa10`, `+0x9a8`
   (@`0x953b11c`, `0x953b618`, `0x953b754`), which in the decoded
   `AppleHPMARMSPMI` table are `readIECSReg`, `writeIECSReg` and
   `AppleHPM::atomic4CC`. The HAL correction fixes attribution (which code is
   live, and that `0x23`/`0x24`/`0x55` are doubly unreachable); the class-10
   mutation surface is unchanged.

2. **Interrupt wiring.** `interrupt-type` values are consumed by
   `AppleHPMARMSPMI::start` @`0x9527648` (file `0x449c8`): type 2 registers
   `spmiInterruptActionSleepInt` (@`0x9527b58`..`0x9527b80`), type 3
   registers `spmiInterruptActionWakeInt` (@`0x9527bc0`..`0x9527be0`), and
   `AppleTCController::initSingleHPM` @`0x95353c4` registers type 0 as
   `hpmInterruptAction` (slot `+0xb18`). So for hpm2: IRQ 11 on
   `nub-spmi-a1` is the HPM event line, 17 the SPMI-sleep line, 19 the
   SPMI-wake line. Linux's `spmi-apple-controller.c` has no irq domain, so a
   DT `interrupts` property cannot be expressed today and tipd polls (500 ms).

3. **DFU workaround gate.** `AppleHPMARMSPMI::sendHPMReset` @`0x9529c24`
   (file `0x46fa4`) issues the prohibited `GAID` only if the ADT property
   `hpm-exit-dfu == 1` (@`0x9529cc0`) **and** MODE reads `"ADFU"`
   (@`0x9529d1c`). hpm2 has no `hpm-exit-dfu`; the path is dead on this
   machine. Listed so nobody mistakes it for a bring-up step.

## 3. The ordered sequence

Register widths are the lengths macOS passes (`w3`), except where the HAL
reads "natural length" (`readRegWithLength`, capacity `0x40`, the part
returns its own length in SPMI register `0x1f`, §3.0). `Class` is the
SPMI_SAFETY classification: **R0** read, **E1** inside the signed-off
Entry 1 driver envelope, **NEW** not in the envelope (needs CJ), **OOS** out
of scope (stop there).

### 3.0 Transport primitive (how every row below reaches the wire)

`AppleHPMARMSPMI::readRegs(reg, buf, len)` @`0xfffffe0009528464` (file
`0x457e4`), provider = `AppleARMSPMIDevice` (slots decoded from
AppleARMPlatform):

```text
register0Write(reg, flags)                      slot +0x8e0  @0x9528520   SPMI Register-0 Write = select
loop <= 1000 x 1 ms:  registerRead(0x00)         slot +0x8a8  @0x9528578   until bit7 clear and low7 == reg
registerRead(0x1f) -> actual length              slot +0x8a8  @0x95286b4   ("Actual register length ... shorter than expected")
extRegisterRead(0x20, buf, len, flags)           slot +0x8c8  @0x9528778   data window
```

`AppleHPMARMSPMI::writeRegs(reg, buf, len)` @`0xfffffe000952807c` (file
`0x453fc`), where `buf[0]` is a **length byte** prepended by `writeIECSReg`
@`0x9527e20` (file `0x451a0`: `strb w19,[x22]` @`0x9527eb0` then
`memmove(buf+1, data, len)` @`0x9527ea8`):

```text
register0Write(reg, flags)                      @0x95280f0   select
poll registerRead(0x00) until bit7 clear          @0x952814c
extRegisterWrite(0xa0, buf+1, len-1, flags)       @0x95282a4   payload at window 0xa0 (NOT 0x20); buf[0], the length byte, never goes on the wire
register0Write(reg, flags)                        @0x95282ec   second select of the same register
poll registerRead(0x00) until bit7 clear          @0x952833c
```

What is proved is the sequence: select, stage the payload at `0xa0`,
select again, poll. Whether the second select *commits* the staged bytes or
is only a completion handshake is an inference, not shown by the code.

`flags` is `0x12` or `0x02` depending on a per-bus byte (`this+0x112`); it
is an `AppleARMSPMIDevice` API option word and is not decoded here. The
Linux transport (`patches/0001-...spmi.c` `tps6598x_spmi_window_write`) and
the m1n1 path (`t6040_hpm2.c:183`) write the payload directly at `0x20` with
no re-select. That form is live-proven for a 1-byte `DATA1` and a 4-byte
`CMD1` write (ticket 095) and nothing else; see §7.1.

### 3.1 Phase A: bus bring-up, `AppleHPMARMSPMI::publishHPMDevices` @`0xfffffe0009529024` (file `0x463a4`)

Runs once per HPM nub at kext start, before any controller exists.

| # | Operation | Where | Class |
|---|---|---|---|
| A1 | `AppleARMSPMIDevice::getSPMIConfig(&cfg)` (slot `+0x888`) — no bus traffic | `0x9529098` | - |
| A2 | create `AppleHPMDevice` + HAL (Type3, §2), set `rid`/location, attach | `0x9529604`..`0x9529c14` | - |
| A3 | **`AppleARMSPMIDevice::cmdWakeup(2)` (slot `+0x900`) then `IOSleep(100)`** — SPMI `WAKEUP` to SID `0x0c`, 100 ms settle. Reached on the main path via the back-edge `b loc_90a4` @`0x9529c1c` with the attach result in `w20`. | `0x95290d0`, `0x95290d8` | **R0** (WAKEUP preamble; Linux uses 10 ms) |
| A4 | `readRegs(0x0f, 4)` FW version -> `setVersion` | `0x9529114` | R0 |
| A5 | `readRegs(0x00, 4)` VID -> `setVendorID` | `0x952917c` | R0 |
| A6 | `readRegs(0x01, 4)` DID -> `setDeviceID` | `0x95291dc` | R0 |
| A7 | `readRegs(0x05, 0x11)` UID -> `setUUID` | `0x9529240` | R0 |
| A8 | `readRegs(0x2c, 1)` -> `setRevision`; no tipd name | `0x95292a0` | R0 |
| A9 | `readRegs(0x2d, 0x34)` boot status -> `setRevisionID(byte)` | `0x952930c` | R0 |
| A10 | `AppleHPMARM::getHPMMode()` = `readRegs(0x03, 4)` -> property `"HPM Mode Register on Boot"` | `0x952935c`, `0x9546478` | R0 |
| A11 | `sendHPMReset()` — dead on hpm2 (§2.3) | `0x95293e0` | OOS (`GAID`, DFU) |
| A12 | `registerService` on the device nub | `0x9529420` | - |

A read failure sets `setI2CFailure(true)` on the device, which later makes
`AppleTCController::genericStart` latch `this+0xf6f` ("I2C Read Failed")
and `AppleTCController::writeReg` silently drop every write (`tbnz w8,#0`
@`0x953b548`). That is the only start-time "write inhibit" in the stack.

Runtime power control (RTPC, `AppleHPMARMSPMI::enterRTPC` @`0x952a208`,
`exitRTPC` @`0x952a364`): after an idle timer Apple sends
`cmdSleep(2)` (slot `+0x8f0` @`0x952a304`) to the HPM SID and later
`cmdWakeup(2)` + 100 ms (@`0x952a41c`, `0x952a4ac`). This is why a warm boot
from macOS finds the HPM asleep and every bare read returns zero until a
`WAKEUP` (tickets 093/094). It is also direct evidence that SPMI `SLEEP` to
*this* SID is routinely restored by `WAKEUP`, which SPMI_SAFETY R1 currently
lacks; recorded for CJ, not an authorization.

### 3.2 Phase B: controller start, `AppleTCControllerType10`

| # | Operation | Where | Class |
|---|---|---|---|
| B1 | `Type10::probe` requires `hpm-class-type == 10` | `0x952abc4` (`cmp w8,#0xa`) | - |
| B2 | `Type10::start` -> `AppleTCController::genericStart` (non-virtual super call) | `0x952ac9c` -> `0x9533abc` | - |
| B3 | `genericStart`: boot-args, NVRAM `boot-command`/OTA check, seeds the cached power state to **2** (`strb #2,[x19,#0xf32]` @`0x9534188`), `initCommunicationsBus` (stub), `initSingleHPM` (interrupt sources, §2.2), `setupPowerManagement(provider)` (slot `+0xae8`, 2 IOKit power states) | `0x9533abc`..`0x95345f4` | - |
| B4 | `commonStartPhase1`: **`readReg(0x01, 4)`**, compare to `"ACE1"` (`0x31454341`) -> `this+0xf45` "HPMV1" | `0x95347ec`, `0x95347f4` | R0 |
| B5 | `Type10::start` tail: `registerService(0)` | `0x952ae2c` | - |

No HPM write and no 4CC occurs in Phase B. `Type10::start` does **not** call
`AppleTCController::start`; the first port evaluation is deferred to the
power-management callback (Phase C).

### 3.3 Phase C: power on -> first port evaluation (also the exact plug-event path)

IOKit PM calls `AppleTCController::setPowerState(1)` @`0xfffffe000953a91c`
(file `0x57c9c`): `poweredStart` (slot `+0xab8`, `Type10::poweredStart`
@`0x952af00`, timers only), enable the HPM interrupt source
(`0x953abe0`), **`forcePortEvaluation`** (slot `+0xb70`, `0x953ac08`),
`messageClients(0xe3ff83e8)`. A plug interrupt later takes the same chain
from `hpmInterruptAction` @`0x9536dfc` (file `0x5417c`) with real event
bytes instead of synthetic ones.

| # | Operation | Where | Class |
|---|---|---|---|
| C1 | `getAndClearInterrupt(0x14, buf, 9)`: `readReg(0x14, 9)` then `writeReg(0x18, same 9 bytes)` (W1C) | `0x9537374`, `0x95373dc` (reg map `0x14->0x18` @`0x9537340`) | **E1** (`0x18` W1C per event) |
| C2 | `Type10::forcePortEvaluation` ORs into the **stack buffer** `raw[1] \|= 0x0d` (event bits 8, 10, 11) and `raw[7] \|= 0x08` (bit 59), then `processInterruptEvents(buf, 9)` — software only | `0x952b884`..`0x952b898`, `0x952b8d8` | - |
| C3 | `processInterruptEvents` (raw bytes, no parse) gates its reads on raw bits: bit 0 -> re-run `setInterruptMask`; bit 1 -> plug-event accounting; bit 2 -> overcurrent; bits 8\|19 -> "AppLoaded, reinit": `getBootFlags` = `readReg(0x2d, 0x40)` and `readReg(0x0f, 4)`, then force the Status, Data Status and CF VID reads (the PD-status flag `w27` is cleared @`0x95378a4`, so `0x40` is *not* read on this path); bit 10 -> `readReg(0x5f, 5)`; bit 11 -> `readReg(0x40, 5)`; bit 19 -> `hardResetHandler`; bit 44 -> `rtPanicHandler`; bit 57 -> `handleAppleUVDMEnumUpdated`; bit 63 -> `this+0xf67`. Reads performed: **`0x2d`(0x40), `0x0f`(4), `0x1a`(4) "Status Reg", `0x5f`(5) "Data Status Reg", `0x40`(5) "PD Status", `0x5e`(0x12) "CF VID Status Reg"** | `0x95376a4`..`0x95376e8` (unpack); reads @`0x9537fc0`, `0x95377c8`, `0x9537974`, `0x9537a10`, `0x9537ae0`, `0x9537ba0` | R0 |
| C4 | `processStatusRegisters` (slot `+0xb40`) -> `setCurrentModeFlags(dataStatus, status)`: `readReg(0x03, 4)` DFU gate (`"DFU"` literal compare @`0x9539358`..`0x9539374`); when STATUS bit 0 (plug) is clear the reset block runs and calls `clearDpIRQ()` = **blind `writeReg(0x50, 00 20 00 00, 4)`** | `0x9538500`, `0x953934c`, `0x953a53c`..`0x953a574` | R0 read; `0x50` write **NEW** (IOKit bookkeeping, not needed) |
| C5 | `processStatusRegisters` tail: `processModeFlags` = `readReg(0x48, 0x25)` + `readReg(0x49, 0x25)` (SOP/SOP' identity, software port objects), `handleDetectChange`, `resetDataControl()` = conditional RMW of `0x50` (reads 4 B, writes back high half if bit 13 set) | `0x95397c0`, `0x9539a90`, `0x953a6e0`/`0x953a798` | R0; `0x50` RMW **NEW** (not needed) |
| C6 | `processStatusRegisters` gate `this+0xf48`,`+0xf32!=0`,`!0xf6c`,`!0xf6d` -> `forceUSB23On(dataStatus)` (slot `+0xaf0`): `createUSB3PortObject`, `setPinConfiguration` (six software bytes + `"Pin Configuration"` property), `handleDetectChange(false/true)`, 10,000 ms USB timer, `printConnectedTransports`. **No register access.** | `0x9538568`, `0x952bf5c` | - |
| C7 | `processInterruptEvents` tail, **the only `SSPS` sites reachable on class 10**: plug present (`this+0xf46` bit 0) and not sleeping (`this+0xf59`) -> `setPowerStateHPM(0)` ("active"); no plug -> `setPowerStateHPM(2)` ("active unplugged"); sleeping -> `setPowerStateHPM(3)`. `setPowerStateHPM` = `readReg(0x20, 1)` redundancy gate, then `execute4Cc(0x08, "SSPS", &arg, 1)` = `DATA1 0x09 <- arg`, `CMD1 0x08 <- 53 53 50 53`, `atomic4CC` polls `CMD1` with `IOSleep(5)` against `"!CMD"`/`0`/`"ABRT"` | `0x9537d60`..`0x9537f30`; `0x953ad54`, `0x953adb8`; `0x9550f8c`, `0x9550fc4` | `SSPS 0`: **E1**. `SSPS 2`: **NEW** (never needed). `SSPS 3`: sleep path, OOS |

### 3.4 Phase D: framework activation, `setHPMActive` -> `setInterruptMask`

`AppleTCController::setHPMActive` @`0xfffffe000953dd4c` (file `0x5b0cc`,
slot `+0xbc0`) and its inverse `setHPMInactive` (`+0xbb8`) have **no caller
inside AppleHPM.kext** (verified by exhaustive scan for the slot, direct
`bl`, and any symbol reference such as a pointer-to-member; the only
occurrences are the function labels and vtables); they are virtual hooks
driven by the IOAccessoryManager framework. `setHPMActive` re-runs `setupPowerManagement` and then
`setInterruptMask` (slot `+0xb20`):

| # | Operation | Where | Class |
|---|---|---|---|
| D1 | `readRegWithLength(0x5d, 6)`; if the returned byte equals 5 then mask byte 5 becomes `0x10`. `0x5d` has no tipd name. | `0x95371f4`, `0x9537200`..`0x9537208` | R0 |
| D2 | **`writeReg(0x16, 8)` = `07 0d 00 00 02 00 c0 0b`** (byte 7 = `0x8b` when `this+0xf68`, the remote-wakeup flag). A fully synthesized constant; `0x16` is never read on this class. Raw event bits enabled: 0,1,2, 8,10,11, 33, 54,55, 56,57,59 (+63). | `0x9537184`..`0x9537190`, `0x953724c` | **E1** (mask write; Apple's value differs from `cd321x_data.irq_mask1`, §5) |

### 3.5 Phase E: plug -> xHCI -> "VBUS" acknowledgement

With a sink attached the PD firmware raises IRQ 11; Phase C repeats with
real event bytes, STATUS bit 0 set, `SSPS 0` (C7), mode flags, then
`forceUSB23On` publishes the USB port object. When the xHCI driver attaches,
`AppleTCController::driverStatusInterrupt` @`0x95458b4` logs
`"driverStatusInterrupt: turnOnVbus"` and calls `Type10::turnOnVbus()`
@`0x952c200` (file `0x49580`), whose entire body is: clear
`this+0xf6b` (`fWaitingForUSB`), `stopUSBTimer`, `forcePortEvaluation`
(C1-C7 again). `AppleHPMInterface::turnOnVbus` @`0x951906c` is
`mov w0,#0; ret`. `AppleTCController::setAccessoryPower` @`0x9545aec`
returns `kIOReturnUnsupported`.

### 3.6 Phase F: VBUS itself

No AP operation. Across the whole 119 MB kernelcache the only TPS-vocabulary
4CCs are `SWDF`/`SWUF` (data role, `AppleHPMInterface::roleSwap`, never
reached from the `AppleTCController` family); there is no `SWSr`/`SWSk`,
no `SRDY`, no `PP_*`/power-path command, no `SCfg` outside the LDCM
(liquid-detection) `disablePort` path, and no platform function for VBUS or
an accessory load switch (`function-*` set: `LDCM_Mux_Sel0/1`, `LDCMpower`,
`ldcmInvalid`, `challenge_crypto`, `cio_mux`, `connect_DIG`, `hdmi_hpd`,
`mux_flip_back/front`, `orientation`, `recovery_status_output`,
`usb_dconnect`, `usb_dmonitor`). `AppleHPMARM::findSMC` only looks up
`AppleSMC` for `startSMCDelayUVDM` (SMC key `0x4150....` write, UVDM timing);
it is not on the plug path. The port's `acc_bm3-current-limit = 1300` in
`/port-usb-c-3` is consumed by IOAccessoryManager power-mode accounting, not
written to the HPM.

The source decision therefore belongs to the SN201202x firmware's stored
configuration (SYSTEM_CONF `0x28` PORTINFO, Rp advertisement, Try.SRC), which
macOS reads (C3/C4 via STATUS/PD status) and never writes on this port.

## 4. Classification summary

| Class | Operations macOS performs (S0 -> sourcing) |
|---|---|
| **R0** (reads, incl. WAKEUP preamble) | `WAKEUP`+100 ms; `0x0f`(4) `0x00`(4) `0x01`(4) `0x05`(0x11) `0x2c`(1) `0x2d`(0x34/0x40) `0x03`(4) `0x14`(9, read half) `0x1a`(4) `0x5f`(5) `0x40`(5) `0x5e`(0x12) `0x48`/`0x49`(0x25) `0x20`(1) `0x5d`(6) `0x50`(4, read half of the RMW) |
| **E1** (already signed off, tickets 231/305) | `SSPS 0` via `0x09`/`0x08`; `0x16` 8-byte mask write; `0x18` 9-byte W1C per event |
| **NEW** (CJ sign-off needed; none required for sourcing) | `SSPS 2` ("active unplugged", C7); blind `0x50 <- 0x00002000` (`clearDpIRQ`, C4); conditional `0x50` RMW (`resetDataControl`, C5); Apple's mask constant instead of tipd's |
| **OOS** (touches firmware/DFU/sleep/other endpoint; stop) | `GAID` in `sendHPMReset` (DFU-gated, dead on hpm2); `AppleHPM::sleep` 4CC via `hpmIECSCommand` (system sleep); SPMI `cmdSleep(2)` (RTPC, §3.1); `SCfg` 11-byte write in LDCM `disablePort`; `EURr`/`prst` repeater reset (no caller); every firmware-update 4CC (`BFUp CFUp RFWs RFWd SFWd SFWi SFWs SFWv Gaid Grst PRGN ADFU DFUf`); `startSMCDelayUVDM` SMC write; PMU/charger: nothing in this driver touches them |

No step touches the PMU, a charger, NVRAM (the `boot-command` NVRAM *read*
in `genericStart` is a kernel registry read, not an HPM operation), or a
second SPMI endpoint.

## 5. What Linux already does, and the minimal "NEW" set

### 5.1 tipd over the SPMI transport, probe order (patched `tps6598x_probe_common`, `core.c` after `0001-...`.patch, plus `spmi.c`)

```text
spmi_command_wakeup                      WAKEUP (+10 ms after t6040-spmi-wakeup-and-tipd-probe-diag.patch)  = A3 (Apple: 100 ms)
regmap_raw_read(0x20, 1)                 diag only (same patch)                                          = R0
TPS_REG_VID 0x00 (4)                     -ENODEV on 0                                                     = A5
cd321x_switch_power_state: 0x20 (1), SSPS 0 if != 0, 0x20 (1)                                            = C7 with arg 0 (Apple only after a plug)
tps6598x_check_mode: 0x03 (4) must be APP/PTCH/BOOT                                                      = A10 / C4 read
TPS_REG_INT_MASK1 0x16 <- irq_mask1 (8 B)                                                                = D2, different value (below)
TPS_REG_STATUS 0x1a (4)                                                                                  = C3
fwnode "connector": only fwnode_usb_role_switch_get() (optional); the cd321x path never reads
                                         power-role/data-role and never calls typec_get_fw_cap (only tps25750_register_port reads data-role)
cd321x_register_port -> tps6598x_register_port: TPS_REG_SYSTEM_CONF 0x28 (4) PORTINFO -> port type      (Apple never reads 0x28 on the plug path; LDCM only)
                                         PORTINFO outside the switch (e.g. 7) -> -ENODEV = probe FAILURE, not PARTIAL (visible in dmesg)
power status 0x3f (2), data status 0x5f (4); if plug present: connect()                                  = C3
poll every 500 ms: cd321x_interrupt: 0x14 (8) -> 0x18 W1C (8) -> 0x1a; 0x3f if bit 9; 0x5f if bit 10     = C1/C3 (Apple reads 9 bytes, Linux 8)
```

Role commands: `tps6598x_dr_set` (`SWUF`/`SWDF`) and `tps6598x_pr_set`
(`SWSk`/`SWSr`) exist in `tps6598x_ops` but are reachable only from the
typec class on a userspace request; nothing in the bring-up image calls
them. `cd321x_init`/`cd321x_reset` are empty.

Event-bit agreement (raw `INT_EVENT1` bits, both sides): plug event bit 1,
status update bit 8, data-status update bit 10 are what Apple's synthetic
re-evaluation sets and what `APPLE_CD_REG_INT_PLUG_EVENT`/`_STATUS_UPDATE`/
`_DATA_STATUS_UPDATE` name. Apple's mask does **not** enable bit 9
(`APPLE_CD_REG_INT_POWER_STATUS_UPDATE`) and additionally enables 0, 2, 11,
33, 54-57, 59; Apple reads PD status `0x40` on bit 11, which tipd never
reads. In polling mode the mask value is irrelevant to what tipd sees (the
event register latches regardless), so this difference cannot cause the
PARTIAL outcome.

### 5.2 Minimal NEW set for sourcing: **empty**

Everything macOS does between S0 and sourcing that has an effect on the
part is inside Entry 1. The three NEW operations in §4 are IOKit port-object
bookkeeping (`0x50`) or the unplugged parking state (`SSPS 2`), neither of
which precedes sourcing. A Linux image that binds, reaches S0 and shows no
VBUS is therefore in one of these states, each decidable by R0 reads:

| STATUS `0x1a` fields (tps6598x.h) | Meaning | Next |
|---|---|---|
| `PLUG_PRESENT`=1, `PORTROLE`=source(1), `PP_5V0_SWITCH`=OUT(2), `VBUS_STATUS`=vSafe5V(1) | already sourcing; "no child" is a data-path problem (ticket 170) | stop R3 work |
| `PLUG_PRESENT`=0 with the stick inserted | CC detection never happened: firmware not in APP mode (`0x03`), or Rp/Rd policy disabled by `SYSTEM_CONF` PORTINFO (`0x28`), or the HPM is not the one on the right port | read `0x03`, `0x28`, `0x40` |
| `PLUG_PRESENT`=1, `PORTROLE`=sink(0), `PP_5V0_SWITCH`=disabled | firmware resolved to sink/DRP-sink; `PD_STATUS 0x40` `PORT_TYPE` and `0x28` PORTINFO say whether source is even allowed | only then is a power-role write (`SWSr`, NEW/R3) a candidate — macOS never issues it, so there is no precedent to copy |
| `PP_5V0_SWITCH`=FAULT(1) or `VBUS_STATUS`=FAULT(3) | power-path fault; hardware/rail side, outside this driver | report, stop |

### 5.3 Patch sketch (diagnostic, in-envelope; no new transaction class)

Shaped for review, not built. All reads are R0 and the only writes are the
two already in Entry 1.

```diff
--- a/drivers/usb/typec/tipd/spmi.c
+++ b/drivers/usb/typec/tipd/spmi.c
@@ tps6598x_spmi_probe
-	usleep_range(10000, 11000);
+	/* Apple's AppleHPMARMSPMI::publishHPMDevices waits 100 ms after cmdWakeup. */
+	msleep(100);
--- a/drivers/usb/typec/tipd/core.c
+++ b/drivers/usb/typec/tipd/core.c
@@ tps6598x_probe_common, after the TPS_REG_INT_MASK1 write
+	{
+		u64 mask_rb = 0;
+		u32 conf = 0, pdst = 0;
+		u16 pwr = 0;
+
+		/* R0 readbacks: window-width validation and connector state. */
+		tps6598x_read64(tps, TPS_REG_INT_MASK1, &mask_rb);
+		tps6598x_read32(tps, TPS_REG_SYSTEM_CONF, &conf);
+		tps6598x_read32(tps, TPS_REG_PD_STATUS, &pdst);
+		tps6598x_read16(tps, TPS_REG_POWER_STATUS, &pwr);
+		dev_info(dev, "mask wrote %#llx read %#llx; sysconf %#x pdstatus %#x pwr %#x\n",
+			 tps->data->irq_mask1, mask_rb, conf, pdst, pwr);
+	}
@@ tps6598x_read_status (or the connect path)
+	dev_info(tps->dev, "status %#x: plug %u conn %u portrole %u datarole %u pp5v0 %u vbus %u src %u\n",
+		 status, !!(status & TPS_STATUS_PLUG_PRESENT), TPS_STATUS_CONN_STATE(status),
+		 TPS_STATUS_TO_TYPEC_PORTROLE(status), TPS_STATUS_TO_TYPEC_DATAROLE(status),
+		 TPS_STATUS_PP_5V0_SWITCH(status), TPS_STATUS_VBUS_STATUS(status),
+		 TPS_STATUS_POWER_SOURCE(status));
```

DT: no change. `dts/t6040-j614s-dcuart-usb2-native-right-pd.dts` already
describes exactly hpm2. Its `power-role = "source"`, `data-role = "host"`
are **not consumed** by tipd on the cd321x path (§5.1): the port capability
comes from the chip's `0x28` PORTINFO, and no DT property can change the
firmware's policy or issue a command. `interrupts` stays absent (§2.2). If a write-side change is ever
wanted it is the transport, not the policy: mirror Apple's write path
(`0xa0` staging + re-select) in `tps6598x_spmi_window_write` — but only
after §7.1 says the `0x20` form is actually wrong, because the `0x20` form is
what ticket 095 proved.

## 6. The R0 read set that decides the PARTIAL case

One operation class, one endpoint, no W1C, no command (every register is
already named in SPMI_SAFETY R0 or cross-validated in
`evidence/2026-08-04-t6040-r3-boundary-closure-design.md` §2):

| Reg | Bytes | Decides |
|---|---|---|
| `0x03` | 4 | `"APP"` vs `BOOT`/`PTCH`/`DFU` |
| `0x20` | 1 | S0 reached (and, with/without the stick, §7.2) |
| `0x1a` | 4 | `PLUG_PRESENT` b0, `CONN_STATE` b3:1, `PORTROLE` b5, `DATAROLE` b6, `VCONN` b7, `PP_5V0_SWITCH` b9:8, `POWER_SOURCE` b19:18, `VBUS_STATUS` b21:20, `USB_HOST_PRESENT` b23:22 |
| `0x3f` | 2 | `CONNECTION` b0, `SOURCESINK` b1, `PWROPMODE` b3:2 |
| `0x40` | 5 | `PORT_TYPE` b5:4 (sink-source / sink / source / source-sink) |
| `0x28` | 4 | `PORTINFO` = conf & 7 (what the firmware is configured to be) |
| `0x5f` | 5 | `DATA_CONNECTION` b0, `USB2_CONNECTION` b4, `USB_DATA_ROLE` b7 |
| `0x2d` | 0x34 | boot status: dead-battery flag b2, EEPROM-present b3 |
| `0x1f` (SPMI) | 1 per select | the part's own length for each of the above (§7.1) |

## 7. Explicit unknowns and the bounded R0 read that resolves each

1. **Window-width validity of Linux writes.** Apple writes payloads at SPMI
   window `0xa0` and re-selects; Linux writes at `0x20` without re-select
   (§3.0). The `0x20` form is live-proven only for a 1-byte `DATA1` and a
   4-byte `CMD1` (ticket 095). The 8-byte `0x16` and 9-byte `0x18` writes in
   Entry 1 have never been exercised on this part through `0x20`.
   Resolver: after the mask write, **read back `0x16`** (patch sketch §5.3)
   and compare; also read SPMI `0x1f` after selecting `0x16`, `0x14`,
   `0x18`, `0x1a`, `0x3f`, `0x40`, `0x28`, `0x5f` to record the part's own
   lengths against the widths tipd assumes (Apple reads `0x14` as 9 bytes,
   tipd reads/clears 8).
2. **`SSPS 0` with no sink vs Apple's `SSPS 2`.** macOS parks the HPM in
   state 2 while unplugged and only moves to 0 on a plug (C7); Linux forces
   0 at probe regardless. Whether state 0 with no partner changes the
   firmware's Rp advertisement or source policy is unknown. Resolver: read
   `0x20` and `0x1a` with the stick out, then with it in, under the Linux
   driver (R0; no `SSPS 2` issued — that stays NEW).
3. **The live `0x07` power state** (ticket 094, pre-`SSPS`) is never a macOS
   `SSPS` argument (only 0, 2, 3 are issued on class 10; `0x20` is never
   written). Still unexplained; it is plausibly a status encoding of the
   RTPC-slept state. Resolver: read `0x20` immediately after `WAKEUP` on a
   cold boot vs a warm boot from macOS, before any `SSPS`.
4. **Registers `0x5d` (6 B, read before the mask write, `==5` branch) and
   `0x2c` (1 B, "revision")** have no tipd name and no decode in the corpus.
   Resolver: read both (R0) and record the bytes; no write depends on them
   in Linux.
5. **Which raw event bits the SN201202x actually raises on attach.** Apple
   enables 0,1,2,8,10,11,33,54-57,59; tipd acts on 1,8,9,10. If the part
   signals attach only on a bit tipd ignores, polling still sees it (any
   non-zero event triggers a status read), so this cannot block sourcing,
   but it would make `cd321x_connect` late. Resolver: log the raw 9-byte
   `0x14` before the W1C in the poll handler (R0 read already performed).
6. **`flags` `0x12`/`0x02` on every Apple SPMI transfer** (`this+0x112`)
   and the argument `2` to `cmdWakeup`/`cmdSleep` are `AppleARMSPMIDevice`
   API options, not decoded. The Linux controller sends plain SPMI frames and
   that is live-proven (305 run 6: controller bound, reads ACK); no
   resolver needed unless a transfer starts failing.

## 8. Corrections to earlier evidence

1. `evidence/2026-07-24-t6040-hpm-class10-host-transition.md` ("constructs
   `AppleHPMDeviceHALType5`") and
   `evidence/2026-08-04-t6040-r3-boundary-closure-design.md` §3.3 ("HAL
   generation undecidable because `acc-hal-type` is absent") are superseded:
   the absence of `acc-hal-type` *is* the selector, and it selects
   **HALType3** (§2.1). Consequences: `0x23`/`0x24`/`0x55` are unreachable by
   HAL class as well as by `hpm-class-type`; the live `0x50` implementations
   are now identified (base-HAL `ackDPIRQ`, a blind `0x40`-byte write with
   byte 1 = `0x20`, and base-HAL `resetDataControl`, a high-half RMW), and
   the byte-preserving `HALType4` pair is not in play on J614s. Identifying
   the live implementation does not prove bit 13's W1C-vs-RW semantics;
   that stays unproven. The class-10 mutation surface is unchanged (§2.1).
   SPMI_SAFETY's R3 register list still names `0x23`, `0x24`, `0x55`; that
   edit remains CJ's.
2. The transport-patch comment and
   `evidence/2026-08-18-t6040-tps6598x-spmi-review.md` remark 1 describe
   Apple as polling SPMI `0x1f` "after select"; the exact protocol is: poll
   `0x00` for the selector, then read `0x1f` as the **actual register
   length**, then read the window at `0x20`; writes stage at `0xa0` and
   commit by re-selecting (§3.0). "Mirrors AppleHPMARMSPMI::readRegs" is
   accurate for reads only.
3. `AppleHPMDeviceHAL::parseInterrupts` offsets (used by the
   `AppleHPMInterface` family) are not what `AppleTCController` consumes;
   `processInterruptEvents` takes the raw 9 bytes (§3.3 C3). Any future bit
   table for class 10 must be written against raw bits.
4. Confirmed unchanged from the 2026-07-25 and 2026-08-04 passes: no VBUS
   primitive in either direction, `turnOnVbus` is a driver-ready ack,
   `0x14` is never written, the `0x16` mask is a synthesized constant,
   `0x20` is never written, `SWDF`/`SWUF` are the only TPS 4CCs in the
   image.

## 9. Explicitly not done here

No SPMI_SAFETY, ticket, DT or patch file was edited; nothing was built,
nothing ran on the rig, nothing was drafted for external posting. §5.3 is a
sketch for review. `SSPS 2`, any `0x50` write, `SWSr`/`SWSk`, `SCfg`, and
every OOS item in §4 remain outside the signed-off envelope and are not
proposed.
