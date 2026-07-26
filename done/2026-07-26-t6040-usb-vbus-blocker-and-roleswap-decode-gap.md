# USB read/write: the blocker is VBUS, and the role-swap sequence is NOT decoded

Autonomous session, 2026-07-26 night, with maintainer authorisation for HPM role-swap writes, live
PCIe reads, and an expendable stick. **No rig run was made.** The reason is below, and it is a
knowledge gap, not a permission gap.

## 1. Forced host mode is already proven — and already proven insufficient

`done/2026-07-21-t6040-usb-host-right-smoke-result.md` records exactly the experiment I was about to
build. `apple,force-host-mode` on `usb_drd2` (the right port) with
`dts/t6040-j614s-dcuart-usb-host-right.dts`:

- DARTs initialised at `0x392f00000`/`0x392f80000`;
- xHCI registered at `0x392280000`, IRQ 42, USB buses 1 and 2 created;
- `uas` and `usb-storage` registered;
- **only the two root hubs appeared. No child device. `/proc/partitions` empty.**
- No SError, no DART fault, no reset loop.

So the controller and DART path reach Linux root hubs, and the missing piece is the **physical Type-C
path**: VBUS, and/or ATC/ACE role and PHY setup. That DT deliberately enables **no ATC PHY** and does
no VBUS/SPMI writes.

**The stick is bus-powered.** With no VBUS it cannot enumerate no matter what the kernel does. Rebuilding
that image unchanged would have burned a rig cycle to re-learn a recorded result — the ticket even says
"do not repeat this image unchanged with the same unpowered topology".

## 2. The R3 role-swap sequence is not decoded, so an R3 candidate cannot be written honestly

HPM writes are issued from purpose-built `m1n1-hpm2` candidates gated on
`T6040_HPM2_EXPERIMENT_CLASS`, which is **hard-capped at 2** (`#if … > 2` → build error). R2 is proven:
DATA1 (`0x09`) ← `00`, CMD1 (`0x08`) ← `"SSPS"`, poll, state `0x07` → `0x00`.

R3 would add the role swap. Ticket 096 states that `AppleHPMInterface::roleSwap()` issues **SWDF**
(DFP/host) and **SWUF** (UFP/device) 4CCs. **I could not corroborate that from the disassembly.**

`SWDF` as a little-endian u32 is `0x46445753`, so building it as an immediate requires
`mov w, #0x5753` followed by `movk w, #0x4644, lsl #16`. In `t6040-applehpm-text.dis` (4.9 MB of
AppleHPM `__TEXT_EXEC`):

- **`mov #0x5753` appears zero times.** So neither `SWDF` nor `SWUF` is constructed as an immediate
  anywhere in this kext's text.
- The only `0x4644` sites (2) are `mov #0x4644` + `movk #0x6655` = `0x66554644`, whose LE bytes are
  `44 46 55 66` = **`"DFUf"`** — a DFU-class command, not a role swap.

I nearly mis-identified that as the role swap by grepping the immediate `0x4644` alone. It is worth
stating plainly: **a guessed 4CC written to CMD1 is not a safe experiment**, and ticket 096 already
flags its own sequence decode as incomplete.

So before any R3 candidate exists, the SWDF/SWUF claim must be re-sourced — the constants may live in a
data section rather than as immediates, may be in a different kext (the IOKit/userspace side), or the
original note may have come from the *public* TPS6598x driver rather than Apple's code.

## 3. A qualification to the brick assessment (not an overturn)

`done/2026-07-25-t6040-r3-risk-calibration.md` withdrew the "unrecoverable port" framing on the grounds
that there are "no flash/OTP/patch-bundle writes" in the staged op set. **That remains true of our
candidates** — R0–R2 contain exactly two extended writes, reviewed byte for byte.

But this decode shows a **DFU-class 4CC does exist in AppleHPM's vocabulary**. The controller therefore
does expose a firmware-update path in principle, even though nothing we issue goes near it. The
practical consequence is narrow but real: an R3 candidate must be reviewed at the byte level *of the
4CC itself*, because the difference between a role swap and a DFU command is a few bytes in one
immediate. That raises the review bar; it does not resurrect the "unrecoverable" framing.

## 4. What would actually move USB forward

In cost order:

1. **Decode `roleSwap` properly** (offline, safe). Find the real SWDF/SWUF construction: search
   `__DATA`/`__const` for the 4CC bytes, locate the `AppleHPMInterface` vtable and its `roleSwap` slot,
   and check the adjacent `AppleHPMARMI2C`/`AppleHPMBusController` classes. Only then write R3.
2. **Enable the ATC PHY in the DT** — even with VBUS, the 2026-07-21 DT enabled no ATC PHY, so the USB2
   data path may not be connected. This is offline DT work and independent of the HPM question.
3. **The topology discriminator that needs no writes at all**: a *self-powered* device or powered hub on
   the right port. If a self-powered device enumerates with the existing image, the gap is purely VBUS
   and the HPM path is confirmed necessary; if it still shows root hubs only, the gap is ATC/ACE PHY and
   HPM work would not have helped. Ticket 065 already proposed this. **It requires someone to plug a
   device in, so it is maintainer-only** — and it is by far the cheapest way to split the remaining
   ambiguity.

Item 3 is the recommendation. It is one cable change, no code, no writes, and it decides which of the
two remaining hypotheses to invest in.
