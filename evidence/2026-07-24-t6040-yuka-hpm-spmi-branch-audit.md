# Yuka m1n1 HPM/SPMI branch audit for T6040

Date: 2026-07-24
Ticket: 090
Scope: source fetch, static review, and host build only; no rig or target access

Policy update later on 2026-07-24: the branch-wide no-live decision remains,
but the transport-wide SPMI ban was replaced by `docs/SPMI_SAFETY.md`.
Offline ticket 092 may extract and harden direct right-HPM2 R0/R1/R2
operations; it must not merge or run this branch wholesale.

## Result

Yuka's late-2026-07-24 `tps6598x-spmi` branch is the first public
upstream-shaped implementation candidate that recognizes the exact HPM
topology blocking Wallace's right-side passive USB stick:

```text
/arm-io/nub-spmi-a1
  compatible = aapl,spmi
  gen = 3
/arm-io/nub-spmi-a1/hpm2
  compatible = usbc,sn201202x,spmi
  port-location = right
```

This materially upgrades ticket 023 from “no published T6040 HPM transport
code” to “public, compiling WIP exists.” It does **not** clear the live gate.
The IRC success report says only that the factored `foreach-hpm` path works on
T6000, whose HPM path is I2C. It does not report that the new Gen3 SPMI path
works on T6040.

Sources:

- `feature/foreach-hpm` head
  [`0f6cf87bc652`](https://github.com/yuyuyureka/m1n1/commit/0f6cf87bc65200b35c519d17ca9d799137ee2d18)
- `tps6598x-spmi` transport split
  [`2acd5b6c7ecb`](https://github.com/yuyuyureka/m1n1/commit/2acd5b6c7ecbb04dd94dbc7294b9676f4e933ac5)
- SPMI transport
  [`23c7cea1da14`](https://github.com/yuyuyureka/m1n1/commit/23c7cea1da14aaf7024f7fe59185ad673bb72ff6)
- SPMI-node iteration / branch head
  [`dcc5f1bccbbe`](https://github.com/yuyuyureka/m1n1/commit/dcc5f1bccbbe986099f218e9057f7fa99a0b1fe2)
- prerequisite empty-child ADT fix
  [`06219343e5cd`](https://github.com/yuyuyureka/m1n1/commit/06219343e5cdce4e2f45a16740bff52da4ac5676)

## What the branch changes

`tps6598x_foreach_hpm()` now walks both:

- legacy `i2c,s5l8940x` → `usbc,manager` → `usbc,cd3217`; and
- `aapl,spmi` or `spmi,gen3` → direct `usbc,sn201202x,spmi` children.

For J614s it will find HPM0/1/2/5. A `USE_DEBUG_USB` build starts normal USB
initialization at index 1, so it should avoid applying the general USB action
to tether HPM0 while including right-port HPM2. After iterating the HPMs,
`usb_init()` runs the existing per-index PHY bring-up.

A clean detached build of exact head `dcc5f1bc` succeeds with the local LLVM
and nightly Rust toolchain. It emits five C23-extension warnings for unnamed
callback parameters and one unrelated unused Rust-feature warning. This is
compile evidence only; the produced binary was deleted and is not a live
artifact.

## Why it is not an observation-only candidate

The SPMI path performs state-changing operations during ordinary
initialization:

1. `tps6598x_init_spmi()` sends SPMI WAKEUP (`0x13`) and waits 10 ms.
2. Even a logical TPS register read first issues `spmi_reg0_write()` to select
   the register, then polls the selection byte.
3. `tps6598x_powerup()` may write DATA1 and issue the `SSPS` command.
4. `tps6598x_disable_irqs()` writes all ones to `IntClear1`, then zeros the
   interrupt mask.
5. `tps6598x_shutdown()` sends SPMI SHUTDOWN (`0x12`).
6. The existing PHY bring-up then performs its known ATC/eUSB2 MMIO sequence.

These are exactly the SPMI/HPM operations prohibited by the rig rules without
an independently reviewed state/rollback contract and explicit maintainer
authorization. In particular, “foreach works on T6000” cannot authorize them
on the J614s SN201202x.

The branch also does not visibly implement the paired class-10
`turnOnVbus()` address-`0x14` nine-byte RMW, connector role/orientation policy,
or the complete eUSB2 repeater reset/rollback path documented in Wallace. It
may rely on generic TPS state already established by firmware; that is an
unproven inference, not a test premise.

## Source-review issues before any live proposal

- `tps6598x_spmi_select_reg()` has no iteration or time bound. A selection byte
  that remains in the trigger state hangs forever.
- `tps6598x_init_spmi()` dereferences the allocation result before checking it
  and leaks it if WAKEUP fails.
- `tps6598x_enable_debugusb_one()` calls shutdown on a power-up error and the
  outer iterator calls shutdown again, producing a double shutdown/free path.
- HPM index matching uses `idx > USB_IODEV_COUNT` instead of `>=`; an `hpm8`
  name would index past the eight-entry state array.
- `matched` becomes true before bus initialization/action succeeds, so the
  iterator can report success after an SPMI-controller initialization failure.
- There is no T6040 transcript proving WAKEUP, register selection, `SSPS`, IRQ
  masking, and SHUTDOWN semantics or showing the right port reaches source
  role with correct rollback.

## Decision

1. Track `dcc5f1bc` as the leading external-root implementation candidate.
2. Do not merge it into Wallace's safe m1n1, build a rig image, or retry the
   passive stick.
3. First resolve the bounded-poll, lifetime, bounds, and error-reporting
   issues; obtain an exact T6040 state/rollback explanation and upstream test
   result.
4. Historical note: a powered/self-powered fixture was then retained as an
   alternative. It is no longer available or an active gate; later endpoint-
   scoped tickets 093–095 proved only inactive → WAKEUP → SSPS/S0, and
   096/102–113 now own the remaining decomposed work.

No repository outside Wallace was modified. Fetches changed only remote/FETCH
metadata; the temporary build worktree and binary were removed.
