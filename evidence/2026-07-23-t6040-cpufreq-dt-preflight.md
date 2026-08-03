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

## DVFM table decoded (2026-07-23)

`ipsw dtree --json` mangles the `voltage-states*` blobs (`voltage-states1` →
`['6y']`), so I read them from the raw ADT (`j614s-usb-port-map-20260721.adt`)
via m1n1's `adt.py` (`construct` in a scratch venv). Each `voltage-states<N>` is
u32 pairs; the **`-sram` sibling's word0 is the frequency in kHz**, decoded
cleanly to round MHz. Cluster mapping (validated below):

- **E-cluster (ECPU0, cpu@0-3)** = `voltage-states1`, **7 pstates**:
  1020, 1404, 1788, 2112, 2352, 2532, 2592 MHz.
- **P-cluster0 (PCPU0, cpu@10100-4)** = `voltage-states5`, **19 pstates**:
  1260 … 4512 MHz.
- **P-cluster1 (PCPU1, cpu@10200-4)** = `voltage-states13`, 19 pstates, identical
  `-sram` freqs to P0 (per-bin core voltage differs; HW-owned).

**Validation (not fabricated):** (a) E ps1 = 1020 MHz matches the known t6031
E-cluster base OPP; (b) the kHz encoding yields exact round MHz for every entry
(a wrong interpretation would not); (c) **P max = 4512 MHz = the documented M4
Pro P-core boost clock**; (d) freqs monotonic, voltages monotonic. Full decode:
scratchpad `dvfm-decoded.txt`. A read-only m1n1 HW-pstate read
(`cluster_base+0x70000+pstate*0x20`) remains a nice-to-have confirmation but the
four independent checks make the table trustworthy; the driver also sets pstate
by `opp-level` (HW applies the voltage), so `opp-hz` is a reporting/capacity
label, not a V/f command.

## Built artifact

`dts/t6040-j614s-dcuart-cpufreq.dts` — the proven dcuart console base +
`#include`, adding the three `apple,t8112-cluster-cpufreq` controllers
(reg = base+0x20000) and the two decoded OPP tables, wiring each CPU to its
performance domain via label overrides (`t6040.dtsi` untouched, so other
experiments' base DT is undisturbed). Built + verified (kernel dtc): 3 cpufreq
nodes, `cpu@0` carries `operating-points-v2` + `performance-domains`, P-max
`opp-hz = 0x10cefa800` = 4,512,000,000. **DTB SHA-256
`a42bb096ea3d302ec7486d9f96e3068b1106d9a8285ffdb57802d5b65d43e4dc`.** dtc-clean.

## Ticket 006 run requirements

- Kernel must have `CONFIG_ARM_APPLE_SOC_CPUFREQ=y` (verify in the dcuart build;
  add if absent — a config-only rebuild, no source change).
- Boot the cpufreq DTB above + the dcuart console kernel + a reporter that reads
  `/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq` and drives a governor
  step; pass = pstate transitions observed on E and P policies. Cross-review the
  final pinned set (kernel/m1n1/DTB/initramfs) before the CJ-approved boot.

## Status: **035 done.** DVFM decoded, OPP authored, DTB built + pinned. 006 is
runnable pending the `CONFIG_ARM_APPLE_SOC_CPUFREQ` kernel confirmation + a
reporter initramfs + cross-review. cpufreq is a Stage-C comfort, not a boot
blocker.
