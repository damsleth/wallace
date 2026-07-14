/*
 * fdt_builder.c — construct the minimal M4 (T6041) FDT for Linux (Phase 3). SKELETON.
 *
 * The shim hands Linux a flattened device tree. For internal-NVMe boot this must include the
 * nvme/ans nodes so Linux's nvme-apple driver probes — but Linux only owns the queues after
 * sptm_nvme_bringup() (P4). Everything here is the generic minimal DT plus the nvme node.
 *
 * BLOCKED ON: Phase 3. Reuse wallace's existing T6040/T6041 DT work (dts/, done kboot-fdt);
 * this is a thin shim-side emitter, not new DT authorship.
 */

void *fdt_build(void)
{
    /* TODO(P3): serial (s5l/dockchannel earlycon), AIC, arch timer, memory (RAM base). */
    /* TODO(P3): ans/nvme node (compatible = apple,nvme-ans2 t6041) + its DART/SART.     */
    /* TODO(P3): reuse dts/ + done/2026-07-10-t6040-kboot-fdt-plan.md; do NOT re-author. */
    return 0; /* not implemented — see PLAN.md */
}
