# T6040 ticket 096 — R3 boundary closure design (offline)

Date: 2026-08-04
Ticket: 096 (R3 right-port HPM2 host transition), with a strategic verdict on 170
Author: claude (offline static RE)
Status of this document: **DESIGN DOCUMENT. No artifact was built or run.**

## Offline attestation

100% offline static analysis. No rig lease was acquired. Nothing under
`scripts/t6040-boot-*`, `scripts/t6040-debugusb-*` or `scripts/t6040-bootcap-*`
was executed. No SPMI, SMC, MMIO, PMU or charger operation was issued. No
hardware was touched, nothing was chainloaded, nothing was posted externally.
Only read-only tools ran: `ipsw macho disass`, `nm`, `strings`, `python3` over
the captured ADT and the extracted kexts, and `grep`/`sed` over the Linux tree.

## Headline

**All three named boundaries are answerable, and the answer changes the route.**

| # | Boundary | Verdict |
|---|---|---|
| 1 | reg `0x50` save/restore | **PARTLY CLOSED, and MOOT** — restoring bits 16..31 is Apple-precedented and safe; the low 16 bits (incl. bit 13) are **NOT CLOSABLE STATICALLY**; the recommended design never writes `0x50` at all |
| 2 | `IntClear1` `0x18` W1C | **CLOSED — Wallace must not clear events.** Live-proven that a 4CC command completes with `0x18`/`0x16` untouched, and Linux's `tipd` takes ownership of both at bind. Design never touches `0x14`(write)/`0x16`/`0x18` |
| 3 | cross-layer teardown order | **CLOSED BY DESIGN** — a forward-only, non-mutating design needs no teardown; the power cycle is the documented inverse, and Apple sequences nothing on detach anyway |

**But the more important finding is that the question R3 was built to answer can
be answered at class R0, which existing policy already permits.** The
`SN201202x` register map is now cross-validated against upstream Linux's
`apple,cd321x` support, and logical registers `0x1a` / `0x40` / `0x3f` / `0x5f` /
`0x28` report, read-only, whether the right port is already sourcing VBUS and
what power/data role it holds. If it is already sourcing, R3 is unnecessary and
the entire remaining blocker is the data path (ticket 170).

**Route recommendation: run the R0 connector-state read first; do the ticket-170
data-path DT/driver work in parallel; and if a role/PD write is ever needed, do
it with the reviewed upstream `tipd` driver over an SPMI regmap — not with
hand-rolled 4CC writes from m1n1.** A draft R3 ticket body is included, gated
behind the R0 result, and marked not runnable.

---

## 1. Sources and tooling

```text
kernelcache (reference)  /Users/damsleth/Code/linux-build-out/t6040-kernelcache-25F84.raw
                         119,209,984 bytes, macOS 26.x build 25F84

kext under analysis      /Users/damsleth/Code/linux-build-out/t6040-usb-kexts-25F84/
                           com.apple.driver.AppleHPM
                           sha256 b6eab85a4478fe354c29d4a274fa1ea23ced1c051e3b320fdfad54d65dce381d
                           __TEXT_EXEC.__text vmaddr 0xfffffe00094fac80 size 0x581fc
                           __TEXT.__const     vmaddr 0xfffffe00074e31b0
                           __DATA_CONST.__const addr 0xfffffe00080bb3e8 size 0x21598
                         com.apple.driver.AppleHPM.a2s  (symbol cache, used by ipsw)
                         com.apple.driver.AppleTypeCRetimer

captured ADT             /Users/damsleth/Code/linux-build-out/j614s-usb-port-map-20260721.adt
                         606,208 bytes
                         sha256 7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84
                         (matches docs/SPMI_SAFETY.md identity gate)

Linux tree               /Users/damsleth/Code/linux @ 4f2429104009
m1n1 HPM worktree        /Users/damsleth/Code/m1n1-hpm2 @ baf2c20d  (branch codex/t6040-hpm2-status-r0)

tools present            ipsw, r2, objdump, nm, strings, python3
tools absent             rizin, llvm-objdump (on PATH; llvm-* exist under brew --prefix llvm)
```

Disassembly command (whole text section, symbolised):

```text
ipsw macho disass --section __TEXT_EXEC.__text \
  --cache .../com.apple.driver.AppleHPM.a2s --no-color \
  .../com.apple.driver.AppleHPM     ->  99,488 lines
```

Vtable decoding reused the method recorded in
`evidence/2026-07-25-t6040-hpm2-rollback-evidence.md`:
`entry_VA = __ZTV<class> + 0x10 + slot`, `target = 0xfffffe0007004000 + (raw &
0xffffffff)`, `PAC diversifier = (raw >> 32) & 0xffff`, self-checked against the
call site's `movk x16/x17, #imm, lsl #0x30`.

---

## 2. New primary decode: the register map is now cross-validated

This is the load-bearing new result. It was not available to the 2026-07-24/25
passes, and it reframes every boundary.

Apple's `AppleHPM` and upstream Linux's `drivers/usb/typec/tipd` are two
independent implementations of the **same** PD-controller register map. Upstream
`tipd` carries first-class `apple,cd321x` support
(`drivers/usb/typec/tipd/core.c:2024`). Its register numbers
(`core.c:30-54`) line up with every register Apple's class-10 path touches:

| Reg | upstream `tipd` name | Apple `AppleHPM` use (decoded) |
|---|---|---|
| `0x03` | `TPS_REG_MODE` | `setCurrentModeFlags` DFU gate literally compares `"DFU"` — a mode **string** register |
| `0x08` | `TPS_REG_CMD1` | every `execute4Cc` / `atomic4CC` command register |
| `0x09` | `TPS_REG_DATA1` | command payload |
| `0x14` | `TPS_REG_INT_EVENT1` | `getAndClearInterrupt` read half |
| `0x16` | `TPS_REG_INT_MASK1` | `setInterruptMask` |
| `0x18` | `TPS_REG_INT_CLEAR1` | `getAndClearInterrupt` W1C half |
| `0x1a` | `TPS_REG_STATUS` | `AppleHPMDeviceHAL::getStatus` @`0xfffffe000954b7fc` |
| `0x20` | `TPS_REG_SYSTEM_POWER_STATE` | `setPowerStateHPM` redundancy read; the live `0x07` observation |
| `0x24` | `TPS_REG_USB4_STATUS` | `getUSBStatus` — read-only, never written. **Explains the asymmetry** |
| `0x28` | `TPS_REG_SYSTEM_CONF` | `disablePort` reads it and issues 4CC `SCfg` = **S**ystem **C**on**f**i**g** |
| `0x40` | `TPS_REG_PD_STATUS` | `AppleHPMDeviceHAL::getPDStatus` @`0xfffffe000954ba78`, `mov w1,#0x40` @`0xfffffe000954baec` |
| `0x48` | `TPS_REG_RX_IDENTITY_SOP` | `processModeFlags` reads `0x48`/`0x49`, 37 bytes |
| `0x5e` | `TPS_REG_CF_VID_STATUS` | `AppleHPMDeviceHAL::getCFVidStatus` @`0xfffffe000954bc40` |
| `0x5f` | `TPS_REG_DATA_STATUS` | `AppleHPMDeviceHAL::getDataStatus` @`0xfffffe000954b398`, `mov w1,#0x5f` @`0xfffffe000954b40c` |

