# 🎉 Ticket 006 SOLVED — P-cluster cpufreq was a 32-bit overflow in apple-soc-cpufreq (upstream bug)

2026-07-30 autonomous rig session. Both clusters now register and transition; the M4 Pro's P cores
run at **4.512 GHz** under Linux for the first time (previously locked at m1n1's parked pstate 6 =
2.616 GHz — a ~72 % single-thread deficit, now gone).

## The bug

`drivers/cpufreq/apple-soc-cpufreq.c`, `apple_soc_cpufreq_init()`:

```c
unsigned long rate = freq_table[i].frequency * 1000 + 999;
```

`frequency` is `unsigned int` kHz; the multiply is evaluated in 32 bits before widening. Every
pstate above 4,294,967 kHz wraps — the everest table's 4,416,000/4,512,000 kHz entries become
~121/~217 MHz, `dev_pm_opp_find_freq_floor()` lands below the lowest OPP and returns `-ERANGE`,
and init fails through its **only print-free error path**. The policy silently never registers.

No M1/M2/M3 cluster exceeds 4.294 GHz. **The M4 P cluster is the first Apple cluster past the
32-bit kHz→Hz boundary**, which is why upstream has never seen it, and why our E cluster
(max 2.592 GHz) worked while both P clusters failed with zero dmesg output.

Fix: `patches/t6040-apple-cpufreq-freq-mult-overflow.patch` (widen before multiplying), applied in
kbuild whenever present. **Draft for CJ → upstream/asahi** — this bites every M4+ machine.

## How it was found (method note)

1. Code reading mapped every silent exit: core swallows `->init()` errors with `pr_debug`; in the
   driver only the EPROBE_DEFER path (dev_dbg) and two print-free paths (`kzalloc`, the
   `find_freq_floor` driver_data loop) fail without a `dev_err`.
2. `DIAG=1` kbuild switch (CONFIG_DYNAMIC_DEBUG) + `dyndbg="file drivers/cpufreq/* +p; file
   drivers/opp/* +p"` boot at maxcpus=5: cpu0's OPP table added all 19 levels cleanly, then
   `cpufreq_policy_online: 1431: initialization failed` with the deferral message conspicuously
   absent → eliminated everything except the two print-free exits → the loop's multiply is the
   only frequency-dependent code left, and 4416000 × 1000 > UINT32_MAX.
3. Rebuilt with the one-line fix, rebooted: policy0 present, transitions verified.

## Verified live (maxcpus=5, diag kernel + fix)

```
policy0: cpu 0        1260000-4512000  gov=schedutil
  performance -> 4512000
  powersave   -> 1260000
policy1: cpus 1 2 3 4 1020000-2592000  gov=schedutil   (E, verified 07-29)
```

P1 has no policy at maxcpus=5 because none of its CPUs are online — correct behavior, not a bug.
Full three-policy validation folds into the maxcpus>=6 SMP ticket (121).

## Corrections to prior claims

- The `opp-shared` split (everest_opp2) was **not** the fix and never changed anything; the DTS
  comment claiming causality is corrected (kept on DT-semantics grounds only).
- My 07-29 greps would have missed core pr_errs (`->get() failed`, `Failed to initialize policy`)
  — irrelevant in the end (nothing printed at all), but the grep pattern claim was overbroad.
- 07-29's "apple_soc_cpufreq_init seemingly never called" was wrong: it was called and failed
  silently after successfully adding the OPP table.

## Artifacts

- `Image-macsmc-hid-type-fix-trackpad-nbcon-ppp-diag` (DIAG kernel with fix, on /out)
- kbuild: `DIAG=1` switch (dynamic debug), `CPUFREQ=1` now suffixes `-cpufreq` (no more silent
  overwrite of the daily image name), builds `t6040-j614s-dcuart-wifi-cpufreq.dtb`
- DTS refactor: payload moved to `dts/t6040-cpufreq.dtsi`; new combined
  `dts/t6040-j614s-dcuart-wifi-cpufreq.dts` for the daily-driver object
