# M4 (T6040/T8140) internal NVMe is behind SPTM — is there a boot-object path in?

*Draft for #asahi-dev — 2026-07-14. Review before posting.*

Working T6040 (Mac16,8 / J614s) bring-up, tethered over DebugUSB, mainline Linux
to BusyBox with the storage stack otherwise ready (PCIe parents forced
actual-active, CoastGuard SART v3 activated, ANS RTKit booted,
`APPLE_ANS_BOOT_STATUS_OK`). The remaining wall is the queue interface, and it's
an SPTM wall, not a DT/PMGR/SART one. Before we invest in either direction, does
anyone know whether a permissive/custom boot object can legitimately get inside
SPTM on M3/M4?

**What we found (static, from the paired 26.x kernelcache, Darwin 25.5.0
xnu-12377 RELEASE_ARM64_T6041):**

- The T8140-class controller rejects direct admin/IO queue programming. Main-BAR
  `AQA`/`ASQ`/`ACQ` and `MAX_PEND` fault; the secure BAR (`0x44dcc0000`) holds
  iBoot's own disabled-controller admin queue state.
- `AppleANS2CGv2Controller` drives queue setup through GENTER guarded calls, not
  MMIO. Selector `x16 = op | (service << 32)`; **service 6 = NVMe with ops 0..8**
  (read directly off the kernel's per-(service,op) GENTER veneer table). op 0 =
  init, op 1 = TCB auth, op 4 = admin-queue register `(ASQ PA, SQ depth-1,
  ACQ PA, CQ depth-1)`. Named ops incl. `SetupAdminQueue`,
  `Enable{Submission,Completion}Queue`, `EnableAutoQueueManage`,
  `SetupIOQARegister`, `NVMeCoastGuardSetTCB`, `GetNVMeSPTMProtocolVersion`.
- The guard-enter helper spins on `GXF_STATUS_EL1` (`s3_6_c15_c8_0`,
  `GUARDED=BIT0`) until idle, then GENTERs into SPTM at the guarded level.

**What raw m1n1 boot has:**

- M4 CPU advertises GXF (`AIDR_EL1` bit 16 set on Brava Chop).
- But at m1n1 runtime: `SPRR_CONFIG_EL1 = 0`, `GXF_CONFIG_EL1 = 0`,
  `GXF_STATUS_EL1 = 0`, and `GXF_ENTER_EL1`/`GXF_ABORT_EL1` reads trap. So iBoot
  hands the m1n1 boot object a non-guarded EL1/EL2 with no SPTM resident.
- Reproducing macOS's exact op-0/op-4 sequence from Linux hangs on the GENTER —
  no dispatch, no fault, watchdog recovers. Expected: no monitor behind the gate.

**The question.** Two ways we can see to get real NVMe:

1. Have iBoot load and enter the genuine signed SPTM for our (permissive) boot
   object, then drive the service-6 ABI above from Linux. Is there any documented
   boot-policy / boot-object path that does this on M3/M4, or is SPTM wired only
   for Apple-signed kernelcaches? The snapshot says it isn't happening for us
   today — is that fundamental or just unconfigured?
2. Otherwise, internal NVMe implies an open SPTM-equivalent monitor servicing
   service 6 (secure PT + SART allow-listing + per-command TCB). Is TCB
   authorization cryptographically bound to the real SPTM (making a re-impl a
   non-starter), or is it structural?

If both are dead ends for now we'll ship USB-attached root as the daily-driver
storage path and treat internal NVMe as blocked on upstream M4 SPTM. Mostly
looking to not chase (1) if it's known-impossible, and to know whether (2) is
even theoretically open.

---

## Session notes (not for posting)

- Full ABI decode: `done/2026-07-14-t6040-sptm-service6-abi.md`. Route analysis:
  `done/2026-07-14-t6040-nvme-sptm-route-finding.md`. NVMe map:
  `done/2026-07-13-t6040-nvme-map.md`.
- Snapshot transcript: `logs/t6040-console-20260714-nvme-sptm.log`.
- m1n1 side: `supports_gxf()` needs `cpu_features->mmu_sprr`; `features_m4`
  (chickens.c) omits it, so `gxf_init()` never runs on T6040. m1n1's `gl_call`
  (gxf.c) is the M1/M2 own-GL-code model, which doesn't help here — enabling it
  just GENTERs into m1n1's own handler, not SPTM.
- Keep the ticket-007 selector table + the raw snapshot handy; they're the
  concrete evidence to attach if asked.