Two independent confirmations that this is the same protocol, not a coincidence:

1. **The invalid-command sentinel matches byte for byte.** Upstream:
   `#define INVALID_CMD(_cmd_) (_cmd_ == 0x444d4321)` (`core.c:144`) — that is
   ASCII `"!CMD"` little-endian. Apple's `AppleHPM::atomic4CC`
   @`0xfffffe0009550c9c` compares the command result against the literal
   `"!CMD"` at @`0xfffffe0009550f8c` (`ldr d0,[x8,#0x278]`), then against zero,
   then against `"ABRT"` @`0xfffffe0009550fc4`. Upstream's
   `tps6598x_exec_cmd_tmo` (`core.c:401-465`) implements exactly that sequence:
   read `CMD1`, refuse `-EBUSY` unless zero or `!CMD`, write `DATA1` payload,
   write the 4CC to `CMD1`, poll `CMD1` until zero, then read the `DATA1` result
   byte and map `TPS_TASK_TIMEOUT`/`TPS_TASK_REJECTED`.

2. **The `STATUS` bit layout matches.** `AppleHPMDeviceHAL::setStatus(uchar*
   raw, uchar len, HPMType1Status*)` @`0xfffffe000954b8f4` is the pure software
   decoder for the `0x1a` read. With `w20 = *(u32*)raw`:

   ```text
   0xfffffe000954b924  cmp w2, #0x5 ; b.lo        ; else log "Abnormal Status Length"
   0xfffffe000954b948  bfxil w8, w20, #0, #1      ; out.b0 bit0 <- raw bit 0
   0xfffffe000954b94c  and  w9, w20, #0xe
   0xfffffe000954b954  cmp  w9, #0x8              ; raw bits[3:1] == 4 ?
   0xfffffe000954b958  csel w9, wzr, w10(#2), eq  ; out.b0 bit1 = (conn_state != 4)
   0xfffffe000954b95c  lsr  w10, w20, #0x3
   0xfffffe000954b964  and  w10, w10, #0xc        ; out bits2,3 <- raw bits 5,6
   0xfffffe000954b960  lsr  w11, w20, #0x5
   0xfffffe000954b968  and  w11, w11, #0x30       ; out bits4,5 <- raw bits 9,10
   0xfffffe000954b970  lsr  w11, w20, #0x15
   0xfffffe000954b974  and  w11, w11, #0x40       ; out bit6  <- raw bit 27
   ```

   Against upstream `tps6598x.h:17-83`: raw bit0 = `TPS_STATUS_PLUG_PRESENT`;
   raw bits[3:1] = `TPS_STATUS_CONN_STATE_MASK` with value 4 =
   `TPS_STATUS_CONN_STATE_NO_CONN_R_A` (Apple treats exactly that value as
   "not connected"); raw bit5 = `TPS_STATUS_PORTROLE` (power role); raw bit6 =
   `TPS_STATUS_DATAROLE`; raw bit9 = top bit of `TPS_STATUS_PP_5V0_SWITCH_MASK`
   (`GENMASK(9,8)`), set iff the 5 V power path is `OUT` or `IN` rather than
   disabled/fault; raw bit10 = top bit of `TPS_STATUS_PP_HV_SWITCH_MASK`; raw
   bit27 = `TPS_STATUS_BIST`. Every field lands where upstream says it does.
   The 4-bit-summary shape (Apple keeps only the "switch is engaged" bit of each
   2-bit power-path field) is itself evidence that Apple's silicon has TI's
   power-path encoding.

**Consequence.** We now have a *named, cross-validated* read-only view of the
connector's electrical state on this exact part — and every register in it is
already permitted by `docs/SPMI_SAFETY.md` class R0.

### 2.1 ADT topology, freshly re-derived

Parsed the captured J614s ADT directly (no rig, no m1n1 proxy). All four HPM
nodes and their parents:

```text
/arm-io/nub-spmi-a0/hpm0  usbc,sn201202x,spmi  class 10  port-type 2  SID 0x0c rid 0  left-back
                          acio-parent -> /arm-io/acio0      spi-flash-parent -> /arm-io/i2c6/uatcrt0
/arm-io/nub-spmi-a0/hpm1  usbc,sn201202x,spmi  class 10  port-type 2  SID 0x0a rid 1
                          acio-parent -> /arm-io/acio1     (no port-location property)
/arm-io/nub-spmi-a0/hpm5  usbc,sn201202x,spmi  class 11  port-type 17 SID 0x08 rid 5
                          (no port-location, no acio-parent, empty transports-supported)
/arm-io/nub-spmi-a1/hpm2  usbc,sn201202x,spmi  class 10  port-type 2  SID 0x0c rid 2  right   <-- allowlisted
                          acio-parent -> /arm-io/acio2      spi-flash-parent -> /arm-io/i2c6/uatcrt2
                          dock        -> /device-tree/port-usb-c-3
```

Three new facts:

- **hpm2 and hpm0 are configuration twins.** Identical `compatible`,
  `hpm-class-type = 10`, `port-type = 2`, `features-supported {1,2,3}`,
  `transports-supported {1,2,3,4,5}`, `interrupts {0x0b,0x11,0x13}`,
  `feature-ldcm-arch-version 4`, `feature-ldcm-hw-version 1`,
  `usbc-update-protocol 2`, and even the same SID `0x0c` on their respective
  controllers. hpm0 is the left-back/DebugUSB port, which demonstrably works as
  a full-function USB-C port. Whatever makes hpm0 source VBUS for a bus-powered
  accessory applies identically to hpm2.
- **`acio-parent` pins the layer mapping:** `hpm2 -> acio2`, which carries
  `atc-phy-parent` and `port-number = 3`. That is the exact HPM ↔ ACIO ↔ ATC PHY
  ↔ `usb-drd2` chain the ticket-170 DT needs.
- **`spi-flash-parent` pins the retimer:** the right port's ATC retimer is
  `/arm-io/i2c6/uatcrt2` (`compatible = "atcrt"`, I2C6 address `0x1a`), and the
  HPM is its firmware path. Left-back is `uatcrt0` (`0x18`).
- `/device-tree/port-usb-c-3` (`compatible = "dock,usb-c"`) carries
  `acc_bm3-current-limit = 1300` — a **1300 mA accessory current limit**. The
  right port is designed to source power to bus-powered accessories.

