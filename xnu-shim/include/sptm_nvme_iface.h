/*
 * sptm_nvme_iface.h — SPTM / NVMe guarded-call interface for the M4 XNU-shim route.
 *
 * Derived from the guarded-side decode (done/2026-07-14-t6040-sptm-nvme-guarded-backend-decode.md)
 * and the Steffin/Classen ABI (arXiv:2510.09272, appendices A.2–A.5). This header encodes
 * ONLY what was proven from the SPTM blob + kernelcache. Guarded-side argument consumption
 * is byte-verified in ticket 051; the outer IOMMU call marshalling remains TBD-053.
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
 * All indices and guarded-side contracts are confirmed from the handlers. The op index is
 * passed to SPTM on the IOMMU path (NOT as an x16 endpoint); that outer mechanism is TBD-053.
 */
enum nvme_op {
    NVME_OP_INIT               = 0,   /* no caller arguments */
    NVME_OP_SET_TCB            = 1,   /* qid, cid, TCB PA, page-list PA, count */
    NVME_OP_INVALIDATE_TCB     = 2,   /* qid, cid, direction/state flag */
    NVME_OP_CONFIGURE          = 3,   /* queue entries, protocol version */
    NVME_OP_ADMIN_QUEUE_REGS   = 4,   /* sptm_nvme_bar_admin_queue_regs   (CONFIRMED) */
    NVME_OP_IOQA_REG           = 5,   /* sptm_nvme_bar_ioqa_reg           (CONFIRMED) */
    NVME_OP_IOSQ_REG           = 6,   /* sptm_nvme_bar_iosq_reg           (CONFIRMED) */
    NVME_OP_IOCQ_REG           = 7,   /* sptm_nvme_bar_iocq_reg           (CONFIRMED) */
    NVME_OP_ANS_SHA_REG        = 8,   /* sptm_nvme_ans_sha_reg            (CONFIRMED) */
    NVME_OP__COUNT             = 9,
};

/*
 * Guarded-side register contracts, byte-proven on sptm.t8132.release:
 *
 * op 0: no arguments
 * op 1: x0=qid, x1=cid, x2=TCB PA, x3=page-list PA, x4=page count
 * op 2: x0=qid, x1=cid, x2=direction/state flag (low bit consumed)
 * op 3: x0=queue entries, x1=protocol version
 * op 4: x0=ASQ PA, x1=ASQ depth, x2=ACQ PA, x3=ACQ depth
 * op 5: x0=IOSQ entries, x1=IOCQ entries
 * op 6: x0=IOSQ register PA/value
 * op 7: x0=IOCQ register PA/value
 * op 8: x0=ANS SHA base PA, x1=buffer size, x2=packed-write config
 *
 * Addresses stay 64-bit; count/depth/config fields are consumed as w registers. The exact
 * outer-call register preservation/return convention is still TBD-053.
 */
struct nvme_op_args { uint64_t x[8]; };

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
