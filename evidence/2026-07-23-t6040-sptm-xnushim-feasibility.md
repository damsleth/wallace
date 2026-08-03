# M4 internal-NVMe XNU-shim feasibility checkpoint

Date: 2026-07-23
Ticket: 055
Result: offline foundation complete; implementation remains blocked

The XNU-shim route is internally coherent but still a low-confidence,
upstream-scale bet. Raw m1n1 cannot load or impersonate SPTM. The only plausible
route is to boot a permissive XNU-style kernelcache, let genuine SPTM establish
the NVMe/SART/CoastGuard boundary, intercept after `init_xnu_ro_data`, then
pivot to Linux while preserving the XNU caller domain and controller state.

Static uncertainty has been reduced substantially:

- exact T6041 SPTM registers NVMe dispatch table 6 / IOMMU id 2 with XNU and
  XNU-hibernate permission mask `0x12`;
- all nine guarded handler arguments are byte-proven;
- the ABI is structurally stable across T8132, T8140, and T6041;
- T6041 adds segment-count and NLB enforcement;
- the old service-6 veneer ABI and pre-build m1n1-HV trace ideas are retired.

Two decisive risks remain:

1. whether Linux after the XNU pivot still executes as `XNU_DOMAIN` in SPTM's
   tracked state, rather than merely writing an XNU-looking descriptor;
2. whether CoastGuard TCB/CID, SART mappings, queue ownership, and SEP-loaded
   APFS key/controller state survive the change of EL1 owner.

Neither can be answered by more raw-m1n1 experiments. The next legitimate
inputs are an upstream answer to the sharpened draft in
`xnu-shim/docs/asahi-dev-escalation.md` (CJ posts, never this agent) or a future
signed permissive-kernelcache shim proof. The signing/build path is itself
unresolved.

The repository now contains the complete safe P0 foundation: guarded interface,
argument contract, bring-up-order skeleton, loader/FDT/shim skeletons, signing
scope, and escalation draft. `sptm_nvme_call()` remains a hard stub, so no code
can issue a malformed live call.

No external message, rig action, storage access, or proprietary binary was
committed.
