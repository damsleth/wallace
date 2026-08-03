# Permissive XNU kernelcache signing path — parked

Status 2026-08-03: unresolved and not active.

The former shim plan required iBoot to accept a custom XNU-style kernelcache,
start genuine SPTM, and run a linked shim before Linux handoff. None of these
requirements is established:

1. genuine SPTM activation for a permissive custom kernelcache;
2. custom kext linking and execution at the required XNU point;
3. a reproducible kernelcache build, signing, and IMG4 packaging path;
4. preserved SPTM caller-domain and NVMe queue state across handoff.

Because the direct m1n1/Linux ANS path now reaches real filesystem I/O, solving
this signing stack would add risk without addressing the observed Linux
CQ-wrap assert. Retain the question for research; do not begin implementation
unless the conditions in `../README.md` are met.