And the negative that matters for ticket 170, re-confirmed independently: **no
HPM/PD controller sits on any I2C bus.** The complete I2C child inventory is
audio codecs (i2c1/2/3), `sd-card` (i2c4/0x20), the three ATC retimers
(i2c6/0x18-0x1a) and `pcon0` (i2c8/0x08). Every PD controller is an SPMI child
of `nub-spmi-a0`/`nub-spmi-a1`. The `macvdmtool` string
`i2c0@9B040000/.../hpm0/AppleHPMARMI2C` is not J614s topology — `AppleHPM`
contains both an `AppleHPMARMI2C` and an `AppleHPMARMSPMI` transport class
(vtables at `0xfffffe00080be858` and `0xfffffe00080cda50`), and this machine
instantiates the SPMI one.

---

## 3. Boundary 1 — register `0x50` save/restore

### 3.1 What `0x50` is

Register `0x50` is the PD controller's **Data Control** register. Apple's own
strings name it: `"AppleHPMDeviceHAL::setBRDataControl - WARNING: Abnormal Data
Control Length = 0x%x"`, `"AppleTCController::resetDataControl(@0x%x) - clearing
Data Control"`, and the struct type `HPMBRDataControl`. It pairs with `0x5f`
`DATA_STATUS` (read) and `0x55` `DataControl2` (`HPMType1DataControl2`).

Natural length: `AppleHPMDeviceHALType5::setBRDataControl` @`0xfffffe000950eac8`
sanity-checks the length and logs "Abnormal" unless it is in `{3,4,5,6}`:

```text
0xfffffe000950eaec  sub w8, w2, #0x7
0xfffffe000950eaf0  cmn w8, #0x4
0xfffffe000950eaf4  b.hi   -> log "Abnormal Data Control Length"
```

The class-10 path always uses **4 bytes** (`AppleTCController::clearDpIRQ` and
`::resetDataControl` both `mov w3, #0x4`).

Note also, correcting a possible misreading of the name:
`AppleHPMDeviceHALType5::setBRDataControl(uchar* raw, uchar len,
HPMBRDataControl* out)` is a **pure software decoder**, not a register write. It
extracts `out.u16 = (out.u16 & 0x0f00) | (raw & 0xf0ff)` @`0xfffffe000950eb0c-
0xfffffe000950eb1c` and `out.b2 bit2 = raw bit 18`
@`0xfffffe000950eb20-0xfffffe000950eb34`. Raw bits 8..11 are not part of that
decode. No `writeReg` occurs in it.

### 3.2 Does any Apple path perform a read-modify-write of `0x50`? **Yes — four, in two different shapes.**

The 2026-07-25 inventory found two (`clearDpIRQ`, `resetDataControl`). A
complete re-scan of every `mov w1, #0x50` site in the 99,488-instruction listing
finds **six** call sites across four functions, in two HAL generations:

| Function | VA | Shape |
|---|---|---|
| `AppleTCController::clearDpIRQ()` | `0xfffffe000953a4a4` | **blind** 4-byte write of `0x00002000` (`mov w8,#0x2000; str w8,[x0]` @`0xfffffe000953a53c`; `mov w1,#0x50` @`0xfffffe000953a564`; `mov w3,#0x4`; slot +0xb08) |
| `AppleTCController::resetDataControl()` | `0xfffffe000953a610` | **RMW, high half preserved** |
| `AppleHPMDeviceHAL::ackDPIRQ()` | `0xfffffe000954c020` | **blind** — zeroed 0x40 buffer, `mov w8,#0x20; strb w8,[sp,#0x1]` @`0xfffffe000954c04c`, `writeReg(0x50, sp, 0x40)` @`0xfffffe000954c080` |
| `AppleHPMDeviceHAL::resetDataControl()` | `0xfffffe000954c0ac` | **RMW, high half preserved** |
| `AppleHPMDeviceHALType4::ackDPIRQ()` | `0xfffffe00095023b8` | **byte-preserving RMW, sets only bit 13** |
| `AppleHPMDeviceHALType4::resetDataControl()` | `0xfffffe00095024b8` | **byte-preserving RMW, clears only bit 13** |

`AppleTCController::resetDataControl` (class-10 reachable), exact sequence:

```text
0xfffffe000953a6a0  bl   _IOMallocData          ; 4 bytes
0xfffffe000953a6ac  str  wzr, [x0]
0xfffffe000953a6d0  mov  w1, #0x50
0xfffffe000953a6d8  mov  w3, #0x4
0xfffffe000953a6e0  blraa                        ; slot +0xaf8 readReg(0x50, buf, 4)
0xfffffe000953a6e4  ldrb w8, [x20, #0x1]
0xfffffe000953a6e8  tbz  w8, #0x5  -> return 0    ; word bit 13 clear => write nothing
0xfffffe000953a76c  strh wzr, [x20]               ; zero the LOW 16 bits
0xfffffe000953a788  mov  w1, #0x50
0xfffffe000953a790  mov  w3, #0x4
0xfffffe000953a798  blraa                        ; slot +0xb08 writeReg(0x50, buf, 4)
```

`AppleHPMDeviceHALType4::resetDataControl`, the byte-preserving variant:

```text
0xfffffe0009502528  mov  w1, #0x50
0xfffffe0009502534  blraa                        ; readRegWithLength(0x50, sp+0x10, &len)
0xfffffe0009502538  cbnz w0  -> bail
0xfffffe000950253c  ldrb w8, [sp, #0x11]
0xfffffe0009502540  tbnz w8, #0x5  -> continue    ; only if bit 13 set
0xfffffe0009502554  and  w8, w8, #0xffffffdf      ; CLEAR bit 13, preserve every other bit
0xfffffe0009502558  strb w8, [sp, #0x11]
0xfffffe000950255c  ldrb w3, [sp, #0xf]           ; the length the read reported
0xfffffe0009502584  blraa                        ; writeReg(0x50, sp+0x10, len)
```

and its `ackDPIRQ` twin, which **sets** the same bit by RMW:

```text
0xfffffe0009502428  mov  w1, #0x50               ; readRegWithLength(0x50, ...)
0xfffffe000950243c  ldrb w8, [sp, #0x11]
0xfffffe0009502440  orr  w8, w8, #0x20           ; SET bit 13, preserve every other bit
0xfffffe0009502444  strb w8, [sp, #0x11]
0xfffffe0009502478  mov  w1, #0x50
0xfffffe000950247c  mov  w3, #0x40
0xfffffe0009502488  blraa                        ; writeReg(0x50, ...)
```

### 3.3 What that settles, and what it does not

**Settled: bits 16..31 can be written back from a saved read.** Two independent
class-reachable functions (`AppleTCController::resetDataControl` and
`AppleHPMDeviceHAL::resetDataControl`) read `0x50`, zero only the low halfword,
and **write the upper halfword back exactly as read**. Restoring bits 16..31
from a saved word is therefore Apple's own operation, not an invention. Since
those are the only bits Apple ever writes back as read `1`s, a restore of the
form `write(0x50, saved & ~0x0000ffff)` writes a `1` to no bit that Apple does
not also write a `1` to in the same situation.

**Not settled: bit 13, and hence the low halfword.** The two HAL generations
are mutually inconsistent under either hypothesis:

