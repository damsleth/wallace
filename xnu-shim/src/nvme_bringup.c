/*
 * nvme_bringup.c — drive the SPTM NVMe backend (ops 0..8) from post-handoff Linux.
 *
 * This is the P4 deliverable and the payoff of the whole route: once Linux runs at EL1 with
 * a resident SPTM (via the XNU-shim, Phases 2–3) it walks the ops below in allowed_functions
 * order to take ownership of the internal NVMe queues, after which normal nvme-apple I/O
 * (read AND write) works exactly as on M1/M2 Asahi.
 *
 * STATUS: skeleton only. Every sptm_nvme_call() is a no-op stub (see sptm_nvme_iface.h)
 * until ticket 053 proves (a) the SPTM call path for NVMe ops and (b) that Linux-at-EL1 is
 * tagged XNU_DOMAIN so the 0x12 permission is satisfied. Arg blocks are TBD-051/053. Do not
 * run this against real hardware — issuing a mis-formed genter with no valid path wedged the
 * machine before (ticket 008); nothing here should reach the rig until 053 closes.
 */
#include "sptm_nvme_iface.h"

/* Call-ordering the backend enforces via validate_nvme_call_allowed(allowed_functions).
 * Exact prerequisite bitmap per op is TBD-053 (read allowed_functions transitions live). */
static const enum nvme_op NVME_BRINGUP_ORDER[] = {
    NVME_OP_PROTOCOL_NEGOTIATE,   /* 0: negotiate SPTM NVMe queueing protocol version */
    NVME_OP_QUEUE_ENTRIES_TCB,    /* 1: query/limit queue entries; begin TCB/CID setup */
    NVME_OP_TCB_CID_2,            /* 2: TCB/CID */
    NVME_OP_TCB_CID_3,            /* 3: TCB/CID */
    NVME_OP_ADMIN_QUEUE_REGS,     /* 4: register admin SQ/CQ (ASQ/ACQ PA + depths) */
    NVME_OP_IOQA_REG,             /* 5: program I/O-queue-attributes register */
    NVME_OP_IOSQ_REG,             /* 6: register/activate I/O submission queue */
    NVME_OP_IOCQ_REG,             /* 7: register/activate I/O completion queue */
    NVME_OP_ANS_SHA_REG,          /* 8: program ANS SHA register (if nvme-ans-sha-present) */
};

/*
 * sptm_nvme_bringup — take SPTM-mediated ownership of the internal NVMe queues.
 * Returns 0 on success, negative on the first failing op.
 *
 * Preconditions (all TBD until upstream phases land):
 *   - resident, initialised SPTM (Phase 2 shim boot)
 *   - this EL1 context is tagged XNU_DOMAIN by SPTM  (TBD-053)
 *   - admin/IO queue memory allocated + SPTM-retyped   (Phase 3 loader; sptm_nvme_map_pages)
 */
int sptm_nvme_bringup(void)
{
    for (unsigned i = 0; i < sizeof(NVME_BRINGUP_ORDER)/sizeof(NVME_BRINGUP_ORDER[0]); i++) {
        enum nvme_op op = NVME_BRINGUP_ORDER[i];
        struct nvme_op_args args = {0};   /* TBD-051/053: real per-op arg marshalling */
        int rc = sptm_nvme_call(op, &args);
        if (rc != 0)
            return rc;                     /* backend raised a VIOLATION_NVME_* — diagnose */
    }
    return 0;
}

/*
 * Write path note (P4): there is NO write-specific SPTM op. Once sptm_nvme_bringup() owns
 * the queues, write commands use the same authorised SQ + the per-CID TCB DMA authorisation
 * (sptm_nvme_map_pages) as reads. The remaining write work is OPERATIONAL, not SPTM:
 *   - carve a dedicated APFS volume; never write macOS's containers
 *   - respect ANS/SEP-managed encryption / effaceable storage (as M1/M2 Asahi does)
 * That belongs in the Linux nvme-apple + installer layer, not here.
 */
