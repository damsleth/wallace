# T6040/M4 SPTM NVMe guarded-backend decode — the real op map (2026-07-14)

Experiment "#3" from the asahi_neo cross-review
(`done/2026-07-14-t6040-sptm-xnushim-asahi-neo-crossref.md`): disassemble the SPTM
firmware blob to read the **guarded-side** NVMe implementation directly, replacing the
now-retracted caller-side "service-6 ABI" (ticket 007). Static, offline; no rig, no MMIO,
no storage.

**Headline:** the SPTM NVMe backend is a full validating queue-ownership monitor
(`nvme.c`) with **9 functions indexed 0..8** (`nvme_instance->func_state[0..8]`), each
gated by an `allowed_functions` call-ordering check. The `func_state[N]` index **is** the
op number — which yields the authoritative op map and corrects ticket 007's op-5..8
guesses. This is the real thing ticket 007's caller-side veneer decode was reaching for.

## Provenance & method

- **Blob:** `sptm.t8132.release.im4p` (M4-base, from `~/Code/asahi_neo/research/firmware`),
  decompressed with `pyimg4` (IM4P `sptm`/LZFSE-`bvx2`) → 1.13 MB arm64e Mach-O
  (`MH_EXECUTE`), load VA base **`0xfffffff027004000`**, so **vaddr = file_offset + base**
  (constant slide; verified for `__cstring` and `__TEXT_EXEC,__text`).
- **Exact-target caveat:** our kernelcache is **T6041 (M4 Max)**; the byte-exact SPTM is
  `Firmware/sptm.t6041.release.im4p` (confirmed present in the IPSW BuildManifest) but it
  ships as a top-level IPSW payload and is **not** in the staged rootfs dmg. **t8132 is
  the M4-base sibling** — same SPTM codebase; the NVMe/IOMMU logic is SoC-independent
  software (only register offsets / DART variants differ). Re-run on the t6041 blob before
  trusting any *numeric offset*; the *structure and op map* below are the shared design.
- **Tooling note:** `r2`/`rabin2` mis-parsed this Mach-O (chained fixups → 0 sections, bad
  VA map). **Apple `objdump -d --start/--stop-address` maps VAs correctly** and was used
  for disassembly; string/xref work done in Python (MOVZ/MOVK/ADRP/ADD are fixed encodings).

## The authoritative NVMe op map (from `func_state[N]` + handler disassembly)

The `func_state[N]` `__func__` strings pin ops 4..8 by their BAR-register handlers; ops
0..3 are the non-BAR query/TCB functions (no BAR `__func__` string), matched to the
caller-side ANS2 symbols and the `validate_*` set.

| op | SPTM function (guarded side) | Purpose | ANS2 caller symbol | Confidence |
|---:|---|---|---|---|
| 0 | (init / protocol negotiate) | `validate_nvme_protocol_version` | `GetNVMeSPTMProtocolVersion` | inferred (strong) |
| 1 | (queue-entries / TCB setup) | `validate_nvme_queue_entries`, `validate_cid` | `GetNVMeSPTMQueueEntries` / `NVMeCoastGuardSetTCB` | inferred |
| 2 | (TCB / CID op) | `validate_cid`, `invalidate_tcb_entry` | `NVMeCoastGuardSetTCB(Entry)` | inferred |
| 3 | (TCB / CID op) | CID state machine | — | slot present; inferred |
| **4** | **`sptm_nvme_bar_admin_queue_regs`** | **register admin SQ/CQ** | `SetupAdminQueue` | **confirmed** (`func_state[4]`, handler @ `0x…ba450`) |
| **5** | **`sptm_nvme_bar_ioqa_reg`** | **I/O-queue-attributes register** | `SetupIOQARegister` | **confirmed** (`func_state[5]`) |
| **6** | **`sptm_nvme_bar_iosq_reg`** | **I/O submission-queue register** | `EnableSubmissionQueue` | **confirmed** (`func_state[6]`) |
| **7** | **`sptm_nvme_bar_iocq_reg`** | **I/O completion-queue register** | `EnableCompletionQueue` | **confirmed** (`func_state[7]`) |
| **8** | **`sptm_nvme_ans_sha_reg`** | **ANS SHA register** | (ANS secure-hash-area) | **confirmed** (`func_state[8]`) |

**Correction to ticket 007** (which guessed by elimination): op count 0..8 was right; op-4
= admin queue was right; **op-5..8 were wrong** — ticket 007 had 5=I/O-SQ, 6=I/O-CQ,
7=auto-queue-manage, 8=teardown. Truth: **5=IOQA, 6=IOSQ, 7=IOCQ, 8=ANS-SHA**, and there
is no distinct "teardown"/"auto-queue-manage" op — teardown is `invalidate_tcb_entry` /
`sptm_nvme_unmap_pages`. Note this op index is an **IOMMU/dispatch argument**, not the
`x16` service field ticket 007 described (which does not exist — see the cross-review doc).

## Security / validation model (guarded side)