- Under **W1C** semantics for bit 13, `ackDPIRQ` (write `1`) is a correct
  acknowledge, `AppleTCController::resetDataControl` (write `0` to bit 13, zero
  the rest) correctly clears the *configuration* bits and leaves the ack bit
  alone — but `AppleHPMDeviceHALType4::resetDataControl` becomes a complete
  no-op (it writes `0` to bit 13 and every other bit back unchanged), which is
  absurd for a function guarded on that bit being set.
- Under **ordinary read/write** semantics, `HALType4`'s set/clear pair is
  coherent, but then `AppleTCController::clearDpIRQ` writing `0x00002000` under
  the log `"clearing DP IRQ"` is *setting* the bit it claims to clear.

Both cannot be true of one silicon behaviour, so **bit 13's semantics differ by
HPM/HAL generation.** I attempted to decide which HAL binds to a class-10 SPMI
node on J614s and **could not**: the selecting property is `acc-hal-type`
(string present in `AppleHPM`), and it **does not exist anywhere in the captured
606,208-byte ADT** — the four HPM nodes carry `hpm-class-type` but no
`acc-hal-type`, so the HAL class is chosen from a source outside the ADT
(IOKit personality matching / a per-part table not in this corpus).

**Verdict for boundary 1: NOT CLOSABLE STATICALLY as posed**, for the low
halfword only, with the reason named precisely (undecidable HAL generation +
mutually inconsistent implementations). **PARTLY CLOSED** for bits 16..31.

**And moot for the recommended design**, which never writes `0x50`. See §6.1 for
why nothing in a host transition requires it: `clearDpIRQ` is reached only from
`setCurrentModeFlags(0,0)`, i.e. from Apple's *IOKit port-object* mode-flag
reconciliation, which a Linux/m1n1 implementation does not and must not
replicate. For the record: if a design ever needed to leave `0x50` in a
known-good state, `0x00002000` is Apple's own value, written blind on every
class-10 mode-flag reset and therefore proven non-damaging on this part.

---

## 4. Boundary 2 — the `IntClear1` `0x18` W1C position

### 4.1 The question, restated correctly

The W1C at `0x18` is reached from Apple's R3 chain only because
`forcePortEvaluation()` calls `getAndClearInterrupt(0x14 -> 0x18, 9)`
(`AppleTCController::getAndClearInterrupt` @`0xfffffe000953727c`, register
pairing at @`0xfffffe0009537318-0xfffffe0009537340`). `forcePortEvaluation` is
Apple's way of nudging *its own IOKit state machine*; the ORs it applies land on
a stack buffer and are handed to `processInterruptEvents`, as already proven.

So the real question is not "how do we make `0x18` reversible" — it has no
inverse and cannot have one — but **"does a host transition require any
interrupt-state write at all?"**

### 4.2 Decision: **no. Wallace must not clear events, and must not touch `0x16`.** Three independent grounds.

**(a) Live proof on this exact endpoint.** Ticket 095
(`evidence/2026-07-24-t6040-hpm2-r2-ssps-s0-result.md`) executed a full 4CC
command on right-HPM2 with an audited binary containing **exactly two extended
writes**: one byte `0x00` to `DATA1` `0x09` and four bytes `53 53 50 53`
(`SSPS`) to `CMD1` `0x08`. No `IntMask`, no `IntClear`, no W1C, no event path
was linked at all. The command completed, and the power state moved `0x07 ->
0x00`. **The 4CC command channel demonstrably does not require interrupt-state
manipulation on this part.** Any further 4CC — including a role swap — inherits
that.

**(b) The command-completion protocol is polled, not interrupt-driven.** Both
implementations poll `CMD1`: Apple's `AppleHPM::atomic4CC` @`0xfffffe0009550c9c`
loops on the command register with `IOSleep(5)` between reads
(@`0xfffffe0009550f10`) and decides on `"!CMD"` / zero / `"ABRT"`; upstream's
`tps6598x_exec_cmd_tmo` (`core.c:428-441`) polls `TPS_REG_CMD1` until it reads
zero with a 1000 ms timeout. Neither consults `INT_EVENT1`. Clearing `0x18` is
housekeeping for a driver that services an interrupt line — which m1n1 does not
have wired for this endpoint.

**(c) Linux takes ownership of both registers at bind, unconditionally.**
`tps6598x_probe` writes the mask itself — `tps6598x_write64(tps,
TPS_REG_INT_MASK1, tps->data->irq_mask1)` — and for `apple,cd321x` that value is
`APPLE_CD_REG_INT_POWER_STATUS_UPDATE | APPLE_CD_REG_INT_DATA_STATUS_UPDATE |
APPLE_CD_REG_INT_PLUG_EVENT`. Its handler `cd321x_interrupt` reads
`TPS_REG_INT_EVENT1` and immediately `tps6598x_write64(tps, TPS_REG_INT_CLEAR1,
event)`. So the eventual Linux owner **overwrites the mask and consumes events
by design**. Preserving Apple's mask has no consumer; restoring it would be
undone by the first bind. Conversely, any mask value m1n1 leaves behind is
irrelevant to Linux, and any event state m1n1 destroys would have been destroyed
by `cd321x_interrupt` on its first interrupt anyway.

**Verdict for boundary 2: CLOSED.** The design leaves interrupt state entirely
to Linux. `0x14` may be **read** (R0-permitted, and a bare read clears nothing —
only the paired `0x18` write does). `0x16` and `0x18` are **never written**. This
removes the whole R2 inheritance that `docs/SPMI_SAFETY.md` currently attaches
to R3.

---

## 5. Boundary 3 — cross-layer teardown order

### 5.1 The design that needs none

The 2026-07-25 pass established the structural negative: Apple performs no
cross-layer teardown on USB-C detach. The HPM reconciles software port objects
and notifies clients; the PHY tears down when its last client closes
(`AppleTypeCPhy::close` @`0xfffffe0009daa45c` -> `configureUSB2`/`configureLanes`
-> `eusb2phy_shutdown` @`0xfffffe0009dbe77c`, a known-off sequence, not an
inverse); the eUSB2 repeater reset (4CC `EURr` via platform function `prst`,
`AppleTCController::repeaterReset` @`0xfffffe000953c684`) has **no caller in the
corpus**; xHCI orders against the PHY only on driver stop
(`AppleT8150USBXHCI::stopThreadCallGated` @`0xfffffe000b02e710`). There is no
order to copy.

The correct conclusion is not "invent one". It is **do not create the state that
would need tearing down.** Concretely:

1. **Do not mutate any layer other than the command register.** The design's
   entire write surface is `DATA1 0x09` and `CMD1 0x08`. Nothing in `0x16`,
   `0x18`, `0x50`, `0x23`, `0x24`, `0x55`; nothing in the eUSB2 repeater;
   nothing in the ATC PHY; nothing in ACIO/DWC3/xHCI. With no mutated layer
   there is no composition to unwind.
