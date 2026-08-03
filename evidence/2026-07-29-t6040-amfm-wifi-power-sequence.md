# T6040 J614s: paired AMFM WiFi power sequence decoded

Date: 2026-07-29  
Agent: sol  
Scope: offline reverse engineering only; no rig access and no hardware writes

## Result

The paired `AppleMultiFunctionManager` (AMFM) is the actor that consumes both
load-bearing `/amfm` functions. Its power-on order is:

1. call `function-reg_on` with runtime argument `true`;
2. sleep for the configured REG_ON-on delay;
3. call `function-pcie_port_control` with enable `true`.

On the captured J614s ADT there is no `wlan_reg_on_on_delay` override, so the
paired driver's default applies: **100 ms**. The exact first SMC value remains
**`gP13 <- 0x00800001`**, not Linux `gpio-macsmc`'s `0x01000001`.

This resolves the "AMFM actor not yet identified" limitation in
`evidence/2026-07-29-t6040-pcie-endpoint-power-crossreview.md`. It does **not**
clear that review's NO-GO: the proposed Linux DT is upstream-shaped, but it is
not an exact replay of the paired Apple sequence and the new SMC write still
requires CJ's explicit approval.

## Evidence

Paired binary:

```
/private/tmp/wallace-amfm.WVDhdJ/com.apple.driver.AppleMultiFunctionManager
SHA-256 40c85d53184ec5e959e976d1349a5a7d3ed933b16d5ac4c87f8b91b73314d451
```

Addresses below are from that exact binary.

### 1. The embedded platform resolves both ADT functions

`AppleMultiFunctionPlatformEmbedded::init(...)` at
`0xfffffe00097bfea4` resolves:

- `function-reg_on` through `AppleARMFunction::withProvider`, stored at object
  offset `+0x40`;
- `function-pcie_port_control` through
  `AppleEmbeddedPCIEPortControlFunction::withProvider`, stored at `+0x60`.

The captured ADT identities are:

```
/amfm
  function-reg_on = 294:pKW4('gP13', 0x800000)
  function-pcie_port_control = 86:PrtC(0x57)

/arm-io/wlan
  amfm-managed-port-control
```

ADT function argument `0x57` is bridge phandle 87, `/arm-io/apcie0/pci-bridge0`.

### 2. `setPowerEnable(true)` executes pKW4, then sleeps

`AppleMultiFunctionPlatformEmbedded::setPowerEnable(bool)` at
`0xfffffe00097c04b4`:

- selects object `+0x30` for enable or `+0x34` for disable;
- passes a pointer to the runtime boolean to the `AppleARMFunction` virtual
  call at vtable offset `+0x140`;
- calls `IOSleep(delay)` only after the function returns success;
- stops and returns an error if the function call fails.

The paired `AppleSMCEmbeddedFunction::callFunction` decode in the independent
cross-review established pKW4's value construction: the one template constant
is copied and only its low 16 bits are replaced by the runtime argument.
Therefore:

```
pKW4('gP13', 0x00800000), true  -> 0x00800001
pKW4('gP13', 0x00800000), false -> 0x00800000
```

The ADT formatter prints the constant as `0x800000`; the 32-bit value is the
same `0x00800000`.

### 3. J614s uses the 100 ms default

`AppleMultiFunctionManager::loadConstants(OSDictionary *)` at
`0xfffffe00097b9e30` initializes both REG_ON delays to 100:

```
mov w21, #0x64
...
str w8, [expansion + 0x88]   // on delay
...
str w8, [expansion + 0x8c]   // off delay
```

It accepts these overrides, in priority order:

```
boot-arg amfm-wl-reg-on-on-delay
ADT/property wlan_reg_on_on_delay

boot-arg amfm-wl-reg-on-off-delay
ADT/property wlan_reg_on_off_delay
```

The captured `/amfm` node has neither property, so the on and off defaults are
both 100 ms. The following two constants at expansion `+0x90` and `+0x94`
default to 200 ms; they are separate platform delays and are not selected by
`setPowerEnable`.

### 4. Manager ordering is REG_ON before port enable

`AppleMultiFunctionManager::setPowerStateGated(1, ...)` at
`0xfffffe00097ba178` calls manager vtable slot `+0x908`, then `+0x910`:

- `+0x908` is `AppleMultiFunctionManager::powerOn()` at
  `0xfffffe00097bc354`;
- `+0x910` is `AppleMultiFunctionManager::portEnable(bool, bool)` at
  `0xfffffe00097bc458`, called with `(true, false)`.

`powerOn()` calls platform vtable slot `+0x138`, which is embedded
`setPowerEnable(true)`. `portEnable()` subsequently calls platform slot
`+0x168`, embedded `setPortEnable(true)` at `0xfffffe00097c0744`.

`setPortEnable(true)` invokes the resolved
`AppleEmbeddedPCIEPortControlFunction`. Its fallback, used only when that
function is absent, is `IOPCIBridge::resetDevice(type=8)`; disable uses type 4.

Thus the concrete paired path is:

```
gP13 <- 0x00800001
IOSleep(100 ms)
PrtC(bridge phandle 0x57, enable=true)
```

There is no retry of the REG_ON function in this ordinary power-on path.

## Linux comparison and review disposition

The proposed Linux path is:

```
gpio-macsmc line 19 -> gP13 <- CMD_OUTPUT | 1 = 0x01000001
apple_pcie_setup_refclk()
msleep(100)
PERST#/root-port link setup
```

The timing magnitude is calibrated correctly. The key and active polarity are
also supported independently by the direct predecessor T603x J514/J516 device
trees, which use `pwren-gpios = <&smc_gpio 19 GPIO_ACTIVE_HIGH>`.

However, two differences remain:

1. Apple sends `0x00800001`; Linux's stable generic GPIO API sends
   `0x01000001`. The upstream driver deliberately uses the low command API and
   leaves detailed pin configuration to firmware, and its commit message says
   this is sufficient for device power control. That is strong precedent, but
   it is not byte-for-byte equivalence for this new PMU generation.
2. Apple explicitly invokes ADT `PrtC` after the 100 ms delay. Linux instead
   performs its native refclock/PERST/root-port sequence. That may be the
   intended Linux representation, but it has not yet been demonstrated on
   T6040.

Disposition:

- retain the independent NO-GO on marking the current candidate reviewed;
- do not add the SD-reader `gP19` write to a WiFi discriminator;
- if CJ explicitly accepts the upstream GPIO-command precedent, the smallest
  attended experiment is WiFi-only `gP13`, with a power-cycle rollback and
  logs that distinguish SMC write failure, refclock failure, and link timeout;
- if that still times out, decode/implement the `PrtC` semantic before
  speculating about another unrelated PHY register.

## Safety

This decode did not touch the rig. A future `gP13` write is a new SMC PMU GPIO
operation. It is volatile and a power cycle is the rollback, but it is still a
hardware write outside the standing `smc_reboot`/`smc_rtc` allowance and must
not run without CJ's explicit approval.

