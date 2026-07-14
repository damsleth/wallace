/*
 * shim_entry.c — XNU-shim intercept point (Phase 2). SKELETON.
 *
 * Linked into a permissive-signed XNU-style kernelcache as a kext. We let iBoot + XNU bring
 * up SPTM legitimately (gxf_setup_early → gxf_setup_late → init_xnu_ro_data, which registers
 * the dispatch tables incl. NVMe/IOMMU), then intercept at the last safe moment and pivot to
 * Linux. Intercept target: IOPlatformExpert::start() (asahi_neo Option A) — post-SPTM-init,
 * early enough to control memory, late enough that all dispatch tables are registered.
 *
 * BLOCKED ON:
 *   - Phase 2 signing/toolchain: no permissive-kernelcache build path yet (docs/signing-path.md).
 *   - Phase 1 (ticket 053): confirm domain provenance before assuming we can call SPTM as XNU.
 * Nothing below is implemented; it documents the intended control flow only.
 */
#include "sptm_nvme_iface.h"

extern int  linux_loader_load(void *linux_image, void *initramfs, void *fdt); /* linux_loader.c */
extern void *fdt_build(void);                                                 /* fdt_builder.c */

/* Hook installed in place of / after IOPlatformExpert::start(). */
int shim_intercept(void)
{
    /* TODO(P2): confirm we are post-init_xnu_ro_data (SPTM dispatch tables registered). */
    /* TODO(P3): locate the linux Image + initramfs staged in Preboot at a known offset. */
    /* TODO(P3): fdt = fdt_build();  build minimal M4 FDT (serial, AIC, timer, nvme, memory). */
    /* TODO(P3): linux_loader_load(image, initramfs, fdt) — retype+map Linux via SPTM. */
    /* TODO(P3): transfer to Linux __primary_switch: x0=FDT PA, MMU per SPTM, other cores WFE. */
    /* NVMe (P4) happens *inside* Linux via sptm_nvme_bringup() — not here. */
    return -1; /* not implemented — see PLAN.md phases */
}
