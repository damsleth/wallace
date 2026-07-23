# DockChannel per-instance IRQ masks and poll fallback: upstream draft packet

> **Routing update (2026-07-21):** the patch's poll fallback and per-instance
> masks remain useful, but the J614s board DT must use measured AIC input 816,
> not the ADT's 360. See `done/2026-07-21-asahi-dev-log-review.md`.

Ticket 012 is complete offline. The source draft remains
`patches/t6040-dockchannel-poll.patch`, SHA-256
`627d0805f103f56ad20cc24785d4e747740e774c1660604611298adf6bcd0e63`.
It applies to Linux `origin/dockchannel` at `ba89d30070d4` and changes only
`drivers/mailbox/apple-dockchannel.c`.

This is a draft for the DockChannel branch authors, not a claim that its local
DT property names are an accepted binding. CJ sends any external message.

## Grounded problem statement

The branch driver hard-codes TX BIT(2) and RX BIT(3). BIT(3) is the MTP
instance's receive flag, while the older working UART-style DockChannel path
uses RX BIT(1). The J614s instances therefore cannot share one hard-coded RX
mask. The bounded UART run with explicit BIT(2)/BIT(1) retained TX but did not
recover interactive RX, and could not retrieve an interrupt count. It proves
the instance mask difference; it does **not** prove that ADT AIC input 360 is
dead. See `done/2026-07-14-t6040-dockchannel-irq-retest.md` and
`done/2026-07-14-t6040-dockchannel-rxirq-txpoll-result.md`.

The same source draft provides an explicit 5 ms delayed-work fallback. That
path is the current daily remote shell: it completes TX when the existing data
FIFO drains and delivers RX according to the existing `DATA_RX_COUNT`. It is
opt-in, and the IRQ path remains the default.

## Source-draft behavior

- Default TX/RX masks stay BIT(2)/BIT(3), preserving existing MTP behavior.
- Local `apple,irq-tx-mask` and `apple,irq-rx-mask` values override each
  instance independently; zero or overlapping masks fail probe.
- Local `apple,poll-mode` skips IRQ acquisition and IRQ mask enablement.
- Startup still programs the existing byte-granularity RX threshold, then
  starts one delayed worker.
- The worker completes an active TX only after `DATA_TX_FREE` reports the full
  0x800-byte FIFO, drains bounded FIFO-sized RX chunks, and reschedules only
  while the mailbox client is active.
- Shutdown clears `poll_running` and synchronously cancels the worker before
  clearing TX state. `READ_ONCE`/`WRITE_ONCE` make the reschedule decision
  explicit across the shutdown race.

The patch adds no MMIO address or offset. It uses the driver's already mapped,
ADT-described IRQ/config/data resources and its existing mask, flag, threshold,
FIFO-free, and FIFO-data registers. Poll mode avoids new IRQ-block writes after
probe; it does not blind-probe any register.

## Offline validation

A fresh case-sensitive tree in the `kbuild` container was checked out at exact
base `ba89d30070d4`, then the stored patch was applied by itself:

- `git apply --check`: PASS;
- applied source `git diff --check`: PASS;
- strict `scripts/checkpatch.pl` on the applied source diff: 0 errors,
  0 warnings, 0 checks;
- `make ARCH=arm64 olddefconfig`: PASS;
- `make ARCH=arm64 W=1 -j4 drivers/mailbox/apple-dockchannel.o`: PASS with no
  warning from the changed object.

The live evidence is intentionally narrower than the static result. Poll mode
has repeatedly carried the J614s BusyBox shell. The corrected UART mask run
proved TX survived with BIT(2), but the later bounded telemetry left AIC input
360 unattributed. Keep those claims separate.

## Draft handoff text

Suggested subject:

```text
mailbox: apple: make DockChannel IRQ masks configurable
```

Suggested cover/body, to adapt after agreeing the binding shape with the branch
authors:

```text
DockChannel instances do not all use the same receive flag. The MTP instance
uses BIT(3), while the UART-style instance on T6040 uses BIT(1); both use
BIT(2) for transmit. Move the masks into per-instance state while retaining
the existing BIT(2)/BIT(3) defaults.

Also add an explicit delayed-work fallback for users that cannot yet rely on
their described interrupt path. The fallback uses only the existing FIFO
count/free/data registers, completes TX after drain, and is disabled by
default.

This does not characterize the T6040 UART AIC input as non-functional. Our
bounded test has not yet attributed that input because the target RX path did
not return the interrupt counters.
```

## Coordination points before sending

The authors should choose whether the IRQ-mask description belongs in DT,
compatible data, or a client/instance quirk, and whether the poll fallback
belongs in the same patch. There is no DockChannel binding in this local
branch, so `apple,irq-{tx,rx}-mask` and `apple,poll-mode` must remain explicitly
local until that decision is made. If DT properties are retained, add and
schema-check a binding in the authors' series.

The fallback's 5 ms policy and drain-until-empty RX loop also deserve explicit
review before submission. They are acceptable for the proven debug-console
use, but the upstream authors may prefer a bounded per-work budget or a
different scheduling policy for a continuously producing coprocessor.

No further rig run is required to hand this source packet to the branch
authors. Any new IRQ experiment remains separately build/hash/review/approval
gated, and must not call IRQ 360 dead without direct attribution.
