# T6040 next rig experiment review (2026-07-21)

Review of every tracked rig experiment after the USB-host artifacts were built
and the M4 showed a local `Running proxy` but failed to present KIS to the M1.

## Completed experiments

| Ticket | Result | Consequence |
|---|---|---|
| 001 DockChannel RX BIT(1) | Probe bytes never entered the AP FIFO; AIC delivery was not exercised | Do not retry the image; continue only with offline RX-path delta evidence |
| 002 PCIe op-115 read | The ADT-derived 32-bit read at `0x417040090` stalled | No write-only retry; PCIe waits for a statically proven missing precondition |
| 003 ANS CPU_CONTROL read | After correcting ADT address translation, the isolated read returned `0x10` and stopped safely; later bounded work reached the protected SPTM/CoastGuard queue boundary | Raw-boot internal NVMe is now a documented near-term no-go; do not spend rig time forcing GENTER/service 6 |
| 053 SPTM HV trace | Infeasible because m1n1 HV itself is SPTM-blocked on T6040; not run | Superseded by static decode and XNU-shim/escalation work |

## Approved experiments still open

| Ticket | Readiness | Decision |
|---|---|---|
| 004 trackpad motion | **Not runnable.** Board-paired `tpmtfw-j614s.bin` is absent; tickets 016/030 remain open; live ticket still says hashes TBD and needs cross-review | Do not boot |
| 005 `maxcpus=2` | **Not runnable.** Yuka's WIP `more-t6041` branch reached an M4 Pro shell with all cores and PMGR, but its inherited CPU/domain description is not board-correct for 14-core J614s. Ticket 034 still must audit topology/release/WFE constraints and produce hashed, self-reporting artifacts plus cross-review | Do not boot |
| 006 cpufreq DT | **Not runnable.** m1n1's minimal `+0x20020` APSC path is proven, but offline ticket 035 has not produced/schema-checked the Linux DT or pinned artifacts; T6040 throttle offsets remain unsafe | Do not boot |
| 057 USB port-map ADT | **Completed.** Moving DebugUSB to the known-good left-back port restored KIS; the RAM-read capture maps `usb-drd0/1/2` to `left-back/left-front/right` | Build a single-port DTB with `usb-drd0` disabled |

## Recommendation

Ticket **057 is complete** and removes the physical-map blocker. The next valid
rig action is the no-`root=` USB enumeration smoke, but only after building,
hashing, and independently reviewing a DTB that enables the one controller
carrying the external drive. `usb-drd0`/left-back must remain disabled because
it carries DebugUSB. Do not jump to tickets 004–006 merely because they are
approved; their own descriptions and offline dependencies show they are not
artifact-ready.

Post-review correction: the 11–21 July `#asahi-dev` audit established that the
DockChannel UART is on AIC input 816, not ADT input 360. Rebuild the one-port
poll-mode USB DTBs with the corrected interrupt before the smoke test. Poll mode
does not request the line, so this is a correctness/provenance rebuild rather
than a new runtime variable. Full record:
`done/2026-07-21-asahi-dev-log-review.md`.