2. **Do not attempt an in-band rollback of a PD-firmware policy decision.** If a
   role swap is ever issued and the port ends up in an odd state, the documented
   inverse is the one already sanctioned everywhere else in this workflow: a
   warm reboot, then a power cycle. Per
   `evidence/2026-07-25-t6040-r3-risk-calibration.md`, the SN201202x holds
   role/VBUS/mask/event state in volatile RAM, `AppleHPM` re-initialises it every
   macOS boot, and the exhaustive write inventory contains no flash/OTP/patch
   path — the whole-kernelcache 4CC scan found no `FLrr`/`FLwr`/`FLem`/`FLad`/
   `FLvy` at all. A power cycle is therefore a *complete* inverse for everything
   the design can touch, not a partial one.
3. **Let Linux compose the layers.** In the target end state the four layers are
   four DT nodes with four drivers, and the composition order is expressed by
   `phys`/`resets`/`usb-role-switch`/`typec-mux` links, reviewed upstream. That
   is a better artifact than any order we could reconstruct from a corpus that
   does not contain one.

### 5.2 The one ordering fact worth keeping

The HPM-layer order *is* fully specified and bidirectional via
`AppleTCControllerType10::overrideHPMMode(enforce, keepRoleAndOrientation,
dataStatus, status)` @`0xfffffe000952c3bc` (slot +0xbb0, IOKit selector
`0xe3ff843f`), with pre-transition values readable from `this+0xee8`/`this+0xef0`.
It is recorded for completeness, but it is **software** ordering inside Apple's
port-object model, and its teardown branch is precisely what drags in the blind
`0x50` write via `setCurrentModeFlags(0,0)` -> `clearDpIRQ()`. A Wallace design
should not transliterate it. That is the same conclusion as §3.3 from the other
direction.

**Verdict for boundary 3: CLOSED BY DESIGN.** No cross-layer teardown order is
needed, because a forward-only, single-register-surface design leaves no layer
mutated, and the power cycle is a complete documented inverse for the volatile
state that remains.

---

## 6. The reframing: the deciding measurement is R0, not R3

### 6.1 Why R3 was over-scoped

Everything that made R3 look hazardous — `0x50`, `0x16`, `0x18`, the mode flags,
the detect re-advertisement, the cross-layer order — came from modelling R3 as
*"reimplement `AppleTCControllerType10`'s host transition"*. But that chain is
overwhelmingly **IOKit port-object bookkeeping**: `setCurrentModeFlags` zeroes
cached transport bytes and clears VID/PID caches; `processModeFlags`
@`0xfffffe0009539728` reads `0x48`/`0x49` and performs **no register write at
all**, then calls `removeUSB3PortObject`/`removeUSB2PortObject`/
`removeDPPortObject`/`removeTBTPortObject` and `messageClients(0xe0000130)`;
`setPinConfiguration` @`0xfffffe000953b7a8` writes six *software* bytes and
publishes an `OSDictionary` property; `handleDetectChange` calls out to
`IOAccessoryManager`, which is not even in this kext.

None of that is a hardware prerequisite for the connector to source VBUS or to
be a DFP. In a Linux world the equivalent work is done by
`drivers/usb/typec/`, `usb-role-switch`, `typec-mux` and `dwc3`. Transliterating
Apple's IOKit reconciliation into m1n1 would import all of its irreversibility
and none of its purpose.

### 6.2 The R0 experiment that decides whether R3 is needed at all

`docs/SPMI_SAFETY.md` class R0 already permits **any** logical register read on
`/arm-io/nub-spmi-a1/hpm2`, at natural length, with the WAKEUP preamble. With
§2's cross-validated map, that is enough to answer the actual question.

With the passive bus-powered stick plugged into the **right** port and DebugUSB
on left-back/HPM0 untouched, read:

| Reg | Name | What it decides |
|---|---|---|
| `0x03` | `MODE` | firmware is in APP mode (not `BOOT`/`PTCH`/`DFU`) — a precondition for trusting anything else |
| `0x1a` | `STATUS` (4 B) | `PLUG_PRESENT` b0; `CONN_STATE` b[3:1]; **`PORTROLE` b5 (source/sink)**; **`DATAROLE` b6 (DFP/UFP)**; `VCONN` b7; **`PP_5V0_SWITCH` b[9:8]** (`2`=OUT ⇒ sourcing); **`VBUS_STATUS` b[21:20]** (`0`=vSafe0V, `1`=vSafe5V); `POWER_SOURCE` b[19:18]; `USB_HOST_PRESENT` b[23:22] |
| `0x3f` | `POWER_STATUS` | `CONNECTION` b0, `SOURCESINK` b1, `PWROPMODE` b[3:2] |
| `0x40` | `PD_STATUS` | `PORT_TYPE` b[5:4]: sink-source / sink / source / source-sink |
| `0x28` | `SYSTEM_CONF` | `PORTINFO` = conf & 7 — the port capability upstream uses to pick `TYPEC_PORT_SRC`/`DRP`/`SNK` (`core.c:1206-1230`) |
| `0x5f` | `DATA_STATUS` | `DATA_CONNECTION` b0, `USB2_CONNECTION` b4, `USB3_CONNECTION` b5, `USB_DATA_ROLE` b7 |
| `0x20` | `SYSTEM_POWER_STATE` | current HPM power state (was `0x07` pre-095, `0x00` after) |
| `0x14` | `INT_EVENT1` | pending events, **read only** — a bare read clears nothing |
| `0x50` | `DATA_CONTROL` | free evidence for boundary 1 (records the live word without writing it) |

This is **one operation class** (R0), one endpoint, no W1C, no data-window
write, no command. It needs no new policy class and no new risk argument.

**Decision table:**

- **`PP_5V0_SWITCH == OUT` and `VBUS_STATUS == vSafe5V` and `PORTROLE ==
  source`** ⇒ the port is already sourcing VBUS autonomously. **R3 is
  unnecessary.** The 2026-07-21 "root hubs but no child device" result is a
  data-path failure, and the whole remaining blocker is ticket 170
  (atcphy + retimer + dwc3 + DARTs). This is the outcome the evidence predicts,
  for four independent reasons: macOS contains **no** VBUS primitive in either
  direction (proof by exhaustion, ticket 176), so sourcing must be autonomous PD
  firmware policy; `AppleHPMLDCM::getVbusPresent` @`0xfffffe00095112e0` is a
  stub returning false and `setVbusPresent` @`0xfffffe00095112b4` only logs, so
  the AP does not even track it; hpm2 is a configuration twin of the working
  hpm0 (§2.1); and `port-usb-c-3` declares a 1300 mA accessory current limit.
- **`PORTROLE == sink` / `VBUS_STATUS == vSafe0V` with `PORT_TYPE`/`PORTINFO`
  showing a DRP** ⇒ the firmware has not yet resolved to source. Then the
  relevant question is whether a **data**-role swap (`SWDF`) is even the right
  lever — it is not a power-role command — and the honest next step is the
  reviewed `tipd` driver's PD policy engine (§7), not a one-shot m1n1 4CC.
