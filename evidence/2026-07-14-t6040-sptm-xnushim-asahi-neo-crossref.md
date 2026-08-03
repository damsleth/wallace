# T6040 SPTM ⇄ asahi_neo cross-review: XNU-shim route, SPTM-vs-PPL, new experiments (2026-07-14)

Follow-up to tickets 007/008 (`done/2026-07-14-t6040-sptm-service6-abi.md`,
`done/2026-07-14-t6040-nvme-sptm-route-finding.md`). Cross-reads `~/Code/asahi_neo`
(XNU-shim boot project, target A18 Pro / t8140) against the T6040/M4 NVMe-SPTM
blocker. Four questions from CJ. Static analysis only; read-only string/symbol greps
and a byte-level GENTER decode over the already-staged M4 kernelcache — no rig, no
MMIO, no storage.

> **CORRECTION (read this first):** a byte-level re-examination of the GENTER sites
> this session **retracts ticket 007's "service-6 = NVMe" x16 ABI** — no
> `movk x16,#6,lsl#32` exists in the binary; the caller-side encoding carries only an
> endpoint (table/domain = 0), plus `txm_enter`/`sk_enter` domain gates. See
> **"Veneer re-examination — CORRECTION to ticket 007"** below. Where earlier sections
> say "service 6," read it as "SPTM-internal dispatch table 6 = NVME (A.3)," which is
> real, **not** an x16 field XNU sets. The go/no-go verdict is unaffected.

TL;DR: (Q2) On M4 it is **SPTM, confirmed** — now with XNU-runtime + NVMe-CoastGuard
string evidence, not inference; the PPL question is closed for M4. (Q1) The XNU-shim
boot *is* ticket-008 "Route A" given a concrete mechanism, and is the most credible
long-term path to internal NVMe — but it is a large architectural pivot with several
unproven links, and asahi_neo has never runtime-exercised the SPTM NVMe path on their
own hardware. (Q3/Q4) asahi_neo hands us real assets — an M4-family SPTM blob, the
Steffin/Classen paper, and a capability-model argument that route-B's "crypto-bound
TCB" fear is likely unfounded — enabling several concrete decode experiments. The paper
(read firsthand, primary-source section below) **confirms table 6 = NVME and that the
NVMe dispatch table is registered XNU-callable** (`permissions = 0x12`), and shows
dispatch is a coarse caller-domain capability check (not per-caller crypto) — which is
the mechanism that makes the shim route viable in principle. None of this changes the
near-term verdict: **USB-attached root stays the daily-driver path.**

---

## Q2 — Are we 100% sure it is SPTM and not PPL? (answer first; it grounds the rest)

**Yes for M4/T6041 — now confirmed at string/symbol grade.** asahi_neo is exactly
the reason to have asked: it proved the naive "newer silicon ⇒ SPTM" assumption
*wrong* for macOS on A18 Pro (t8140) — 0 `genter`, pure PPL, SPTM blob present on
disk but never loaded for the macOS boot. So the label had to be earned on the M4
image, not assumed. Ticket 007 inferred SPTM from the `genter` veneer table; it never
ran asahi_neo's own negative controls. I ran them against the staged target
(`/private/tmp/t6040-ipsw/kernelcache.mac16j.raw`, Darwin 25.5.0 T6041):

- **`genter` present in quantity** — ~162 raw 4-byte matches for `20 14 20 00`
  (ticket 007 disassembled 151 real sites incl. the service-6 veneer table). vs
  **0** in asahi_neo's A18 Pro macOS kernel.
- **XNU is compiled and running SPTM** — verbatim runtime strings in the image:
  `"SPTM load address: %p"`, `"libsptm_init failed: %u"`, `"found CPU %d in SPTM"`,
  `"%s is unimplemented on SPTM-based systems"`,
  `"arm_init: Development SPTM / Release XNU is not a supported configuration"`,
  a `__DATA_SPTM` segment, `"Mismatch of ARM_LARGE_MEMORY in SPTM/XNU"`. These are
  boot-path assertions/log strings that only exist in an SPTM-configured kernel.
