# T6040 approved rig-ticket overnight audit (2026-07-24)

Scope: reconcile every approved, not-done rig ticket against its actual
dependencies while the maintainer is away. The M4 began healthy at `Running
proxy`. No ticket may consume that state unless it is both approved and
`runnable=true` after exact-artifact independent review.

## Result

There was no approved-and-ready unattended run. The correct overnight action
was to advance offline gates, correct stale state, and leave the healthy proxy
untouched. The table records the blocker for every approved rig ticket:

| Ticket | Current blocker / next action |
|---|---|
| 004 trackpad motion | Exact candidate failed independent functional review and was retired unrun. Offline replacement 125 now byte-reproduces and independently passes; proposed 126 still waits for fresh approval, a narrow volatile-runtime-firmware policy exception, and attended finger motion. |
| 006 cpufreq | Waits for replacement maxcpus=2 ticket 123 and all-core ticket 121; both P-cluster policies must exist first. |
| 087 ALS calibration | Corrected private/fail-closed procedure independently reviewed PASS; still requires booting this M4 into its main macOS and collecting machine-private data, so do not abandon proxy unattended or substitute the M1. |
| 101 enrolled B0 cold boot | Ticket 119 review is complete. Ticket 082 still needs the M4 m1n1 volume UUID, current enrolled-object backup/hash, exact selected manifest, and maintainer enrollment/boot-picker action split. The agent never runs `kmutil`/`bputil`. |
| 103 post-S0 status | Blocked by ticket 096's final R3 no-go and ticket 102's deliberate no-artifact stop. |
| 106 HPM host transition | No safe forward/inverse artifact: 096 lacks VBUS, event/cache/mask/detect, pre-SSPS-state, and teardown-order proof. |
| 108 right USB enumeration | Waits for 106 and offline composition 107; no host-link artifact exists. |
| 109 read-only USB block | Waits for actual child enumeration 108. |
| 111 destructive stick flash | Waits for read-only identity 109 and preflight 110, then requires a separate erase confirmation naming the exact M1 removable whole disk. Plan approval is not that confirmation. |
| 112 tethered external-root read/write | Waits for enumeration 108 and verified flash 111. |
| 113 untethered external-root boot | Waits for B0 cold boot 101 and tethered persistence 112. |
| 121 all-core SMP | Waits for revised two-core proof 123 and offline all-core artifact 120. |

Ticket 123 was created after the maintainer's approve-all action and therefore
remains proposed. Ticket 122 is complete: the exact storage-disabled
early-DockChannel artifact passed independent review. It must not be run until
the maintainer explicitly approves 123.

Ticket 004's exact candidate was independently rejected before hardware use.
Its corrected replacement live ticket 126 was also created after the
approve-all and remains proposed; offline 125 and the explicit volatile
runtime-firmware policy exception were separate gates. Offline 125 is now
complete; the policy exception and approval remain open.

## Offline progress made instead

- Ticket 096 received its final PAC-aware static review and remains an honest
  R3 no-go.
- Ticket 119 completed the dual-mode B0 object cross-review with a conditional
  PASS and explicit version/Rust provenance caveat.
- Ticket 122 corrected the physical boot-CPU model, built a direct
  early-DockChannel diagnostic around only the already-proven TX registers,
  fixed its reporter/TTY ownership plan, and passed exact-artifact review.
- Ticket 087's first review found stale-capture and private-file-mode flaws.
  The corrected procedure and extractor now pass independent review, but the
  actual capture remains maintainer-attended.
- Ticket 125 corrected the two functional defects in retired ticket 004,
  normalized C/assembly build paths, reproduced the exact bytes twice, and
  passed independent review. Live 126 remains unapproved and attended.
- All stale `NEEDS_RECOVERY` claims in live ticket descriptions were replaced
  with the actual healthy-proxy state and the real dependency/attendance
  blockers.