- **`PORTINFO` says sink-only** ⇒ the port will never source under any 4CC we
  are allowed to issue; changing it means writing `SYSTEM_CONF 0x28` via `SCfg`,
  which is a far larger decision and out of scope here.

An unrun R0 candidate already exists at `m1n1-hpm2` `baf2c20d`
(`src/t6040_hpm2.c`, ticket 178), but it reads **only** `STATUS 0x1a`
(`TPS_REG_STATUS`, @ line 347) plus `POWER_STATE 0x20`. It should be widened to
the table above before it burns a rig cycle. Note that the same file already
carries an unapproved R3/R4 `SWDF`/`SWUF` class (from `e41cf6e4`, the
`write_logical_reg(CMD1, role_swap_4cc)` block); **that class must not be linked
into the R0 candidate**, per the "one operation class per experiment" rule.

---

## 7. Strategic answer: does ticket 170's DT route make the hand-rolled R3 path unnecessary?

**Partly — and where it does not, it still beats hand-rolling.** Verified,
not assumed:

**Verified present in our tree.**
- `drivers/usb/typec/tipd/core.c:2024` — `{ .compatible = "apple,cd321x",
  &cd321x_data }`. Full `cd321x` support: `cd321x_data`, `cd321x_init`,
  `cd321x_interrupt`, `cd321x_read_data_status`, `cd321x_register_port` with DP
  and TBT altmodes and a `typec-mux`, `cd321x_switch_power_state`,
  `cd321x_reset`.
- **The exact 4CCs Wallace wanted to hand-roll are already implemented,
  reviewed and upstream.** `tps6598x_dr_set` (`core.c:475-489`):
  `const char *cmd = (role == TYPEC_DEVICE) ? "SWUF" : "SWDF";` then
  `tps6598x_exec_cmd(tps, cmd, 0, NULL, 0, NULL)`. `tps6598x_pr_set`
  (`core.c:505-519`): `"SWSk"` / `"SWSr"`. Both are wired into
  `tps6598x_ops` (`core.c:535`), and `typec_cap.ops = &tps6598x_ops` is set on
  the `cd321x` path too (`core.c:1203`, reached from `cd321x_register_port` ->
  `tps6598x_register_port`). The command engine
  (`tps6598x_exec_cmd_tmo`, `core.c:401-465`) is a faithful implementation of
  `AppleHPM::atomic4CC`, down to the `"!CMD"` sentinel (§2).
- `drivers/phy/apple/atc.c` exists.
- `arch/arm64/boot/dts/apple/t6040-usb3-right-data-path.dtsi` already stages the
  right-port data path (`atcphy2_t6040`, `compatible = "apple,t6040-atcphy"`,
  44 native banks, retimers inventoried and disabled, `usb-role-switch` +
  `role-switch-default-mode = "host"`), all `status = "disabled"`.

**Verified absent / blocking.**
1. **`tipd` is an I2C-only driver.** `module_i2c_driver(tps6598x_i2c_driver)`
   (`core.c:2046`), `tps6598x_probe(struct i2c_client *client)` (`core.c:1741`),
   `tps->regmap = devm_regmap_init_i2c(client, ...)` (`core.c:1769`).
   `apple,cd321x` is in the **OF** match table but only ever reached through an
   I2C bus walk. Our PD controllers are SPMI (§2.1). **So `apple,cd321x` cannot
   bind on T6040 as shipped**, and a DT node alone will not fix it.
2. **`atc.c` matches only `apple,t8103-atcphy`** (`atc.c:2299-2301`), and per
   sol's 2026-07-29 correction the t8103/t8122 fallback must **not** be added —
   the existing probe resets and writes the incompatible five-window layout, the
   T6040 event bank is at `0x392800000` while the fallback expects core-relative
   `0x393000000`, and T6040 has 17 tunables with `CIO4PLL_CORE`/TB5 versus
   t8132's 44. A T6040 compatible plus a layout-correct probe path is real
   driver work (`patches/0001-phy-apple-add-experimental-T6040-USB2-only-slice.patch`
   is the current staged answer).

**The good news is structural.** `struct tps6598x` holds a `struct regmap
*regmap` (`core.c:168`) and *every* register access goes through
`regmap_raw_read`/`regmap_raw_write` (`core.c:244-271`). The driver's PD logic
is already transport-agnostic; only `probe` is I2C-bound. Making it work on
T6040 is therefore:

- an SPMI regmap implementing the `SN201202x` selector protocol (write logical
  register number to SPMI reg 0, poll selector `0x00`, extended read/write the
  data window `0x20`) — the exact protocol `m1n1-hpm2`'s
  `select_logical_reg`/`read_logical_reg`/`write_logical_reg` already implements
  (`src/t6040_hpm2.c:143-184`);
- an SPMI device driver shim that builds that regmap and calls the shared
  `tps6598x` core;
- a DT node under the SPMI controller.

This is precisely what yuka's `tps6598x-spmi` branch attempts
(`docs/SPMI_SAFETY.md` records it at `dcc5f1bccbbe986099f218e9057f7fa99a0b1fe2`,
and equally records why it is not an approved artifact today: generic
iteration, automatic power-state commands, interrupt mutation, recovery
behaviour).

### 7.1 Verdict on the strategic question

- **For the data path: yes, the DT route replaces nothing less than everything.**
  atcphy + retimer + dwc3 + two DARTs is required whatever happens to the PD
  question, it is already staged and compile-checked, and it needs no PD decode.
  It should proceed independently.
- **For VBUS/role: the DT route does not work as shipped, but it is still the
  better destination.** `apple,cd321x` will not bind over SPMI today. But if a
  role/PD write is ever needed, doing it through the upstream `tipd` core over an
  SPMI regmap is **strictly better** than a hand-rolled m1n1 4CC, because: the
  4CC sequences are identical but reviewed; the command engine already handles
  `!CMD`, `ABRT`, `TIMEOUT`, `REJECTED` and timeouts; the role change is
  expressed through `usb-role-switch`/`typec` so the data path follows
  automatically; failures are Linux driver bugs recovered by reboot rather than
  m1n1-time SPMI experiments on a machine with one recovery tether; and it is
  upstreamable.
- **Therefore the hand-rolled R3 4CC path is not the way forward.** It is not
  forbidden by anything I found, and §8 records its minimal shape, but it has no
  advantage over the DT/driver route and it consumes attended rig cycles on the
  one machine.

---

## 8. Draft R3 ticket body — **REQUIRES CJ SIGN-OFF — NOT RUNNABLE**

Recorded because boundaries 2 and 3 are closed and boundary 1 is closed by
avoidance, so a minimal R3 *is* now specifiable. **I am not asking for sign-off
on it, and I recommend it not be run.** Its value is unproven until the R0 read
in §6.2 has run: if that read shows the port already sourcing VBUS, this ticket
should be deleted rather than approved.