- **The NVMe protected path is SPTM+SART CoastGuard** — same image:
  `"Successfully enabled NVMe CoastGuard"`, `"NVMe CoastGuard disabled through boot-arg"`,
  `AppleSART/IOCoastGuardSARTMapper.cpp`, `sart,coastguard`, `NVMeSPTM`. This directly
  corroborates ticket 007's "service 6 = NVMe" from a second, independent angle.
- **PPL is vestigial, not the mechanism** — `pmap_in_ppl`=2, `pmap_cs`=36 (code-signing
  subsystem name, persists regardless), `_ppl`=12; **no** `ppl_enter`, `ppl_dispatch`,
  or `gxf_ppl`. Consistent with "PPL symbols linger as compat shims; the live path is
  SPTM," reinforced by the literal `"unimplemented on SPTM-based systems"` string.

Method caveat worth recording: the raw HINT-byte counts asahi_neo used as a PPL
"control" are **not reliable** — `HINT #0x1b`/`#0x1f` byte patterns hit 144k/35k times
in the 119 MB M4 fileset (overwhelmingly data false positives), and `HINT #0x22`
(= `BTI c`, `0xD503245F`) was **0** here vs their 88,770 on A18 Pro. Byte-grep does not
discriminate; the **symbol/string** controls above do. Confidence: SPTM on M4 is
settled. The only sliver short of literal 100% — that iBoot loads the sptm blob on
*this specific* boot rather than the KC merely being SPTM-configured — is closed for
practical purposes by the `arm_init` SPTM assertion + the raw-boot `genter` wedge
(ticket 007): a monitor was expected behind the gate and wasn't resident.

**Cross-repo correction that follows:** asahi_neo's easy path — "Path A: boot a
macOS-style kernelcache, iBoot won't activate SPTM, follow M1–M3 PPL" — is an
**A18-Pro-specific** artifact of *that* SoC's macOS using PPL. It does **not** transfer
to M4: the M4 macOS kernelcache is itself SPTM-configured. For M4 the relevant
asahi_neo path is **Path B (iOS/SPTM shim)**, the harder one.

---

## Q1 — Does the XNU-shim boot (asahi_neo) change the internal-NVMe verdict?

**It is the concrete instantiation of ticket-008 "Route A," and the best long-term
candidate — but it is a big pivot with unproven links, and does not move the near-term
go/no-go.**

Ticket 008's Route A was stated vaguely: "can iBoot be induced to load genuine SPTM
for a permissive/custom (m1n1) boot object?" The raw-boot snapshot said no — iBoot
leaves the m1n1 object in non-guarded state. asahi_neo supplies the missing mechanism:
**don't ask iBoot to bless m1n1 — ride a real XNU bring-up.**

