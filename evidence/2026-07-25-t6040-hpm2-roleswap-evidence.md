# T6040 ticket 096 — new primary evidence: the role-swap pair, and no VBUS-off exists

Date: 2026-07-25. Host-only static analysis; no rig, no SPMI, no writes to the paired
firmware corpus. Continues `evidence/2026-07-24-t6040-hpm2-detach-static-slice.md` (Sol) and
does not redo what it proves.

## 1. A matched operation/inverse pair: `SWDF` / `SWUF`

`AppleHPMInterface::roleSwap(unsigned char)` — VA `0xfffffe0009521fd0`, in
`com.apple.driver.AppleHPM` — issues exactly **two** TPS6598x 4CC commands, selected by
its argument:

| Call | Command | Meaning |
|---|---|---|
| `roleSwap(0)` | **`SWDF`** | Swap to **DFP** — become downstream-facing (host) |
| `roleSwap(1)` | **`SWUF`** | Swap to **UFP** — become upstream-facing (device) |
| `roleSwap(n>1)` | none | `v0` zeroed, `w8 = 0`; no command issued |

Decode: the two constants live at VA `0xfffffe00074e3208` (`SWDF`) and `0xfffffe00074e3200`
(`SWUF`), stored as **16-bit halfwords** (`53 00 57 00 44 00 46 00` = `S W D F`), which is
why the code applies `rev64.4h` then `uzp1.8b` — reversing the four halfwords and taking
each low byte yields the packed 4-byte command register value. Branch logic:

```text
cmp  w1, #0x1 ; b.eq -> ldr d0, [x8, #0x200]   (SWUF)
cbnz w1       ->        movi.2d v0, #0          (arg > 1: no command)
fallthrough   ->        ldr d0, [x8, #0x208]   (SWDF)
```

**This is the first genuine operation/inverse pair found for the host-transition problem.**
Sol's slice searched the `AppleTCController*` hierarchy; `roleSwap` lives in the parallel
`AppleHPMInterface*` hierarchy, which is why it was not surfaced before.

## 2. `AppleHPMInterface::turnOnVbus()` is a no-op stub — confirms Sol

VA `0xfffffe000951906c`: `bti c ; mov w0, #0x0 ; ret`. The base-class implementation does
nothing, so `AppleTCControllerType10::turnOnVbus()`'s logical-`0x14` event injection
remains the only implementation. Consistent with the existing slice.

## 3. Proof by exhaustion: **no VBUS-off command exists in the driver's vocabulary**

Scanned the **entire 119,209,984-byte kernelcache** for halfword-encoded 4CCs
(`(?:[ -~]\x00){4}`). Across the whole image the only TPS6598x-vocabulary commands present
are **`SWDF` (×1) and `SWUF` (×1)** — the pair above.

Specifically **absent**: `SWSr`/`SWSk` (power-role swap to source/sink), `GAID` as an issued
command (`GAID` appears in AppleHPM exactly once, inside the log string `"Mode after GAID"`,
i.e. a state the driver *observes*, not a command it sends), `SRDY`, `Disc`, `SSrC`, `GSkC`,
`PTCc`, `MRST`.

Two consequences:

- **Sol's "no VBUS-off operation" is now much stronger.** It is not "we did not find one" —
  the driver's command vocabulary does not *contain* one. VBUS sourcing on this port is not
  4CC-controlled, so an R3 rollback cannot be built around a VBUS-off command because none
  exists to build around.
- **Independent corroboration of the risk calibration**
  (`evidence/2026-07-25-t6040-r3-risk-calibration.md`): no flash/OTP commands (`FLrr`, `FLwr`,
  `FLem`, `FLad`, `FLvy`) appear anywhere in the kernelcache, which is the actual
  persistent-brick vector. Its absence across the whole image, not just the staged op set,
  supports "no persistent-brick mechanism".

`SSPS` appears 7× in AppleHPM, all inside `setPowerStateHPM` log strings — consistent with
R1/R2's use of it.

## 4. Bonus: a forced-role state gates SSPS

AppleHPM contains the log string:

```text
SSPS blocked due to forced usb device role and UFPf
```

So the driver tracks an explicit **forced-UFP** state, and that state can **block** an SSPS
power-state transition. Relevant to R1/R2, which drove SSPS directly: if a forced role is
latched, SSPS may legitimately refuse, and that is a driver policy rather than a hardware
fault.

## 5. What this does and does not change for R3

**Changes the design.** The rollback for a host transition should be framed as
`roleSwap(1)` → `SWUF` (relinquish the DFP/host role), composed with the framework's
existing mode-flag teardown that Sol decoded (absent flags → `removeUSB3PortObject()` /
`removeUSB2PortObject()`), rather than as a search for a VBUS-off register.

Likewise the *forward* path may be far cleaner than the logical-`0x14` event injection:
`roleSwap(0)` → `SWDF` is a documented, single-command way to request the host role.

**Does not make R3 a go.** `SWDF`/`SWUF` are **data**-role commands (DFP/UFP), not power-role
commands (source/sink). Whether VBUS actually drops when the port leaves DFP is **not
proven by this evidence** — it depends on the controller's DRP/Try.SRC configuration and on
what the framework does next. Also still unproven from Sol's original list: exact
mask/detect restoration semantics, restoration of the observed pre-SSPS state `0x07`, a
byte-preserving `0x23` inverse or neutral `0x55`, and a safe cross-layer teardown order.

## Verdict for ticket 096

Item 1 of the six ("a VBUS-off / source-disable operation") is now **answered — negatively
and conclusively**: no such command exists. Item 2's inverse acquires a real candidate
(`SWUF`) for the *role* half, though not for the `0x14`/W1C event half. Items 3-6 remain
open.

So 096 moves from *"no evidence"* to *"evidence found; R3 needs redesigning around the
role-swap pair"*. **R3 remains a no-go** as currently specified, and any future candidate
must treat "does VBUS drop on leaving DFP?" as a measurement, not an assumption.