> ```json
> {
>   "seq": "<odd, claude-allocated>",
>   "slug": "hpm2-r3-swdf-dfp-request",
>   "needs": "rig + CJ attendance",
>   "state": "draft-requires-cj-signoff",
>   "runnable": false,
>   "track": "usb",
>   "priority": "P2",
>   "desc": "R3 minimal right-port data-role request. HARD PRECONDITION: the ticket-178 R0 connector-state read (STATUS 0x1a / PD_STATUS 0x40 / POWER_STATUS 0x3f / DATA_STATUS 0x5f / SYSTEM_CONF 0x28 / MODE 0x03) has run and shows the port NOT sourcing VBUS and NOT already DFP. If it shows the port already sourcing, this ticket is void."
> }
> ```
>
> **Endpoint (fail-closed identity gate, all must match or abort):**
> `/arm-io/nub-spmi-a1/hpm2`; `compatible = usbc,sn201202x,spmi`;
> `hpm-class-type = 10`; `port-type = 2`; `port-number = 3`;
> `port-location = right`; `rid = 2`; SID `0x0c`; controller
> `/arm-io/nub-spmi-a1`, `compatible = aapl,spmi`, `gen = 3`, reg0
> `0x309198000 / 0x4000`; ADT sha256
> `7a92e6e4d16cb1b5a5858beb22b22acc8e5ed4b36ed5d5ccde9b251f1da55c84`.
>
> **Operation class:** R3 (connector data role), and **only** R3. No R2
> operation is linked; no R1 `SSPS` is linked unless the R0 read shows the HPM
> not in S0, in which case this ticket is withdrawn and re-scoped rather than
> extended.
>
> **Complete register surface — every register touched, with its exact operation:**
>
> | Reg | Name | Operation | Bytes |
> |---|---|---|---|
> | SPMI `0x00` | selector | write (logical-register select), then bounded poll | 1 |
> | SPMI `0x20` | data window | extended read / extended write of the selected register | ≤ 4 |
> | `0x03` | `MODE` | **read** — abort unless APP mode | natural |
> | `0x1a` | `STATUS` | **read** — pre-state and post-state capture | 4 |
> | `0x40` | `PD_STATUS` | **read** — pre-state | natural |
> | `0x5f` | `DATA_STATUS` | **read** — pre-state and post-state | natural |
> | `0x14` | `INT_EVENT1` | **read only**, never cleared | 9 |
> | `0x08` | `CMD1` | **read** (must be `0` or `!CMD`, else abort `-EBUSY`), then **write** `53 57 44 46` (`SWDF`), then bounded poll until `0` | 4 |
> | `0x09` | `DATA1` | **read** result byte after completion; write only if a payload is required (`SWDF` takes none — write nothing) | 1 |
>
> Registers **never** touched: `0x16`, `0x18`, `0x23`, `0x24`, `0x28`, `0x50`,
> `0x53`, `0x55`, `0x70`. No W1C anywhere. No firmware/DFU 4CC ever
> (`DFUf BFUp CFUp RFWs RFWd SFWd SFWi SFWs SFWv Gaid GAID Grst PRGN ADFU`
> are all rejected by construction, not by convention). No eUSB2 repeater
> (`EURr`/`prst`), no ATC PHY, no DWC3, no xHCI, no DART, no storage path linked.
>
> **Fixture:** DebugUSB on **left-back / HPM0**, untouched, not addressed by the
> binary at all (`nub-spmi-a0` is not allowlisted and must not appear in the
> image). The **only** device on the right port is the known passive
> **bus-powered USB memory stick**. No charger, no powered dock, no second host,
> no externally powered source anywhere on the right port, before, during or
> after.
>
> **Stop conditions (all fail closed, no retry, no escalation to another class):**
> identity-gate mismatch; SError; any FIFO / selector-poll / command-poll
> timeout (every wait bounded and logged); `CMD1` non-zero and not `!CMD` before
> issue; `CMD1` reads `!CMD` after issue (command not recognised — stop, do not
> substitute another 4CC); `DATA1` result `TPS_TASK_TIMEOUT (1)` or
> `TPS_TASK_REJECTED (3)`; any leftover FIFO entry; loss of the recovery
> transport; any access outside the manifest. On stop: log the exact opcode,
> SID, logical register, length, data, response and boundary, then halt — do not
> attempt an in-band inverse.
>
> **Rollback / recovery contract (stated honestly, this is the whole point):**
> there is **no in-band inverse and none is claimed**. `SWUF` is the data-role
> counterpart, not a proven inverse of the port state, and issuing it is a
> *second* R3 operation requiring its own approval — it is deliberately not part
> of this ticket. The contract is:
> 1. the binary mutates exactly two registers, `CMD1` and (if ever needed)
>    `DATA1`, both of which are command-channel registers whose content is
>    consumed by the firmware and does not persist as configuration;
> 2. all resulting state — role, VBUS, orientation, event and mask state — lives
>    in the SN201202x's volatile RAM. The exhaustive class-10 write inventory and
>    the whole-kernelcache 4CC scan found **no** flash, OTP, patch-bundle or
>    other non-volatile write path (no `FLrr`/`FLwr`/`FLem`/`FLad`/`FLvy`
>    anywhere in the 119 MB image);
> 3. therefore the documented inverse is **warm reboot, then a full power cycle
>    if the warm reboot does not restore it**. Per
>    `evidence/2026-07-25-t6040-r3-risk-calibration.md` this is inside the normal
>    bring-up loop, not an incident;
> 4. expect a full shutdown after the run regardless of outcome, and a fresh
>    healthy-proxy check plus `rig-lease.sh recovered <agent>` before any
>    subsequent experiment (ticket 118 precedent).
>
> **Gates:** rig lease held; CJ present; CJ approval of the exact artifact
> hash; independent source and machine-code review confirming the write surface
> is exactly `{CMD1}` (and `DATA1` only if a payload is used); pinned and
> verified m1n1 commit, binary sha256, ADT identity, controller path,
> generation, base, child compatible, SID and port location; clean rebuild
> reproducing the binary byte for byte.

**Marked clearly: REQUIRES CJ SIGN-OFF — NOT RUNNABLE. No artifact exists for
this ticket and none was built.**

---

## 9. Recommended forward route

In priority order.

**A. Widen and run the R0 connector-state read (ticket 178 / `m1n1-hpm2`
`baf2c20d`).** Existing policy class, no new sign-off class, one endpoint, no
W1C, no command. Add `0x03`, `0x40`, `0x3f`, `0x5f`, `0x28`, `0x14` (read) and
`0x50` (read) to the existing `0x1a` + `0x20` read. Unlink the `SWDF`/`SWUF`
class from the binary. **This single experiment decides whether R3 exists at
all**, and it also hands boundary 1 the live `0x50` word for free.

**B. Proceed with the ticket-170 data path in parallel — it is required either
way.** Enable, review and iterate the staged
`t6040-usb3-right-data-path.dtsi` + the T6040 atcphy driver slice. Newly
available facts that help: `hpm2 -> acio2` (`atc-phy-parent`, `port-number 3`),
right-port retimer = `/arm-io/i2c6/uatcrt2` @ `0x1a` with the HPM as its
firmware path (`spi-flash-parent`), and `apple,dart-vm-size` is mandatory on the
DART nodes.

