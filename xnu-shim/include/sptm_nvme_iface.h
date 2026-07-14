/*
 * sptm_nvme_iface.h — SPTM / NVMe guarded-call interface for the M4 XNU-shim route.
 *
 * Derived from the guarded-side decode (done/2026-07-14-t6040-sptm-nvme-guarded-backend-decode.md)
 * and the Steffin/Classen ABI (arXiv:2510.09272, appendices A.2–A.5). This header encodes
 * ONLY what was proven from the SPTM blob + kernelcache. Anything not byte-verified is marked
 * TBD-051 (static per-op arg decode) or TBD-053 (live HV trace). Do not invent arg layouts.
 *
 * IMPORTANT: ticket 007's "x16 = op | (service<<32)" veneer ABI was RETRACTED — no such
 * encoding exists in the kernelcache. NVMe ops are SPTM-internal (dispatch table 6 / IOMMU
 * id 2), reached from XNU via an IOMMU path, NOT a distinct table-6 genter. The exact XNU
 * entry (which XNU_BOOTSTRAP endpoint + how iommu_id/op/args are passed) is UNPROVEN — 053.
 */
#ifndef SPTM_NVME_IFACE_H
#define SPTM_NVME_IFACE_H
#include <stdint.h>

/* --- GXF guarded-call primitives (proven: enc from m1n1 gxf_asm.S, stable A16..M4) --- */
#define GENTER_INSN  0x00201420u   /* .inst — no mnemonic */
#define GEXIT_INSN   0x00201400u

/* --- SPTM dispatch descriptor in x16 (paper §5.3.4 / Fig 5.3) ---
 * x16 = (domain << 48) | (table_id << 32) | endpoint_id
 * NOTE: the caller-supplied domain field is CROSS-CHECKED by SPTM against the caller domain
 * tracked in TPIDR/state (paper §5.4.1). You cannot forge a domain — it is derived from
 * execution context. This is the crux the shim route bets on (see TBD-053 below).
 */
#define SPTM_DESC(domain, table, endpoint) \
    (((uint64_t)(domain) << 48) | ((uint64_t)(table) << 32) | (uint32_t)(endpoint))

/* SPTM domain IDs (paper A.2, confirmed sptm_common.h) */
enum sptm_domain {
    SPTM_DOMAIN = 0, XNU_DOMAIN = 1, TXM_DOMAIN = 2, SK_DOMAIN = 3, XNU_HIB_DOMAIN = 4,
};
/* domain permission-mask bit values (paper Table 5.2): bit value 2^n ⇒ domain n */
#define PERM_XNU      0x02u
#define PERM_TXM      0x04u
#define PERM_SK       0x08u
#define PERM_XNU_HIB  0x10u

/* SPTM dispatch table IDs (paper A.3) */
enum sptm_table { SPTM_TBL_XNU_BOOTSTRAP=0, SPTM_TBL_SART=5, SPTM_TBL_NVME=6, /* … */ };
/* IOMMU IDs (paper A.5) */
enum sptm_iommu { IOMMU_SART=1, IOMMU_NVME=2 };
/* NVMe IOMMU dispatch table is registered XNU-callable: permissions = PERM_XNU|PERM_XNU_HIB
 * (= 0x12), hard-coded in IOMMU_bootstrap (paper Listing A.1). This is why a Linux inheriting
 * the XNU domain context should be authorized to drive it. */
#define NVME_IOMMU_PERMISSIONS  (PERM_XNU | PERM_XNU_HIB)   /* 0x12 */

/* --- NVMe op set: func_state[0..8], gated by validate_nvme_call_allowed / allowed_functions ---
 * Indices 4..8 CONFIRMED from func_state[N] __func__ strings; 0..3 inferred from the caller
 * ANS2 symbols + validate_* set (confidence noted in the decode doc). The op index is passed
 * to SPTM as an argument on the IOMMU path (NOT as x16 endpoint) — exact mechanism = TBD-053.
 */
enum nvme_op {
    NVME_OP_PROTOCOL_NEGOTIATE = 0,   /* validate_nvme_protocol_version   (inferred) */
    NVME_OP_QUEUE_ENTRIES_TCB  = 1,   /* validate_nvme_queue_entries/cid  (inferred) */
    NVME_OP_TCB_CID_2          = 2,   /* CID/TCB                          (inferred) */
    NVME_OP_TCB_CID_3          = 3,   /* CID/TCB                          (inferred) */
    NVME_OP_ADMIN_QUEUE_REGS   = 4,   /* sptm_nvme_bar_admin_queue_regs   (CONFIRMED) */
    NVME_OP_IOQA_REG           = 5,   /* sptm_nvme_bar_ioqa_reg           (CONFIRMED) */
    NVME_OP_IOSQ_REG           = 6,   /* sptm_nvme_bar_iosq_reg           (CONFIRMED) */
    NVME_OP_IOCQ_REG           = 7,   /* sptm_nvme_bar_iocq_reg           (CONFIRMED) */
    NVME_OP_ANS_SHA_REG        = 8,   /* sptm_nvme_ans_sha_reg            (CONFIRMED) */
    NVME_OP__COUNT             = 9,
};

/*
 * Per-op argument contract — UNVERIFIED. Ticket 007's op-4 contract (x0=ASQ PA, x1=SQ
 * depth-1, x2=ACQ PA, x3=CQ depth-1) came from the debug patch, not a proven veneer; treat
 * as a hypothesis. Fill this from ticket 051 (static handler disasm) + 053 (live arg trace).
 */
struct nvme_op_args { uint64_t x[8]; };   /* TBD-051/053: real width/meaning per op */

/*
 * sptm_nvme_call — issue one NVMe SPTM op from Linux (post-handoff).
 * STUB: the genter path (which endpoint, how iommu_id=IOMMU_NVME + op are marshalled) is
 * not yet known. Do NOT implement the genter until TBD-053 resolves the call path AND
 * domain provenance. Returning an error keeps callers honest until then.
 */
static inline int sptm_nvme_call(enum nvme_op op, const struct nvme_op_args *args)
{
    (void)op; (void)args;
    return -1; /* TBD-053: unimplemented until HV trace proves the path + domain */
}

/* Violation codes the backend can raise (for diagnostics; from the blob strings). */
/* VIOLATION_NVME_{INVALID_QID,INVALID_CID,INVALID_PAGE_COUNT,ILLEGAL_QUEUE_ADDRESS,
 * ILLEGAL_QUEUE_LENGTH,ILLEGAL_NVMe_QUEUEING_PROTOCOL_VERSION,ILLEGAL_FUNC_CALL_STATE, …} */

#endif /* SPTM_NVME_IFACE_H */
