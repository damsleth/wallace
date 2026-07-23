# Cross-review: ticket 001 RX BIT(1)/TX-poll diagnostic (PASS)

> **Superseded routing note (2026-07-21):** this PASS certifies the historical
> IRQ-360 artifact as reviewed, not as using the correct UART route. Later M4
> Pro measurement found AIC input 816. Do not reuse this image.

Reviewer: `fable` (ticket 043), 2026-07-14. Author: `claude`. Reviewed against
`~/Code/m1n1/AGENTS.md` non-negotiables and the DEVLOG DockChannel MMIO
caution, per AGENT_ONBOARDING §6 / COORDINATION §Cross-agent review. Every
claim below was verified against the artifacts, not the write-up
(`done/2026-07-14-t6040-dockchannel-rxirq-txpoll.md`).

## Hashes — all match, byte-exact

Recomputed SHA-256 of all seven recorded artifacts; all match the record:

- `Image-dcuart-irq-txpoll` `ef60d5ea…4a15e` ✓
- `System.map-dcuart-irq-txpoll` `119ad813…3d02e` ✓
- `t6040-j614s-dcuart-irq-txpoll.dtb` `3d5bc90e…8d452` ✓
- `initramfs-dcuart-irq-txpoll-report.cpio.gz` `4697a5b6…70263` ✓
- extracted initramfs `/init` `07d21482…30304` ✓ = byte-identical to
  `scripts/t6040-init-dcuart-irq-txpoll-report` (diff clean)
- `patches/t6040-dockchannel-tx-poll-debug.patch` `af8015a5…76445` ✓
- `patches/t6040-dockchannel-fifo-telemetry-debug.patch` `29a8d9da…3063d` ✓
- m1n1 control: the stashed
  `~/Code/linux-build-out/m1n1-t6040-logbuf-upper-guard-dryrun.bin`
  recomputes to `1394c345…a7e61b` ✓ — the live-proven `a61fd099`
  zero-PCIe-write + log-ring-guard control that already booted Linux to
  BusyBox. It performs no PCIe access and never touches the UART IRQ block
  before handoff.

## DTB (decompiled and inspected)

- UART mailbox node `mailbox@50880c000`: `reg` = ADT-derived
  `0x50880c000/0x508828000/0x50882c000` (irq/config/data),
  `apple,irq-tx-mask = <0x4>`, `apple,irq-rx-mask = <0x2>`,
  `apple,irq-rx-cap = <0x3e8>`, `apple,irq-storm-limit = <0x400>`,
  `apple,tx-poll-mode`, `apple,irq-telemetry`,
  `interrupts = <0 0x168 4>` (AIC input 360, level-high). ✓
- No `apple,poll-mode` anywhere (the 5 ms full-poll stays out, as intended). ✓
- The separate HID dockchannel keeps its own correct MTP RX BIT(3)
  (`apple,irq-rx-mask = <0x8>`) — the two instances are not conflated. ✓
- NVMe (`nvme@40dcc0000`) and SART both `status = "disabled"`; no PCIe host
  node. No storage path exists in this image. ✓

## MMIO audit — all accesses inside the DEVLOG-safe windows

Accessed offsets (driver + both patches, relative to `0x508800000`):
writes `+0xc000/+0xc004` (IRQ_MASK/IRQ_FLAG, within the 24 B irq block),
`+0x28004` (RX_THRESH), `+0x2c004/+0x2c010` (TX8/TX32); reads
`+0x2c014` (TX_FREE), `+0x2c01c/+0x2c028` (RX8/RX32), `+0x2c02c` (RX_COUNT).
All inside the safe `+0xc000` and `+0x28000..+0x38004` windows; the fatal
`+0x20000`-class offsets are never touched. CONFIG_TX_THRESH is never written
in tx-poll mode. No SPMI/PMU/NVRAM access; no new or swept offsets; every
address comes from the DT/ADT. ✓

## Cap and TX-poll logic (patch source review)

- RX cap: at exactly the 1,000th handled RX event the hard handler snapshots
  raw flag/FIFO/total, clears BIT(1) from the local mask via the existing
  helper, reads the mask back, then still W1C-acks and permits that event's
  threaded drain — semantics preserved, as designed. ✓
- Hard cap: at absolute entry ≥1,024 it snapshots, writes local mask 0, and
  `disable_irq_nosync()` on the Linux virq. Post-cap delta ≤ 24. Neither cap
  path printks (the old `dev_err` was removed — important, since printk could
  recurse into the storm). ✓
- Probe validation rejects telemetry without tx-poll, with full poll-mode, or
  with `rx_cap >= storm_limit`. ✓
- TX truncation is impossible: `send_data` returns `-EMSGSIZE` above the
  2,048-byte FIFO size and `-EBUSY` unless the FIFO is completely empty, so
  `write_pending()` always writes the whole message; FIFO-drain is therefore a
  sound completion signal for the 1 ms poll. TX BIT(2) is never unmasked. ✓
- Telemetry sysfs reads only registers the reviewed driver already uses;
  counters are snapshotted under the existing lock; virq→hwirq join is
  reported explicitly. ✓
- Init script: telemetry-only, bounded waits (24 s RX read, 10 samples),
  watchdog petted, no module loads, no storage access, unique
  `INJECT-NOW` marker before the single approved probe line. ✓

## Residual trust (noted, not blocking)

The kernel `Image` binary is trusted to be built from exactly these patches in
the recorded fresh container tree (`/build/linux-dcuart-irq-telemetry`); I did
not rebuild to reproduce the Image hash. All governing inputs (patches, DT,
init) were verified byte-exact, and the record's strict-checkpatch claim was
not re-run.

## Verdict

**PASS.** The image performs no dangerous writes at all: its only MMIO is the
already-reviewed DockChannel UART FIFO/IRQ block inside the safe windows, both
storm caps are bounded and printk-free, storage cannot be reached, and the
one-run discipline plus pre-registered interpretation matrix (NEXT_STEPS §0)
are in place. Ready for CJ approval of one boot of the exact hashes above plus
one `IRQ_BIT1_PROBE` injection after the marker.
