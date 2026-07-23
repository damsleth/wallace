# T6040 SMP DT audit + maxcpus=2 preflight (2026-07-23)

Ticket 034 (offline, P1). Audit the J614s CPU topology and produce the pinned,
cross-review-ready `maxcpus=2` artifacts that the already-approved rig ticket
005 needs (its hashes were TBD). Stage C exit step.

## Topology audit — the DT is board-correct (no fix needed)

Ground truth from the captured J614s ADT (`j614s-usb-port-map-20260721.adt`,
`ipsw dtree`): **14 CPUs**, cluster/core `reg = (cluster<<8)|core`:

| Cluster | ADT cpu-id | reg | cores |
|---|---|---|---|
| 0 (E, sawtooth) | 0–3 | 0x000–0x003 | 4 |
| 1 (P, everest) | 4–8 | 0x100–0x104 | 5 |
| 2 (P, everest) | 10–14 | 0x200–0x204 | 5 |

**cpu-id 9 is absent** — it is the fused-off 6th core of P-cluster 0 (t6040 is a
chopped t6041/M4 Max).

The kernel DT (`arch/arm64/boot/dts/apple/t6040.dtsi`) matches this exactly, with
MPIDR unit-addresses `Aff2<<16|Aff1<<8|Aff0`:

- E: `cpu@0..3` (reg 0x0–0x3), `apple,sawtooth`, `l2_cache_0` (4 MiB).
- P-cl0: `cpu@10100..10104` (5 active) + **`cpu@10105` `status="disabled"`** —
  `apple,everest`, `l2_cache_1` (16 MiB).
- P-cl1: `cpu@10200..10204` (5 active), `apple,everest`, `l2_cache_2` (16 MiB).

**`cpu@10105` is intentional, not a bug** (t6040.dtsi:162–179): m1n1's
`dt_set_cpus` uses a *positional* counter and enumerates the fused core as Apple
smp_id 9; the disabled placeholder at that slot lets m1n1 prune it without
shifting the P-cluster1 MPIDR matching. It is not in `cpu-map` and never reaches
Linux. All active nodes use `enable-method = "spin-table"` with
`cpu-release-addr` filled by the m1n1 loader.

**vs yuka's `more-t6041`:** that branch boots all cores on an M4 Pro but carries
the **t6041 (M4 Max) 16-CPU / memory-domain topology** — do **not** import it.
Our 14-active layout is the board-correct J614s topology; confirmed against the
ADT above, not copied.

Conclusion: `maxcpus=1` everywhere so far was bring-up conservatism, **not** a DT
defect. Nothing in the CPU DT needs changing to bring up a second core.

## maxcpus=2 test — minimal, no MMIO / no DT change

Bring up exactly the boot CPU (`cpu@0`, E) + its first sibling (`cpu@1`, E) via
the existing spin-table path and self-report. This is the smallest SMP assertion:
it exercises Linux's secondary-core release + WFE/idle park on one sibling.

- **No kernel or DT change.** Reuses the proven dcuart console kernel + base
  dcuart DT; the only delta is the boot argument and a reporting initramfs.
- **Bootarg:** `EXTRA_BOOTARGS=maxcpus=2`. The harness cmdline hardcodes
  `maxcpus=1`; Linux `early_param` takes the **last** `maxcpus=`, so the appended
  `maxcpus=2` wins. (Effective cmdline shows both `maxcpus=1 … maxcpus=2`; 2 is
  authoritative. A dedicated single-value arg is a cosmetic follow-up.)
- **Reporter:** `scripts/t6040-init-smp-report` prints `/proc/cpuinfo`, the
  possible/present/online masks, per-cpu online state, a `taskset -c 1` liveness
  check, and an explicit `SMP RESULT: PASS/…` line over `/dev/ttydc0`, then a
  shell. Read-only; no MMIO, storage, or DT poke.

## Pinned artifact set (for cross-review → ticket 005 run)

| Input | SHA-256 | Notes |
|---|---|---|
| `m1n1-t6040-logbuf-upper-guard-dryrun.bin` | `1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b` | safe, PCIe-write-free |
| `Image-dcuart-irq816` (dcuart console stack) | `a6c2f09354bf1d61559b450f9430eb06d42f94d027d539c2deade708d708c4ff` | DOCKCHANNEL console; SMP is standard arm64 — HID-debug patches in its source tree are irrelevant to secondary-core bring-up (mailbox = poll+rx-rearm, verified) |
| `t6040-j614s-dcuart.dtb` | `b3858f60aa96ab81f7314659284174cb10ddcec061140c1c67d397f52d617814` | base dcuart: keyboard + poll-mode `ttydc0`, 14-active topology |
| `initramfs-smp-report.cpio.gz` | `160cd9bdc8b75f10243124c1baea7ae0f4cd9e45b7284b948681e74edd8e90ea` | the reporter above |
| bootargs | `… maxcpus=2 idle=nop …` | keep `idle=nop`; only `maxcpus` changes vs the proven single-core boot |

## Pass / stop conditions

- **Pass:** `online` mask = `0-1`, `/proc/cpuinfo` shows 2 processors, the
  `taskset -c 1` task reports running on cpu1, `SMP RESULT: PASS`, shell stays
  responsive, no watchdog reset.
- **Partial/fail:** only 1 CPU online (secondary never released → check spin-table
  release-addr / WFE park) — captured, not fatal; stop and analyze.
- **Stop** on watchdog reset, hang before the report, or any SError; poll-mode
  single-core boot is the fallback.

## Run (after Sol cross-review; 005 already CJ-approved; rig NEEDS_RECOVERY)

```sh
scripts/rig-lease.sh acquire <agent> "maxcpus=2 SMP bring-up (ticket 005)" 1394c345
RIG_AGENT=<agent> bash scripts/t6040-debugusb-console.sh reboot   # recover first
RIG_AGENT=<agent> M1N1_BIN=<upper-guard> IMAGE=Image-dcuart-irq816 EXTRA_BOOTARGS=maxcpus=2 \
  bash scripts/t6040-boot-dcuart.sh t6040-j614s-dcuart.dtb initramfs-smp-report.cpio.gz
```

One boot. Do not combine with any other experiment. Console-only; no MMIO/PMU/
SPMI/storage. This satisfies ticket 005's "produce hashes + cross-review before
boot" gate.