**C. Only if (A) shows the port is not sourcing: build the PD path as a Linux
driver, not an m1n1 experiment.** An SPMI regmap + SPMI shim for the existing
`tps6598x`/`cd321x` core, reusing `m1n1-hpm2`'s proven selector protocol as the
regmap bus implementation. Keep yuka's `tps6598x-spmi` branch as the reference
but do not import its generic HPM iteration, automatic power-state commands or
interrupt mutation. Constrain the DT to `hpm2` only.

**D. Update ticket 096 to `r3-superseded-by-r0-measurement`** rather than
re-specifying R3. Boundaries 2 and 3 are closed; boundary 1 is closed for the
upper halfword, undecidable for the lower, and avoided entirely by the design.
The reason R3 does not close is no longer "the rollback is incomplete" — it is
"the mutation is unnecessary until an R0 read proves otherwise".

---

## 10. Recommended maintainer edits to `docs/SPMI_SAFETY.md`

Listed, not made — these are CJ's call, as with the 2026-07-25 pass.

1. **Class R3 register list.** It names `0x14`, `0x23`, `0x24`, `0x55` (three of
   which the class-10 path never writes; `0x24` is a *status* register upstream,
   `TPS_REG_USB4_STATUS`, which explains why Apple never writes it) and omits
   `0x50` and `0x18`-as-W1C, which it does write. The 2026-07-25 pass flagged
   this; it is still open.
2. **R3's "reading `0x14` still consumes event state via the paired `0x18`
   clear."** That describes Apple's `getAndClearInterrupt` *helper*, not a bare
   read. A bare R0 read of `0x14` consumes nothing; only writing `0x18` does.
   The R0 section already says the right thing; the R3 sentence should be
   reworded so it cannot be read as "R0 reads of `0x14` are destructive".
3. **Add the cross-validated register names** to the R0 list, since they are now
   established rather than inferred: `0x03 MODE`, `0x1a STATUS`,
   `0x20 SYSTEM_POWER_STATE`, `0x24 USB4_STATUS`, `0x28 SYSTEM_CONF`,
   `0x3f POWER_STATUS`, `0x40 PD_STATUS`, `0x48/0x49 RX_IDENTITY_SOP/SOP'`,
   `0x50 DATA_CONTROL`, `0x55 DataControl2`, `0x5e CF_VID_STATUS`,
   `0x5f DATA_STATUS`. This makes future R0 candidates self-documenting.
4. **Record that `nub-spmi-a0` contains hpm0/hpm1/hpm5 with hpm0 a configuration
   twin of hpm2** (same class, port-type, features, transports, interrupts and
   even SID `0x0c` on its own controller). It strengthens the existing "do not
   touch a0" rule: a wrong-controller transaction to SID `0x0c` would hit the
   recovery tether's PD controller, not a dead address.

---

## 11. Corrections and confirmations relative to earlier write-ups

**Confirmed.** The 2026-07-25 pass's whole-binary claims survive an independent
re-derivation from a freshly generated 99,488-instruction listing: `0x14` is
never passed to `writeReg`; `setInterruptMask` writes a synthesized constant and
never reads `0x16` on the class-10 path; `0x24` is never written; `0x55` is never
read; `turnOnVbus()` is a driver-ready acknowledgement, not a power operation;
`AppleHPMInterface::turnOnVbus` @`0xfffffe000951906c` is a bare stub; the
`SWDF`/`SWUF` halfword constants at `0xfffffe00074e3208` / `0xfffffe00074e3200`
are real and are the only TPS-vocabulary 4CCs in the image.

**Refined — the `0x50` write inventory was incomplete.** The 2026-07-25 pass
listed two `0x50` writers. There are **four functions / six call sites**, and
the two it missed (`AppleHPMDeviceHALType4::ackDPIRQ` @`0xfffffe00095023b8` and
`::resetDataControl` @`0xfffffe00095024b8`) are the byte-preserving,
single-bit RMW pair. That is what makes boundary 1 answerable at all — and also
what makes bit 13's semantics undecidable, since they contradict the base-HAL
implementations.

**Refined — `roleSwap` does not call `execute4Cc`.**
`AppleHPMInterface::roleSwap(uchar)` @`0xfffffe0009521fd0` calls
**`AppleHPM::atomic4CC(uchar, uchar*, uchar*, uchar*, uchar*, uchar*, ushort,
ushort, u64, u64, uint)`** @`0xfffffe0009550c9c` through slot **+0x9a8** of the
bus object at `this+0x1110` (diversifier `0x6715`, matched against the vtables
of `AppleHPM`, `AppleHPMARM`, `AppleHPMARMSPMI`, `AppleHPMARMI2C`, `AppleHPMIECS`,
`AppleHPMEmbedded`, `AppleHCPM`), not through `AppleHPMInterface::execute4Cc`
@`0xfffffe0009519774`. The earlier conclusion is unchanged — `atomic4CC`'s first
argument selects the command register, `1 -> 0x08 (CMD1)` and `2 -> 0x10 (CMD2)`
(`0xfffffe0009550da8-0xfffffe0009550db4` and `0xfffffe0009550d7c-
0xfffffe0009550d88`) — but the call path in the earlier note was wrong and the
real engine is worth knowing, because it is the function that implements the
`!CMD`/`ABRT` handshake and the `IOSleep(5)` poll, and it is gate-held
(`IOEventSource::closeGate` @`0xfffffe0009550e00`).

**New — `4CC SCfg` and register `0x28` are now named, not inferred.** The
2026-07-25 pass recorded "that `SCfg` means source/sink configuration ... is
inference". Upstream names register `0x28` `TPS_REG_SYSTEM_CONF` with
`PORTINFO = conf & 7` (`core.c:44`, `core.c:1206`), so `SCfg` = System Config
and `disablePort`'s `(x & 0x7c) | 0x03` field minimisation is operating on
`SYSTEM_CONF` port-capability fields. The inference is now corroborated.

**New — `AppleHPMDeviceHALType5::setBRDataControl` is a decoder, not a setter.**
Despite the name it performs no register access; it fills an `HPMBRDataControl`
struct from a raw buffer. Anyone auditing the `0x50` surface by symbol name
would otherwise count it as a writer.

---

## 12. What is explicitly NOT authorised by this document

- Nothing here authorises building or running any artifact.
- R3 remains a **NO-GO**. §8 is a draft for CJ's decision, not an approval, and
  it is gated behind an R0 experiment that has not run.
- Tickets 102-108 remain not-to-be-built.
- `SWUF` as a "rollback" is not proposed; it would be a second R3 operation with
  its own ticket.
- No edit was made to `docs/SPMI_SAFETY.md`, `AGENTS.md` or any ticket.
- Nothing was drafted for external posting.