Each op handler begins with an inlined **`validate_nvme_call_allowed`** that checks
`nvme_instance->allowed_functions` (a bitmap) — a **call-ordering capability gate**: an op
may only run when prior ops have put the instance in the right state
(`VIOLATION_NVME_ILLEGAL_FUNC_CALL_STATE`). Confirmed by disassembly: the op-4 handler
loads `allowed_functions`, checks func index 4 (nvme.c:560), and panics via the assert
path on mismatch before touching the admin-queue registers.

Validation surface (from `VIOLATION_NVME_*` + `validate_*` symbols):

- **Queues:** `validate_nvme_queue_addr` / `_len` / `_entries` (INVALID_QID, ILLEGAL_QUEUE_ADDRESS,
  ILLEGAL_QUEUE_LENGTH, ILLEGAL_NVMe_QUEUE_ENTRIES_MISMATCH).
- **Protocol:** `validate_nvme_protocol_version` (ILLEGAL_NVMe_QUEUEING_PROTOCOL_VERSION).
- **Per-command TCB / CID state machine:** `cid_mode[c_id]` with states `CID_EMPTY`,
  `CID_BUSY`, `CID_FILLED_q`, `CID_FILLED_RETRY_q`, encoded `((q_id<<4)|state)`;
  `validate_cid`, `invalidate_tcb_entry` (INVALID_CID, ILLEGAL_CID_STATE_TRANSITION,
  "TCB entry %d is not invalidated in DRAM for qid %d cid %d"). This **is** the "TCB
  authorization" ticket 007 named — a per-(queue,command) translation-control-block the
  controller validates for DMA.
- **DMA pages:** `sptm_nvme_map_pages` / `_unmap_pages`, `validate_nvme_page`
  (INVALID_PAGE_COUNT, INVALID_NVME_PAGE) — this is the SART/CoastGuard-backed DMA
  authorization.
- **ANS SHA:** `validate_nvme_sha_base_addr` / `_buffer_size` / `_packed_write_config`
  (ILLEGAL_ANS_SHA_ADDRESS / _BUFFER_SIZE / _PACKED_WRITES_CONFIG).

`nvme_bootstrap` reads its policy from the ADT: `nvme-iboot-sptm-security`,
`nvme-secure-bar`, `nvme-secure-reg-layout`, `nvme-linear-sq`, `nvme-prp-flush-wa`,
`nvme-queue-entries`, `nvme-tl-wa`, `nvme-vdma-wa`, `nvme-num-sl`, `nvme-ans-sha-present`.

The **SART** IOMMU backend is present in the same blob (`VIOLATION_SART_*`: INVALID_PT,
INVALID_PADDR, INVALID_N_OPS, INVALID_SIZE, INVALID_PERM, ILLEGAL_MAP/UNMAP, CPU_RACE,
POWER …) — SART is the DMA-mapping IOMMU (dispatch table 5 / IOMMU id 1) the NVMe path
rides, matching the `IOCoastGuardSARTMapper` strings in the kernelcache.

## What this changes / what remains

- **Confirms the blocker is real and deep.** NVMe queue ownership is a genuine validating
  monitor (queue addr/len/entries, per-command TCB, DMA-page authorization, ANS SHA), not
  a thin shim — reproducing it (ticket-008 route B) means re-implementing all of the above
  with SART. That reinforces route B = upstream-scale.
- **The op map is now authoritative** for the shim route (Q1): a post-handoff Linux would
  drive exactly ops 0..8 in `allowed_functions` order (protocol → queue-entries → TCB →
  admin-queue → IOQA → IOSQ → IOCQ → ANS-SHA) against the resident SPTM. No secret ABI.
- **Still open (needs more disasm or the HV trace):** the exact per-op **argument
  registers** (e.g. op-4's ASQ/ACQ PA + depths — plausible but not yet byte-confirmed here;
  ticket 007's contract came from the debug patch, treat as unverified), and re-running on
  the byte-exact `sptm.t6041` blob to lock numeric offsets. The HV genter trace (cross-review
  Q3.2) remains the way to capture the live arg values per op.

## Reproduce

```sh
cd <scratch>
pyimg4 im4p extract -i ~/Code/asahi_neo/research/firmware/sptm.t8132.release.im4p -o sptm.t8132.bin
# base VA 0xfffffff027004000 ; vaddr = file_offset + base
strings -a -t d sptm.t8132.bin | grep -iE 'nvme|VIOLATION_|func_state|CID_|validate_|sart'
objdump -d --start-address=0xfffffff0270ba450 --stop-address=0xfffffff0270ba640 sptm.t8132.bin  # op-4 handler
objdump -d --start-address=0xfffffff0270bbf60 --stop-address=0xfffffff0270bc090 sptm.t8132.bin  # nvme_bootstrap
# for the exact target: extract Firmware/sptm.t6041.release.im4p from the M4 Max IPSW
```

## Scope discipline

No admin command, Identify, namespace read, mount, or storage write occurred or is
justified. Work was static disassembly of a decompressed, publicly-analyzed SPTM firmware
blob (asahi_neo's staged t8132) in the session scratchpad; only this write-up is committed.
No Apple binary is stored in the repo.
