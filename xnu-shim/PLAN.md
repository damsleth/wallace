# XNU/SPTM NVMe shim — superseded research plan

Status 2026-08-03: **parked; do not implement**.

The original plan assumed T6040 internal NVMe required a live XNU/SPTM domain
after handoff. Later work disproved that as the immediate blocker:

- raw m1n1 initializes ANS and sustains reads across several completion-queue
  wraps without resident SPTM;
- Linux initializes ANS, enumerates namespaces, and briefly mounts the exFAT
  partition;
- the remaining Linux failure is a CoastGuard firmware assert at the first I/O
  CQ wrap.

The active route is therefore the T8132-style m1n1/Linux ANS work tracked by
tickets 192, 201, 203, and related experiments. The XNU shim adds a custom
kernelcache, signing, domain-provenance, and handoff problem without addressing
the observed CQ-wrap failure.

## Retained value

The files under `xnu-shim/` remain useful as static research:

- decoded guarded NVMe operations and argument shapes;
- SPTM domain and permission questions;
- skeleton interfaces that issue no hardware operation;
- historical escalation and signing questions.

They are not a live implementation base and do not authorize a rig experiment.

## Conditions to reopen

Reconsider this route only if all of the following become true:

1. the direct m1n1/Linux path is shown to require an SPTM-owned capability that
   cannot be reproduced safely;
2. upstream provides a credible permissive XNU-kernelcache and genuine-SPTM
   boot path on T6040;
3. caller-domain provenance across an XNU-to-Linux pivot is understood;
4. the work has a concrete advantage over fixing the current CQ-wrap contract.

Until then, tickets 114–117 remain offline research only. No shim, custom
kernelcache, SPTM call, or handoff should be built for the rig.
