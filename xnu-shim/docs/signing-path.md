# Phase 2 blocker — Permissive-Security kernelcache + shim kext signing path (scoping)

The shim only works if we can boot a **non-Apple-signed XNU-style kernelcache with our shim
kext linked in**, under Permissive Security, and have iBoot bring up genuine SPTM for it.
This doc scopes the open questions; none are resolved. It is the gate on Phases 2–4.

## What we need iBoot/boot-policy to do

- Accept a custom kernelcache under **Permissive Security** (the mode Asahi already uses to
  boot m1n1/Linux on M-series) — known-possible for m1n1; the new part is a *macOS/iOS-XNU-
  style* kernelcache rather than a raw m1n1 Mach-O.
- **Load and enter genuine SPTM** for that object. On M4, macOS boots with SPTM; the open
  question (asahi_neo's too) is whether iBoot keys SPTM activation off the OS/kernelcache
  *type* and whether a Permissive custom XNU KC gets SPTM or not. If it does NOT, this route
  is dead and we're back to route B (re-implement SPTM — near-infeasible).

## Open unknowns (fill before Phase 2 starts)

1. Does iBoot activate SPTM for a Permissive-Security, non-Apple-signed XNU-style KC on M4?
   (asahi_neo lists this as their key open question too — coordinate; ticket 055 escalation.)
2. Kext-into-kernelcache linking under Permissive: can we splice a shim kext into a custom
   KC and have it run at `IOPlatformExpert::start()` without full Apple signing?
3. Toolchain: `-target arm64-apple-macos`, no libc, kernelcache base address, KMOD_* glue.
   Does the project have (or can it obtain) the kernelcache-linking + IMG4 wrap path?
4. Which XNU do we base on — a stripped genuine XNU fileset (needs the matching version) or
   a minimal XNU stub sufficient to reach post-`init_xnu_ro_data`? Minimal stub is riskier
   (must replicate enough of the SPTM bring-up XNU does) but avoids shipping Apple XNU.

## Relationship to existing wallace/asahi work

- Permissive-Security boot of custom objects is established (m1n1). The delta is the
  XNU-style KC + SPTM activation, which is asahi_neo's unbuilt Phase 1 (Path B).
- IMG4 wrap/unwrap tooling exists in-tree/adjacent (pyimg4 used in the SPTM decode;
  asahi_neo scripts/wrap_im4p.py). Signing for Permissive is the gap, not IMG4 mechanics.

## Verdict

Phase 2 cannot start until unknown #1 is answered (SPTM-for-custom-KC). That is precisely
the #asahi-dev escalation (docs/asahi-dev-escalation.md). Until then, Phase 2–4 code stays
skeleton; the productive offline work is the interface/decode (P0, done this pass) and the
HV trace prep (ticket 053).
