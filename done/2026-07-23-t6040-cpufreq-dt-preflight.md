# T6040 cpufreq DT audit + preflight (2026-07-23)

Ticket 035 (offline, P1). Wire `apple,cluster-cpufreq` for the three T6040
clusters to ready the already-approved rig ticket 006. **Audit complete; DT
authoring blocked on one decode step (below) — not on missing data, and no
values are invented here.**

## What's established (grounded)

**Cluster DVFS bases (m1n1-proven).** m1n1's t6040 path uses the 1E+2P cluster
table `ECPU0 0x210e00000 / PCPU0 0x211e00000 / PCPU1 0x212e00000`
(`~/Code/m1n1/src/cpufreq.c`), and m1n1 cpufreq works on the rig (ROADMAP Stage
B) → these bases are live-verified. They are **identical to t6031**; the plan's
"bases may differ on M4" risk (`done/2026-07-10-t6040-cpufreq-plan.md`) is
retired by the working m1n1 bring-up. Apple's DVFS cluster regs are not ADT
addressable nodes (the cpu nodes carry `acc-impl-reg`/`cpm-impl-reg`, and m1n1
reads the pstate table from `base + 0x70000`), so the base cross-check is m1n1,
not an ADT `reg`.

**Linux node shape.** The `apple,cluster-cpufreq` controller reg = cluster base
+ `0x20000` (t6031 uses `cpufreq@210e20000` etc.). So the T6040 nodes mirror
t6031 exactly:

```dts
cpufreq_e:  cpufreq@210e20000 { compatible = "apple,t6031-cluster-cpufreq","apple,t8112-cluster-cpufreq"; reg = <0x2 0x10e20000 0 0x1000>; #performance-domain-cells = <0>; };
cpufreq_p0: cpufreq@211e20000 { … reg = <0x2 0x11e20000 0 0x1000>; … };
cpufreq_p1: cpufreq@212e20000 { … reg = <0x2 0x12e20000 0 0x1000>; … };
```
and each cpu node gains `performance-domains = <&cpufreq_e|_p0|_p1>` by cluster
(E: cpu@0-3 → e; P-cl0: cpu@10100-10104 → p0; P-cl1: cpu@10200-10204 → p1).

**The driver requires OPP tables.** `drivers/cpufreq/apple-soc-cpufreq.c:254`
calls `dev_pm_opp_of_add_table()` and reads `dev_pm_opp_get_level()` per entry,
so each cpu node also needs `operating-points-v2` with `opp-hz` + `opp-level`
(pstate index) — like t6031's `sawtooth_opp`/`everest_opp`. **These frequencies
are SoC-specific and differ M3→M4; they cannot be copied from t6031.**

## The one remaining step (the block) — decode the ADT DVFM table

The needed `opp-hz`/`opp-level` values are in the captured ADT at
`/arm-io/pmgr/voltage-states*` (Apple's per-cluster pstate → freq/voltage
arrays; e.g. `voltage-states1`, `voltage-states5`, with `-sram` siblings).
**But `ipsw dtree --json` mangles these byte blobs** (it serialized
`voltage-states1` as `['6y']` — truncated), so they must be read from the raw
ADT binary (`linux-build-out/j614s-usb-port-map-20260721.adt`), not the JSON.

Unblock (next offline step, no rig):
1. Parse the raw ADT with a real ADT reader — install `construct` in a venv and
   use `~/Code/m1n1/proxyclient/m1n1/adt.py`, or a minimal TLV parser — and read
   the full `voltage-states0/1/5(/-sram)` arrays.
2. Map each `voltage-states<N>` index to its cluster (E/P-cl0/P-cl1) via the cpu
   nodes' cluster/dvfm-state linkage, and decode the word layout
   (freq × voltage) to `opp-hz` (Hz) + `opp-level` (pstate).
3. **Cross-validate** the decoded pstate freqs against a read-only m1n1 proxy
   read of the live HW table (`cluster_base + 0x70000 + pstate*0x20`) before
   trusting them — this is the anti-fabrication check. (Proxy read needs the
   lease but is read-only; can piggyback on any rig window.)
4. Author `everest_opp`/`sawtooth_opp` for T6040 + the three cpufreq nodes +
   per-cpu `performance-domains`/`operating-points-v2`; `dtbs_check` +
   `make dtbs`; pin; then ticket 006 (already CJ-approved) is runnable — verify
   pstate transitions via `/sys/.../scaling_cur_freq`.

## Status

Ticket 035 stays **open**: the topology/node/driver audit is done and the DVFS
data source is located, but authoring the DT requires the ADT DVFM decode +
HW cross-validation above. No OPP frequency is written until it is decoded and
validated — inventing pstate freqs is both forbidden and unsafe (wrong V/f).
