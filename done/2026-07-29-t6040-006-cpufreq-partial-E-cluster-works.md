# Ticket 006 (cpufreq) at maxcpus=5: the E-cluster policy works and transitions both ways; no P policy appears

2026-07-29, over KIS, rollback loader enrolled. Partial run, as agreed — full 006 wants all three
cluster policies and a cluster-2 core needs `maxcpus>=10`, which the `unpack_to_rootfs` fault blocks.

## PASS: real cpufreq on the E cluster

Kernel: `Image-macsmc-hid-type-fix-trackpad-nbcon-ppp` rebuilt with a new kbuild `CPUFREQ=1` switch
(`ARM_APPLE_SOC_CPUFREQ` was `=m` in the base config and the RAM image has no module loader — it is
now asserted `=y` alongside the performance/powersave/schedutil/userspace governors).
DTB: 035's `t6040-j614s-dcuart-cpufreq.dtb`. Root: `initramfs-dcuart.cpio.gz`. `maxcpus=5`.

```text
driver: apple-cpufreq
policy1: affected_cpus=[1 2 3 4]  related=[1 2 3 4]
         cpuinfo_min=1020000  cpuinfo_max=2592000  gov=schedutil
available governors:   ondemand userspace powersave performance schedutil
available frequencies: 1020000 1404000 1788000 2112000 2352000 2532000 2592000
performance -> scaling_cur_freq = 2592000      (2.592 GHz)
powersave   -> scaling_cur_freq = 1020000      (1.02 GHz)
```

Seven P-states, matching 035's board-derived **E 7-pstate** table exactly, and **verified transitions
in both directions** — not merely a policy appearing. That is 006's core mechanism (driver + DT
wiring + OPP table + APSC writes) demonstrated working on real hardware.

Cluster identity check: `policy1`'s cpus 1–4 are the four E cores (part `0x054`), consistent with the
topology measured earlier today.

## OPEN: neither P cluster gets a policy, and I do not know why

Only `policy1` exists. `cpu0` — which is a **P0 core** (boot CPU, MPIDR `0x10100`) and is online —
has no `cpufreq` directory at all. There is **no error in dmesg**, including under the greps that
would catch this driver's own `dev_err` strings ("cluster", "failed to add/get/mark", `cpuN:`), so
`apple_soc_cpufreq_init()` appears never to have been *called* for those clusters rather than called
and failed.

Two hypotheses of mine were tested and **refuted**:

1. *"Both P clusters share one `opp-shared` OPP table, which contradicts their separate
   `performance-domains`."* I split the table — added `everest_opp2: opp-table-2` and repointed
   `cpu_p10..p14` — rebuilt the DTB (`43dd77ff`) and booted. **No change**; still only `policy1`. The
   split is retained on correctness grounds (two distinct clock domains should not share an
   `opp-shared` node) but it is **not** supported by evidence and fixed nothing observable.
2. *"The DT is missing the P-cluster wiring."* It is not. Verified from the DTB: `cpu@0-3` →
   `cpufreq@210e20000`, `cpu@10100-10104` → `cpufreq@211e20000`, `cpu@10200-10204` →
   `cpufreq@212e20000`, each with `operating-points-v2`. `cpu@10105` (the known-dead core) correctly
   has none.

Relevant driver detail for whoever picks this up: `apple_soc_cpufreq_find_cluster()` uses
`of_perf_domain_get_sharing_cpumask(policy->cpu, "performance-domains", …)` to fill `policy->cpus`,
then requires `of_match_node()` on the target node. The E cluster is the only cluster whose CPUs are
**all** online at `maxcpus=5` (P0 = {0,5,6,7,8} has only cpu0 up; P1 has none), which is the most
obvious remaining correlation — but I have not established causation and will not assert it.

**Next step is code reading, not another boot:** how `cpufreq_online()` and
`of_perf_domain_get_sharing_cpumask()` behave when part of the domain's cpumask is offline. If that
is the cause, the fault is cosmetic and full 006 simply needs `maxcpus>=10`, i.e. it collapses into
the SMP bug. If it is not, there is a second independent bug.

## Artifacts

- kbuild gains `CPUFREQ=1` (config + post-`olddefconfig` re-apply + builtin assertion + DTB build).
- `dts/t6040-j614s-dcuart-cpufreq.dts`: added `opp-table-2`; DTB now `43dd77ff…`.
- Console transcript in `linux-build-out/dcuart-console.log` at the time of writing.
