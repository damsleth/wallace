# m1n1 cpufreq report for T6040 (M4 Pro)

**Ready for CJ to post to `#asahi-dev` (finalized 2026-07-23).** The text in
the next section is the posting draft. Nothing has been posted externally.

## Posting draft

I have a minimal m1n1 cpufreq path working on T6040
(Mac16,8/J614s, M4 Pro), with the throttle block deliberately disabled pending
the M4 register map.

T6040 reuses `t6031_clusters` unchanged. I verified the three cluster PSTATE
bases against the live ADT topology and guarded reads:

```text
ECPU0  0x210e00000
PCPU0  0x211e00000
PCPU1  0x212e00000
```

`CLUSTER_PSTATE` at `+0x20020` reads sane values on every cluster.
`cpufreq_init()` enables APSC, reaches the nominal pstates (E=5, P=6), and
clears BUSY without a switch timeout. The measured 4E + 5P + 5P topology also
matches the three table entries.

The T6030 throttle offsets must not be reused on T6040. Reads of `0x40250` or
`0x40270` on a P cluster raise an asynchronous SError, which bypasses the m1n1
exception guard and kills the proxy. The E-cluster `0x40250` read also faults.
The ADT says `ppt-thrtl`, `llc-thrtl`, and `amx-thrtl` exist, but it does not
describe their register offsets.

My conservative patch therefore:

- adds T6040 to the existing PSTATE/cluster dispatch;
- exposes only `cpu-apsc` and `cpu-fixed-freq-pll-relock`, both through the
  validated `CLUSTER_PSTATE` register; and
- performs no T6040 misc/throttle write, including the unverified `+0x440f8`
  write used by T6030.

Does anyone have the T6040/M4 ppt/llc/amx throttle map, or a pointer to the
macOS code which programs it? I can send this pstate/APSC-only patch now and
leave the throttle features for a follow-up. I will not probe additional
offsets on the machine because these failures are asynchronous SErrors rather
than guardable aborts.

## Maintainer notes and evidence

- Local patch commit:
  `c009ef6839cb03186674be182bc4ab66838e0971`
  (`cpufreq: minimal conservative t6040 support`).
- The working code has four dispatch additions, a no-op T6040 misc case, and a
  dedicated two-entry `t6040_features[]`.
- Live PSTATE and failure detail:
  `done/2026-07-10-t6040-cpufreq-plan.md`.
- Linux DT/OPP audit, including the decoded J614s DVFM tables:
  `done/2026-07-23-t6040-cpufreq-dt-preflight.md`.
- The later Linux DT work does not change the m1n1 safety conclusion: hardware
  owns voltage selection, while unknown throttle offsets remain untouched.

## Patch hygiene

- `git diff --check c009ef68^ c009ef68`: pass.
- Every changed C line passes ranged
  `clang-format 22.1.8 --dry-run --Werror` with the repository style. CI's
  pinned clang-format 20 was not installed locally.
- Linux `checkpatch.pl --strict` was run for disclosure. It reports thirteen
  indentation errors and eleven warnings because Linux checkpatch requires
  kernel tabs; m1n1 uses four-space indentation, so these are inapplicable.
- The posting draft above is ready. Actual patch-mail rebasing and series
  ordering remain ticket 046; do not mail the historical commit unchanged.
