# T6040 m1n1 upstream-series preparation (2026-07-23)

Ticket 046 (offline, P1, cross-cut). The 22-commit diagnostic/bring-up history
has been reduced to a nine-patch review series on current AsahiLinux m1n1 main,
with a cover letter, exact hashes, clean-apply test, and repeatable host build.
Nothing was posted externally and no image was run on the M4.

## Durable outputs

- m1n1 branch: `codex/t6040-upstream-series`
- upstream base: `7c7716b6a196c7e601f9f22bb8af335c1b8173ce`
- branch tip: `37fafb86814c8dba0e3552a7cac437e4c685b1f0`
- branch tree: `3f26933ad352aed097db82a9e128e9c5ddf4bfd0`
- mail draft: `patches/m1n1-t6040-upstream-v1/`
- cover letter: `0000-cover-letter.patch`
- per-file hashes: `SHA256SUMS`

Every patch is authored and signed off as:

```text
CJ Damsleth <kim@damsleth.no>
```

The mail is an `[RFC PATCH 0/9]` draft. The maintainer decides whether and
where to post it.

## Baseline and drift audit

Before refreshing upstream, the curated `t6040-bringup` tip `f0738eee` and
Wallace main's reviewed `16b1f61f` had no source drift under `src/` or
`proxyclient/`; their only tree difference there was local `AGENTS.md`
documentation. Wallace main's newer `e4671e08` adds the unapproved PCIe
operation-115 candidate and is intentionally not a series input.

AsahiLinux main had advanced from the curated base `fd20d7f7` to `7c7716b6`.
The important new upstream commits are:

- `d3699d53` — initial T6041 identity/CPU-start support;
- `0f221fc7` — T8132/T6040 PCIe recognition and the moved PHY-reset bit;
- `7c7716b6` — proper four-level paging.

The series was rebased onto this new tip. T6041 identity, CPUSTART, and the
T6040 PCIe reset-bit support were not duplicated. The log-ring upper guard
still applies and builds on the new paging code.

## Shaped series

| # | Commit | Purpose |
|---|---|---|
| 1 | `e6d8d5e8` | M4 `broken_wfi`: park secondaries in WFE |
| 2 | `50b09d63` | bounded `wdt_arm_secs()` helper |
| 3 | `8f1670f3` | per-SoC DAPF gate, retaining required T6040 MTP |
| 4 | `d1a822a8` | verified T6040 display carveouts + handoff watchdog |
| 5 | `6c50b3f4` | ADT-driven T6041 MCC; fixes the `u64` format warning |
| 6 | `cbe92176` | conservative T6040 PSTATE-only cpufreq |
| 7 | `3f616efe` | separate PMGR policy from topology generation |
| 8 | `73103592` | stage-2 log-ring upper guard |
| 9 | `37fafb86` | RFC-only proven T6040 PCIe clock prefix |

Patches 1–8 retain the curated changes with only the MCC format correction.
Patch 9 replaces eleven historical PCIe bring-up/trace commits with one small
delta on top of upstream's new T6040 support.

## PCIe scope

Upstream now recognizes `apcie,t6040` using the T8132-like reset bit. J614s
also has:

- `apcie-cio3pllcore-tunables` at ADT `reg[5]`;
- `apcie-pcieclkgen-tunables` at ADT `reg[6]`;
- Apple ordering that enables PMGR gates 0–6, applies controller/clock
  tunables, then enables gate 7 (`APCIE_PHY_SW`).

Patch 9 encodes only that complete live-proven prefix and then returns before
shared-PHY setup. It does not execute the unresolved first PHY-IP access
(operation 115), touch a port, or claim working PCIe. The local `e4671e08`
operation-115 PLL candidate, tunable tracing, L2 status diagnostic, and
read-only operation-115 probe are all excluded.

This exact rebased patch has not run on the M4 and is not a live candidate.

## Excluded history

The range-diff deliberately drops:

- `proxyclient/experiments/t6040.py` — bring-up helper, not platform support;
- PTY transport and noninteractive `linux.py` policy — ticket 048 host tools;
- ten intermediate PCIe trace/control commits — experimental archaeology,
  collapsed into patch 9's reviewed source boundary;
- the operation-115 read/candidate — unresolved and not approved.

The curated `t6040-bringup` branch remains intact as the record of what ran.

## Validation

The generated patch files were applied with `git am` to a detached clean
`7c7716b6` worktree. The applied tree exactly matched the branch:

```text
branch_tree=3f26933ad352aed097db82a9e128e9c5ddf4bfd0
applied_tree=3f26933ad352aed097db82a9e128e9c5ddf4bfd0
```

`git diff --check` passed. Two clean arm64-Darwin builds with LLVM 22.1.8 and
Rust nightly plus `aarch64-unknown-none-softfloat` reproduced:

| Artifact | SHA-256 |
|---|---|
| `build/m1n1.bin` | `f615a4ef538147cf434b32b851ebd39a00e0a3bbbc66df25feca2f97b2806f4b` |
| `build/m1n1.elf` | `f7d9150afb95314fdeb2610f08b5f0071990836b289704994b5f4ceefc5e3468` |

The remaining compiler warnings are existing upstream warnings in
`dcp_iboot.c` and Rust's unused nightly feature; the new MCC format mismatch
was fixed before export.

No rig lease, chainload, MMIO, enrollment, GitHub/IRC post, or remote branch
push occurred.
