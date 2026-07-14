/*
 * linux_loader.c — load the Linux kernel/initramfs into SPTM-mapped memory (Phase 3). SKELETON.
 *
 * Runs inside the shim (post-intercept), while SPTM is resident. Claims physical frames for
 * Linux and builds its address space through SPTM calls (the standard XNU_BOOTSTRAP page-table
 * endpoints, paper A.4), then transfers control. This is orthogonal to NVMe — it's the generic
 * "boot Linux under a live SPTM" step the asahi_neo shim is designed around.
 *
 * BLOCKED ON: Phase 2 (shim actually running) and rig. SPTM frame-retype/map endpoint numbers
 * and arg contracts are the paper's A.4 set but must be confirmed on M4 (TBD-053).
 */
#include "sptm_nvme_iface.h"

/* SPTM page-table ops live in the XNU_BOOTSTRAP table (paper A.4): RETYPE=1, MAP_PAGE=2,
 * MAP_TABLE=3, REGISTER_CPU=14, … These are the SAME table-0 endpoint-only genters we saw
 * in the kernelcache (done/...xnushim-asahi-neo-crossref.md), so the shim reuses XNU's path. */

int linux_loader_load(void *linux_image, void *initramfs, void *fdt)
{
    (void)linux_image; (void)initramfs; (void)fdt;
    /* TODO(P3): for each Linux phys frame: sptm_retype(pa, FREE, XNU_DEFAULT)          */
    /* TODO(P3): for each page-table page:  sptm_retype(pa, FREE, XNU_PAGE_TABLE)       */
    /* TODO(P3): sptm_map_page(ttep, va, pte) to build Linux's identity/kernel map      */
    /* TODO(P3): stage `linux_image`/`initramfs` from Preboot; place `fdt`              */
    /* NOTE: no SPTM watchdog (paper §5.4 / SPTM_FINDINGS) — Linux won't be killed for  */
    /* not calling back. Frames typed XNU_DEFAULT are R/W/X-capable from EL1 (feasible, */
    /* not hardened) — acceptable for the boot goal.                                    */
    return -1; /* not implemented — see PLAN.md */
}