Mechanism (Path B, mapped to M4):
1. Boot a permissive-signed XNU-style kernelcache that iBoot *does* load SPTM for.
2. Let XNU run through `gxf_setup_early → gxf_setup_late → init_xnu_ro_data`, at which
   point the dispatch tables — including the NVMe table (asahi_neo/paper: dispatch
   table id **6 = `SPTM_DISPATCH_TABLE_NVME`**, matching ticket 007's "service 6") —
   are registered against a **live, resident SPTM**.
3. Intercept post-`init_xnu_ro_data` (asahi_neo Option A: `IOPlatformExpert::start()`)
   and pivot to Linux.
4. Linux-at-EL1 then issues service-6 `genter`s that a **real SPTM services** — which
   is exactly the "protected execution state" ticket 008 said had no documented
   acquisition path.

Why it is more than hand-waving: the blocker in 007/008 is precisely *"no resident
initialized SPTM behind `genter`."* The shim makes SPTM resident legitimately. And the
Steffin/Classen dispatch model (now read firsthand — see the primary-source section
below) is **capability-by-domain, not per-caller cryptographic identity**: at dispatch,
SPTM checks the *caller domain* against the dispatcher's permission mask, where the
domain is a coarse capability (SPTM/XNU/TXM/SK/HIB) tracked in SPTM's own state
(`TPIDR` caller-domain field), established by execution context — there is no signature
or per-caller identity gate. Critically, the NVMe dispatch table is registered
**XNU-callable** (`IOMMU_bootstrap` hard-codes `permissions = 0x12` = XNU_DOMAIN |
XNU_HIB_DOMAIN for NVMe). This **undercuts route-B pessimism** in ticket 008 ("TCB auth
may be cryptographically bound to the real SPTM"): a shimmed Linux running in the
XNU-established EL1 context — hence tagged XNU_DOMAIN by SPTM — should satisfy the NVMe
table's 0x12 mask and drive service-6 without re-implementing SPTM.

Unproven links (why this is not a green light):
- **The whole shim is unbuilt.** asahi_neo `xnu_shim/` is a README; they are still
  stuck on m1n1 USB/PMU bring-up on A18 Pro. No XNU-shim boot has happened anywhere.
- **They have never runtime-exercised the SPTM NVMe path** — their hardware runs macOS
  under PPL, and NVMe is explicitly in their "Parking Lot (Deferred)." Their SPTM
  knowledge is paper- + blob-static, not observed.
- **The load-bearing residual risk is domain provenance, not identity.** The dispatch
  check reads the caller domain from SPTM state/`TPIDR`, not blindly from the x16 bits
  the caller supplies (§5.4.1, Fig 5.6). So the route works **iff** SPTM still tags the
  post-handoff Linux EL1 context as XNU_DOMAIN. Highly plausible (Linux runs in the very
  EL1 context XNU set up; the shim tears nothing down) but **untested** — this is what
  the HV probe must confirm.
- **CoastGuard TCB survival across the pivot is still unproven.** The NVMe CoastGuard
  TCB (service-6 op 1) authorizes **DMA target ranges** to the controller; whether that
  authorization survives an XNU→Linux pivot (or whether the controller latches queue
  state to XNU-registered addresses) is untested inference, separate from the dispatch
  capability question above.
- **Architectural cost.** This abandons Wallace's raw-m1n1→Linux model for
  XNU-then-pivot — new implications for m1n1's role, the DT path, and signing. It is an
  upstream-scale effort, same order as ticket 008 routes A/B.

**Verdict:** Keep the ticket-008 near-term call unchanged (internal NVMe blocked;
USB root is the daily-driver path). But **re-target the ticket-010 Asahi escalation**:
the sharp question is no longer "can iBoot load SPTM for m1n1" but *"is an XNU-shim
(ride real SPTM bring-up, intercept post-`init_xnu_ro_data`, drive service-6 from Linux
via inherited XNU-domain dispatch) a viable route to internal NVMe on M4 — and does the
NVMe CoastGuard TCB survive the pivot?"* That is a materially better-formed question and
should carry the ticket-007 ABI decode + the capability-model argument as evidence.

---

## Q3 — New experiments to glean from asahi_neo

1. **Disassemble the M4-family SPTM blob (highest value).** asahi_neo has
   `research/firmware/sptm.t8132.release.im4p` (M4-base; IM4P/`sptm`/`bvx2`=LZFSE,
   ~185 KB packed). Our exact T6040/T6041 variant lives in the M4 Pro/Max IPSW at
   `/private/tmp/t6040-ipsw`. Decompress and read the **table-6 dispatch
   implementations directly** — this byte-proves ops 2/3/5/6/7/8 that ticket 007 could
   only infer. Note: `extract_sptm_calls.py` found only **1** `genter` in the blob (its
   self-call) — dispatch inside SPTM is a **table lookup**, not more `genter`s, so the
   method is "locate `genter_dispatch_entry` → the per-domain/table function-pointer
   array → table 6's 9 endpoints," not "grep genter."
2. **HV `genter`-logging (Option C / `probe_sptm.py`).** Boot the M4 macOS kernelcache
   as an m1n1 EL2 guest, trap GXF transitions, log every service-6 call + args live →
   converts ticket 007's inferred op map into a confirmed one, including the full NVMe
   bring-up sequence. **Caveats before trusting it:** `probe_sptm.py` is a *stub* and
   still carries the invalidated `x0`-dispatch model (real ABI is x16); and Option C
   assumes m1n1 GXF support that our ticket 008 flagged **off on M4** (`features_m4`
   omits `mmu_sprr`, `gxf_init()` never called). Real work, high payoff.
3. **Static negative controls on the M4 image — DONE above (Q2).** Adopt the
   symbol/string method (not byte-grep) as the standing SPTM-vs-PPL test.
4. **Structural blob diff (`diff_sptm_blobs.py`).** t8132 (M4) vs t8140 (A18 Pro) is
   27% different; a Ghidra/r2 structural diff can locate the NVMe dispatch table and
   confirm the ABI offset layout, then map it onto our exact T6041 blob.
5. **Pull the Steffin/Classen paper** (`research/papers/steffin_classen_sptm_2025.pdf`,
   arXiv:2510.09272). Appendices A.3 (dispatch tables) / A.4 (endpoints) are the
   authoritative maps; A.2 domains. This is the source of "table 6 = NVME" and of the
   capability-model claim — read the NVMe-relevant sections firsthand rather than via
   asahi_neo's transcription.

---

## Q4 — Creative ways to decode the service-6 ABI (given it IS SPTM)

**Framing first (so effort isn't wasted):** decoding the ABI further does **not**
unblock raw-boot NVMe — ticket 007 already proved the ABI was never the missing piece;
the missing piece is a *resident, initialized SPTM*. So the value of a fuller decode is
(a) to drive NVMe **post-handoff in the XNU-shim route**, and (b) to **scope route B**.
Decoding for raw boot alone is a dead end.

1. **Guarded-side disassembly (authoritative).** In the decompressed M4 SPTM blob,
   find `genter_dispatch_entry`/`sptm_dispatch` (asahi_neo's A18 Pro symbol map gives
   analogous VAs as r2 base offsets), walk to table 6's 9-entry function-pointer array,
   disassemble each endpoint, and read its arg consumption + MMIO/SART/CoastGuard side
   effects. This is the only way to *prove* ops 2/3/5/6/7/8.
2. **Cross-anchor caller↔callee.** We already hold op-4's confirmed arg contract
   (x0=ASQ PA, x1=SQ depth-1, x2=ACQ PA, x3=CQ depth-1, x4=0) and op-0/op-1 confirmed.
   Match op-4's `(PA, depth, PA, depth)` signature to the blob endpoint that consumes
   x0..x4 that way — that pins table indexing, after which 2/3/5/6/7/8 read off by
   position.
3. **Dynamic differential trace (HV).** Under m1n1 EL2, trap-and-log both the `genter`
   args *and* the SART/DART/secure-BAR writes each op performs during real macOS NVMe
   init — reconstructs the controller-side contract (what op 4 writes to the IOQA
   register, what op 1 writes to the CoastGuard TCB). Cross-check against (1).
4. **Symbol-guided op resolution.** The caller-side ANS2 methods are named
   (`SetupAdminQueue`, `EnableSubmissionQueue`/`PolledEnable…`, `Enable*CompletionQueue`,
   `EnableAutoQueueManage`, `SetupIOQARegister`, `NVMeCoastGuardSetTCB`). Ticket 007
   couldn't map name→op because dispatch is `blraa`/PAC-vtabled through
   `_pmap_iommu_ioctl`. Targeted r2 emulation of the ioctl shim, or the HV trace in (3),
   resolves each named method to its op immediate.
5. **Version/SoC differential.** Diff the service-6 veneer table across the T6041 KC and
   the t8132 blob / other macOS builds to separate the *stable ABI structure* from
   chip-specific register offsets — hardens the decode against a single-image artifact.

---

## Primary-source confirmation — Steffin/Classen arXiv:2510.09272 (read firsthand 2026-07-14)

CJ supplied the paper (`~/Downloads/SPTM_TXM_Exclaves.pdf`, 174 pp). Read the appendix
ID tables (A.1–A.7) and the dispatch mechanics (§5.3.5, §5.4.1–5.4.2). This upgrades
several items above from asahi_neo-transcribed / inferred to **primary-source**. Note
the analyzed binary is A-series/iOS-class (SPTM symbol VAs `0xfffffff027…`); our
T6040/T6041 blob will differ in offsets but shares the ABI *structure* (domains, table
IDs, dispatch mechanism). The binary even carries multiple SoC DART variants incl.
`IOMMU_ID_DART_T6000`, confirming the SPTM image is generic across the family.

**Confirmed:**
- **Table 6 = `SPTM_DISPATCH_TABLE_NVME`** (A.3, header-derived) — matches ticket 007's
  "service 6." Also **NVMe = IOMMU id 2** and **SART = IOMMU id 1 / dispatch table 5**
  (A.5). The M4 NVMe protected path uses *both* NVMe and SART CoastGuard tables — which
  is exactly why the M4 kernelcache carries `IOCoastGuardSARTMapper` (Q2 strings).
- **Domains** (A.2): 0 SPTM, 1 XNU, 2 TXM, 3 SK, 4 XNU_HIB, 5 MAX. Permission-mask
  convention (Table 5.2): bit value `2^n` ⇒ domain n (0x2=XNU, 0x4=TXM, 0x8=SK,
  0x10=XNU_HIB).
- **Dispatch is capability-by-domain, checked** (§5.4.1, Fig 5.6): `genter` → x16 =
  `sptm_dispatch_target_t` (domain|table_id|endpoint) → `genter_dispatch_entry` →
  `CORE_SPTM_FUNCTION`. Dispatcher = `CORE_DISPATCH_STRUCTURE + 0x180·domain +
  0x18·table_id`; SPTM then **verifies the caller domain suits the dispatcher's
  permission mask**. The domain is read from SPTM state / the `TPIDR` caller-domain
  field (set by execution context / state transitions in A.7), *not* taken blindly from
  the caller. So: no per-caller crypto identity, but a real coarse-capability gate.
- **NVMe table registered XNU-callable** — `IOMMU_bootstrap` (Listing A.1) hard-codes
  `if (iommu_id == 2 /*NVME*/) permissions = 0x12; else permissions = 2;` then
  `register_iommu(...)`. `0x12 = 0x2|0x10 = XNU_DOMAIN | XNU_HIB_DOMAIN` by the Table 5.2
  convention. It also panics if the IOMMU provides no XNU-facing dispatch table. This is
  the mechanism that makes the XNU-shim route (Q1) viable in principle.
- **Exact decode offsets** (A.1, analyzed binary): `NVME_DISPATCH_TABLE 0xfffffff027014710`,
  `SART_DISPATCH_TABLE …0149b0`, `register_iommu …0bf164`, `IOMMU_bootstrap …0be298`,
  `genter_dispatch_entry …0bf3f8`, `sptm_dispatch …0bf268`, `CORE_DISPATCH_STRUCTURE_POINTER
  …079500`. Use as r2 landmarks (rebased) for Q4.1 on our blob.

**Discrepancy to record (do not propagate the paper's summary uncritically):** the
paper's Table 5.3 lists NVMe `0x12` as "bits 2,3 → TXM_DOMAIN, SK_DOMAIN," and the prose
says NVMe "seems to be only valid for TXM and SK." That contradicts (a) the paper's own
Table 5.2 bit convention and (b) the `IOMMU_bootstrap` code, both of which make
`0x12` = XNU + XNU_HIB. Treat the **code as authoritative: NVMe is XNU-callable.** The
Table 5.3 row is an internal inconsistency in the paper.

**The paper does *not* enumerate the NVMe table's endpoints** — A.4 lists the
`SPTM_FUNCTIONID_*` set (0–33) for the *XNU_BOOTSTRAP* table (retype/map/etc.), a
different table. So wallace's service-6 op inventory (ops 0..8, op-0/1/4 confirmed) is
**net-new information beyond the paper**; the two are complementary. Disassembling
`NVME_DISPATCH_TABLE` (Q4.1) is what fills in the endpoint semantics the paper lacks.

**New reconciliation task for the disassembly (Q4):** the paper's descriptor carries a
domain field in x16 bits [55:48], but ticket 007's verbatim service-6 veneer showed only
`movz x16,#op` + `movk x16,#6,lsl#32` — **no domain `movk` at lsl #48** (i.e. domain 0 =
SPTM_DOMAIN as encoded). Since NVMe requires XNU_DOMAIN, either (a) ticket 007's snippet
omitted a third `movk`, or (b) the effective domain is supplied by SPTM from `TPIDR`
context rather than the immediate. Re-examine the veneers for the domain `movk`, and
check `guard_enter` for a domain write — this directly tests whether a post-handoff Linux
must set the domain itself or inherits it from context. Load-bearing for the shim route.

---

## Veneer re-examination — CORRECTION to ticket 007 (byte-level, this session)

CJ asked me to check the service-6 veneers for a domain `movk`. Doing so overturned
ticket 007's stated encoding. I decoded the x16 construction at **all 151** GENTER sites
in the staged T6041 kernelcache (`kernelcache.mac16j.raw`) directly from the instruction
bytes (MOVZ/MOVK are fixed encodings — decoded in Python, no disassembler trust needed).

**Byte-proven facts:**
- **No GENTER site builds a service/table field.** Not one of the 151 sites has a
  `movk x16, #N, lsl #32`. Ticket 007's verbatim op-0 veneer —
  `mov x16,#0 ; movk x16,#6,lsl#32 ; GENTER` — **does not exist in the binary.** The
  `movk x16,#6,lsl#32` is absent everywhere near code.
- **149 sites are endpoint-only veneers:** `…; BL guard_enter; MOVZ x16, #<op>; GENTER;
  BL guard_exit; …`. x16 = endpoint in the low bits, **table field = 0, domain field
  = 0**. All 143 resolvable ones call the **same** gate `guard_enter @ 0x4736830` — which
  is exactly the address ticket 007 cited, confirming 007 looked at these very stubs and
  then mis-transcribed the encoding.
- **2 sites carry a domain** (`movk x16, #d, lsl #48`) and take the endpoint from `w0`,
  loading x0..x7 from a buffer at x1: `@0x5072a40` domain **3 = SK_DOMAIN**, `@0x5072a68`
  domain **2 = TXM_DOMAIN**. These are `sk_enter` / `txm_enter` — precisely the two
  domain-bearing gates the paper names (§5.4.1). No NVMe/domain-anything-else gate exists.
- Op numbers observed run 0..49 in restarting sequences (0..8, 0..18, 0..12, …). Ticket
  007 grouped these restarting runs and labelled them "service 3/5/6/7/…", but the
  service number was **never in x16** — it was assigned, not read.

**Reinterpretation (well-supported inference, not byte-proven):** XNU invokes SPTM
almost entirely through **table 0 (`XNU_BOOTSTRAP`) endpoints** built with `MOVZ #endpoint`
immediates (the A.4 `SPTM_FUNCTIONID_*` page-table set — RETYPE, MAP_PAGE, …), plus the
`txm_enter`/`sk_enter` domain gates. The **NVMe/SART IOMMU dispatch tables (ids 6/5,
IOMMU ids 2/1) are SPTM-*internal* routing**, reached by passing an `iommu_id` *argument*
(NVMe = 2) to a table-0 endpoint — **not** by naming "table 6" in x16. Ticket 007
conflated SPTM's internal dispatch-table id (6) with the XNU-side x16 encoding. What its
"prior live test issued op 0 / op 4" actually issued were table-0 endpoints
(≈ LOCKDOWN / MAP_PAGE-class), which of course wedge without a resident SPTM.

**Impact:**
- **The go/no-go verdict is UNCHANGED and more robust.** Whatever the exact op, a GENTER
  with no resident SPTM behind the gate wedges — that is the whole blocker, and it does
  not depend on the "service 6" framing.
- **Supersede the ticket-007 "service-6 ABI" claim.** The `x16 = op | (service<<32)`
  encoding, the guarded-service map (services 3/5/6/7/9/10/11/13), and the verbatim
  service-6 veneer are **wrong** and should be retracted. The op-4 arg contract (ASQ/ACQ
  PA + depths) came from the debug patch, not from a byte-proven service-6 veneer — treat
  it as unverified until re-derived.
- **The shim route (Q1) gets *simpler*, not harder.** Since XNU uses table-0 endpoints
  with the domain supplied from `TPIDR` context (never a forged domain in x16), a
  post-handoff Linux inheriting XNU's EL1 context would issue the *same* table-0 SPTM
  calls with no special NVMe ABI to reverse. NVMe bring-up becomes "replay macOS's SPTM
  IOMMU/CoastGuard call sequence (table-0 endpoints + `iommu_id=2` args)," which the HV
  trace (Q3.2) can capture directly.
- **Q4 retargets:** the authoritative decode is now (a) find the table-0 endpoint that
  takes an `iommu_id` and (b) disassemble SPTM's `NVME_DISPATCH_TABLE`/`register_iommu`
  to read the per-iommu op semantics. The caller-side "service-6 veneer" decode is void.

Method note: a whole-binary MOVK census is unreliable here (data bytes false-match the
MOVK pattern — 222k bogus "lsl#48" hits), so this rests on the **targeted** decode of the
151 real GENTER code sites, which is sound.

---

## Net recommendation update (feeds tickets 008/010)

1. **Q2 closed:** record SPTM-on-M4 as **confirmed** (string/symbol evidence here),
   supersede the "inferred" hedge in ticket 007. Adopt symbol/string controls (not
   byte-grep, not "newer=SPTM") as the standing test.
2. **Near-term verdict unchanged:** internal NVMe stays blocked from raw boot;
   USB-attached root (tickets 009/031/032) remains the daily-driver storage path.
3. **Re-frame ticket 010** to the XNU-shim question (Q1) — better-formed than the old
   "iBoot-loads-SPTM-for-m1n1" ask, and it recruits asahi_neo's capability-model
   argument against route-B pessimism.
4. **DONE — SPTM blob disassembly (Q3.1/Q4.1):** see
   `done/2026-07-14-t6040-sptm-nvme-guarded-backend-decode.md`. Decompressed the
   M4-family SPTM (t8132) and read the guarded-side NVMe backend directly: **9 ops
   0..8** (`func_state[N]`), op-4=admin-queue **confirmed**, and **op-5..8 corrected**
   (5=IOQA, 6=IOSQ, 7=IOCQ, 8=ANS-SHA — ticket 007's guesses were wrong). Full
   validation/TCB/CID model recovered. Exact-target `sptm.t6041` (in the IPSW, not
   staged) still wanted to lock numeric offsets; per-op arg registers still need deeper
   disasm or the HV trace.
5. **Load-bearing static check for the shim route:** re-examine ticket 007's service-6
   veneers for a domain `movk` (x16 bits [55:48]) and `guard_enter` for a domain write.
   Answers whether a post-handoff Linux must set the XNU domain itself or inherits it
   from `TPIDR` context — the pivot on which the whole XNU-shim NVMe idea turns.

## Scope discipline

No admin command, Identify, namespace read, mount, or storage write occurred or is
justified. New evidence added by this note is one read-only string/symbol grep over the
already-staged M4 kernelcache, plus a read of the (public, CC-BY-SA) Steffin/Classen
paper CJ supplied. asahi_neo was read, not modified.
