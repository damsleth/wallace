# T6040 NVMe SPTM route-finding — go/no-go (2026-07-14)

Ticket 008 (offline, P0, storage track). Decision writeup: can raw m1n1 boot
acquire the protected execution state the M4 NVMe controller requires, via a
documented loader transition — or must internal storage wait for upstream Asahi
M4 SPTM support? Builds directly on the ticket-007 ABI decode
(`done/2026-07-14-t6040-sptm-service6-abi.md`). Pure static reasoning; no rig, no
MMIO, no storage access.

## Verdict

**Internal NVMe under raw m1n1 boot: NO-GO in the near term.** There is no
documented loader transition by which a third-party (non-Apple-signed) boot
object acquires Apple's SPTM-guarded execution state. Acquiring it needs one of
two upstream-scale efforts (real signed SPTM loaded for the Asahi boot object,
or an open re-implementation of the SPTM NVMe backend); neither is a local m1n1
register change.

**Daily-driver storage: GO via USB-attached root** (tickets 009 / 031 / 032).
That path does not touch the internal SSD's SPTM-gated controller and is the
honest "machine boots Linux from disk" milestone while the internal-NVMe
question sits with Asahi (ticket 010).

## The requirement (from ticket 007)

The M4/T8140-class NVMe controller does not accept direct admin/IO queue
programming. Queue registration, TCB authorization, and activation are mediated
by Apple's SPTM through the GENTER guarded-call ABI: selector
`x16 = op | (service << 32)`, service 6 = NVMe, ops 0..8 (op 0 init, op 1 TCB
auth, op 4 admin-queue registration). The op implementations live in Apple's
signed SPTM firmware at the guarded level, not in the kernel/driver. Direct
main-BAR and secure-BAR writes fault. So "own the NVMe queues" == "issue
service-6 GENTER calls that a live SPTM services."

## What raw m1n1 actually provides (evidence)

1. **The M4 CPU has GXF.** `AIDR_EL1 = 0xd168699696` on T6040 has bit 16
   (`AIDR_EL1_GXF`) set — the Guarded Exception Framework is present in hardware.
2. **m1n1 leaves GXF off on M4.** `supports_gxf()` requires
   `cpu_features->mmu_sprr`; `features_m4` in `chickens.c` deliberately omits it
   ("XXX figure out what features are actually available on M4"), so `gxf_init()`
   is never called on T6040. This matches the raw-boot snapshot
   (`logs/t6040-console-20260714-nvme-sptm.log`): `SPRR_CONFIG_EL1 = 0`,
   `GXF_CONFIG_EL1 = 0`, `GXF_STATUS_EL1 = 0`, and `GXF_ENTER_EL1` /
   `GXF_ABORT_EL1` reads trap (guarded sysregs inaccessible while GXF disabled).
3. **m1n1's GXF is the M1/M2 model, not SPTM.** `gxf.c`/`gl_call` enable SPRR +
   GXF and `gxf_enter` (GENTER) into a function pointer **m1n1 itself supplies**
   at the guarded level. There is no signed monitor; m1n1 *is* the guarded code.
   This is fine on M1/M2, where the NVMe controller needs no guarded mediation
   and Asahi programs the queues directly.

The target kernelcache's guard-enter helper (ticket 007) spins on
`mrs GXF_STATUS_EL1` (`s3_6_c15_c8_0`, `GXF_STATUS_GUARDED = BIT(0)`) until the
gate is idle, then GENTERs — i.e. macOS reaches it with GXF live and SPTM
resident. Raw m1n1 reaches the same instruction with GXF off and no monitor
behind it, so the prior op-0/op-4 attempt wedged: GENTER had no valid guarded
vector, never dispatched, never faulted, watchdog recovered.

## Why enabling m1n1's own GXF does not solve it

Setting `mmu_sprr` for `features_m4` and calling `gxf_init()` would give M4 the
same M1/M2-style GXF: GENTER would jump to **m1n1's own** GL handler. Issuing
`x16 = service6 | op` would then land in m1n1 code with the selector in a
register — and m1n1 would have to *implement the entire service-6 backend
itself*: the secure page tables, CoastGuard/SART entry authorization, and the
per-command TCB that the NVMe controller validates. That is re-implementing
SPTM, not "acquiring protected exec state." The controller's protection is
anchored in the real SPTM's state; a home-grown GL handler does not satisfy it.

## The three routes

**A — Load the real signed SPTM for the Asahi boot object.** On M3/M4 Apple's
secure boot loads SPTM (+TXM) into the guarded levels for the *signed*
kernelcache and enters guarded state before the kernel runs. The open question
is whether iBoot can be induced to load and start the genuine SPTM for a
permissive/custom (m1n1) boot object, after which m1n1/Linux would drive the
service-6 ABI that ticket 007 decoded. The raw-boot snapshot shows iBoot does
**not** leave the m1n1 object in guarded state today. Whether any documented
boot-policy path changes that is exactly the #asahi-dev question (ticket 010).
If iBoot only wires SPTM for Apple-signed objects, this route is closed without
Apple changes. *Status: unknown; not a documented facility today.*

**B — Open re-implementation of the SPTM NVMe backend.** m1n1 enables GXF on M4
and provides its own guarded monitor implementing service 6 (secure PT, SART
authorization, TCB). Large RE + security-critical effort, and it may be
infeasible if TCB authorization is cryptographically bound to the real SPTM.
*Status: upstream-scale; speculative.*

**C — Avoid the internal controller: USB-attached root.** External NVMe/SSD or
Ethernet over USB2 host mode makes the machine daily-drivable without the
SPTM-gated internal SSD. Already scoped in tickets 009 (design), 031 (USB2 host
DT audit) and 032 (reproducible external-root artifacts). *Status: the practical
GO; in progress.*

## Recommendation

1. Treat internal NVMe as **blocked on upstream M4 SPTM support** (route A or B).
   Do not spend rig time trying to force service-6 GENTER from raw boot; the
   ticket-007 decode already proved the ABI is not the missing piece.
2. Make USB-attached root (route C) the storage path for the daily-driver
   milestone (tickets 009/031/032).
3. Escalate route A precisely to Asahi via ticket 010: *does the M3/M4 boot chain
   provide any documented way for a permissive/custom boot object to have iBoot
   load and enter genuine SPTM, exposing the service-6 NVMe ABI — or is internal
   NVMe gated on an open SPTM re-implementation?* Attach the ticket-007 ABI decode
   and this route analysis as evidence (draft only; CJ posts).

## Scope discipline

No admin command, Identify, namespace read, mount, or storage write occurred or
is justified by this analysis. All evidence is static: m1n1 source
(`gxf.c`, `chickens.c`, `cpu_regs.h`, `main.c`), the ticket-007 kernelcache
decode, and the read-only raw-boot guarded-state snapshot.
