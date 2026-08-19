# Ticket 3009: exact review of the a1 physfix PD DTB — PASS

Date: 2026-08-19. Reviewer: opus (non-builder, non-sol). Scope: offline binary
review only. No lease, rig command, MMIO, SPMI transaction, build, enrollment,
or storage mutation occurred.

## Verdict

**PASS.** The ticket-3008 address-corrected DTB is byte-reproducible and is
exactly the already-reviewed ticket-305 fixture with only the a1 SPMI controller
physical address corrected (raw `0x309198000` → CPU-physical `0x509198000`, per
the ticket-3000 audit). It is within `docs/SPMI_SAFETY.md` Entries 1 and 2 and
introduces no new endpoint, SID, write, or kernel change. It supersedes the
raw-address DTB `dd57776e` (v3) that hung in every 305 run 1–5.

## Independent verification (nothing trusted from the 3008 evidence)

### Byte identity and reused fixture hashes

```text
eaf8cceb8c22d19f71ea0175397a96bd41ff6ebf56ab0719da7da0272f068acf  ...pd-physfix.buildA.dtb
eaf8cceb8c22d19f71ea0175397a96bd41ff6ebf56ab0719da7da0272f068acf  ...pd-physfix.buildB.dtb
# cmp: byte-identical
5a136710684dbda738cfb51ea0149b9cf64d2ca58c15f1c66a1d6b0310ad9af8  Image-usb2pd.buildA
51aa40f0df95a6938d7067f107f7b4aa0d614bea6c2c269a4e1b10a9e745b2d1  config-usb2pd.buildA
4cc6513365803f161100d93b9dd9ae7c1a75d0a82e2d196ba7e776f8bb93f672  initramfs-sdroot-hardened.cpio.gz
```

All three reused components match the hashes pinned by ticket 3008 and by the
approved ticket-305 fixture. The kernel is unchanged, so the tps6598x driver and
transaction envelope are the ones already reviewed on 2026-08-18.

### Compiled-DTB contract (decompiled buildA with dtc)

| Check | Result |
|---|---|
| a1 controller node | exactly one `/soc/spmi@509198000` |
| a1 reg | `<0x05 0x9198000 0x00 0x4000>` = CPU-physical `0x509198000/0x4000` |
| stale raw-address node | **zero** `spmi@309198000` |
| a1 genpd | `power-domains` phandle `0x78` → `power-controller@70`, `label = "nub_spmi_a1"` |
| a1 status | `okay` |
| PD endpoints (whole DTB) | exactly one `usbc,sn201202x,spmi` |
| endpoint | `usb-pd@c`, reg `<0x0c 0x00>` → SID `0x0c`, USID `0x00` |
| connector | `usb-c-connector`, `power-role = "source"`, `data-role = "host"` |
| internal NVMe | `/soc/nvme@44dcc0000` (`apple,t6040-nvme-ans2`) `status = "disabled"` |
| primary SPMI | unchanged `/soc/spmi@509014000`, `pmic@e` (`apple,abbey-pmic`,`apple,spmi-nvmem`) SID `0x0e` |

### Reconciliation with SPMI_SAFETY.md

- **Entry 1 (hpm2):** the a1 endpoint is the sole right-port hpm2, gen3, SID
  `0x0c`. The DT reg `0x509198000` is the ADT-derived CPU-physical translation of
  the raw `/arm-io` reg0 `0x309198000` recorded in Entry 1 — not a blind or
  cross-SoC address. No a0/a2, no other HPM, no SID scan.
- **Entry 2 (abbey nvmem):** `pmic@e` SID `0x0e` exposes only the bounded
  nvmem-layout cells `rtc_offset`, `boot_stage`, `boot_error_count`,
  `panic_count`, `shutdown_flag`. `pm-setting@2001` is present in the layout but
  carries **no phandle**, so no consumer references it and it is never read —
  which is exactly Entry 2's "`pm_setting` has no consumer and must stay unread."
- No `aop-spmi0`, `nub-spmi1/2/3/4`, or `btm` node is described. Only the two
  allowlisted controllers appear.

### Reconciliation with ticket-305 stop conditions

The only effective change from the approved 305 fixture is the a1 reg address;
kernel, initramfs, driver patch, endpoint, connector policy, and NVMe-disabled
override are identical. `maxcpus=1`, the consoles, the seated passive S128 stick,
and the no-mount / no-block-read prohibition all carry forward unchanged.

## Carry-forward safeguard for the attended 305 resume

Unchanged from the 305 review: because `SPMI_APPLE=y` makes the abbey nvmem
reachable this boot, the attended operator must confirm the probe-time abbey
**reads** look sane (`boot_stage` small int, `panic_count` small, `rtc_offset`
plausible) before any Linux-initiated reboot exercises the abbey **write** path —
the cell offsets were project-measured on this PMIC generation, not inherited.

## Gate

PASS unblocks the attended ticket-305 resume **on the `eaf8cceb…` DTB only**.
The pinned raw-address DTB `dd57776e` (v3) must not be booted. A boot remains rig
work under the normal lease, attended, and is not authorized by this offline
review.
