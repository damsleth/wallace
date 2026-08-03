# XNU/SPTM NVMe escalation draft — superseded

Status 2026-08-03: do not send.

This draft asked whether a permissive XNU kernelcache could start genuine SPTM
and hand its NVMe capability to Linux. Direct m1n1 and Linux ANS bring-up later
worked without that pivot, so the question is no longer on the project’s
critical path.

The unresolved research questions remain:

- whether a post-XNU Linux kernel retains `XNU_DOMAIN` caller provenance;
- whether CoastGuard queue and TCB state survives a different EL1 owner;
- whether a permissive custom XNU-style kernelcache starts genuine SPTM.

Raise them externally only if the direct ANS route is proven insufficient and
CJ chooses to reopen the shim plan. External posting remains CJ’s action.
