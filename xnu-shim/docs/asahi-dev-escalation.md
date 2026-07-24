# #asahi-dev escalation — DRAFT (ticket 055). CJ posts; do not send from here.

Supersedes the ticket-010 framing ("can iBoot load genuine SPTM for a raw m1n1 object" —
answered no: raw m1n1 boots with GXF off, no resident monitor). Sharper question below,
with the evidence we've gathered so the ask is concrete, not open-ended.

---

**Subject: M4 internal NVMe via an XNU-shim that rides genuine SPTM — viable, and does the CoastGuard TCB survive an XNU→Linux pivot?**

Context: on M4 (T6041 family) macOS uses **SPTM** (confirmed: XNU SPTM runtime strings + NVMe
CoastGuard/SART in the kernelcache; PPL vestigial), and the internal NVMe controller only
accepts queue programming mediated by SPTM. Raw m1n1 boot has no resident SPTM, so any
NVMe SPTM call wedges (no monitor behind `genter`). We range-extracted the exact T6041
SPTM and decoded its guarded NVMe backend: 9 ops (`func_state[0..8]`: init → SetTCB →
invalidate TCB → queue/protocol configure → admin queues → IOQA → IOSQ → IOCQ → ANS
SHA), each gated by `allowed_functions`, with per-CID TCB DMA authorisation + SART.
The handler register contracts are byte-proven, including ASQ/ACQ addresses and depths.

The route we think is viable (essentially your XNU-shim idea, Path B, applied to NVMe):

1. Boot a Permissive-Security XNU-style kernelcache with a shim kext linked in.
2. Let XNU bring up SPTM normally through `init_xnu_ro_data` (registers NVMe dispatch
   table 6 / IOMMU id 2 as **XNU-callable**, `permissions = 0x12` per `IOMMU_bootstrap`).
3. Intercept at `IOPlatformExpert::start()` and pivot to Linux.
4. Linux-at-EL1 drives NVMe ops 0..8 against the now-resident SPTM.

Two questions where your read would save us a lot of rig time:

- **(Q1) Domain provenance across the pivot.** SPTM dispatch checks the *caller domain*
  from `TPIDR`/state, not the x16 immediate (per Steffin/Classen §5.4.1). Does a Linux
  kernel that took over EL1 post-`init_xnu_ro_data` remain tagged `XNU_DOMAIN` — i.e. can
  it issue XNU-domain SPTM calls — or does anything (exception return, CPU re-register,
  `TPIDR` reload) reset/clear the caller-domain such that Linux loses XNU credentials?

- **(Q2) NVMe CoastGuard TCB survival.** The per-CID TCB authorises DMA target ranges to
  the controller. If the shim hands off after XNU registered the admin/IO queues, does the
  controller/TCB state stay valid for a *different* EL1 owner, or is queue/TCB state latched
  to XNU's context (SEP/ANS-tied) such that Linux must tear down and re-register from op 0?

July discussion also noted that SEP loads APFS keys into the NVMe controller. We treat
that as additional secure-stack coupling, not as a way around SPTM/CoastGuard. Is the
key/controller state another handoff invariant we must preserve or explicitly rebuild?

The obvious EL2 experiment is unavailable: m1n1-HV cannot boot under T6040's SPTM/GXF
configuration, so we cannot trace macOS calls before building the shim. Is either domain
or TCB/key survival already known from M1/M2/M3 pmap/SPTM work?

*(Attachments CJ can include: the guarded-backend decode + the cross-review with the
capability-model analysis and the ticket-007 retraction.)*

---

Note for us: keep it a question, not a claim. We have NOT proven Q1/Q2. The static ABI is
complete; only an informed upstream answer or a future signed shim boot can resolve them.
