# T6040 s2idle / cpuidle feasibility analysis (2026-07-24)

Ticket 027 (offline, P2, power management). Current asahi-wip, m1n1's M4
features, the J614s DT, and this rig's WFI evidence were compared. The result is
not a live preflight: current T6040 suspend is unsafe and would not provide
useful residency even with the SMC DT present.

## Corrected model: SMC wakes s2idle; it does not enter it

Linux s2idle is the generic suspend-to-idle loop: devices suspend and every
online CPU repeatedly enters its deepest `enter_s2idle` cpuidle state until a
hard wake event arrives. The Apple SMC path contributes wake sources:

- `macsmc-input` arms `wakeup_mode` during PM prepare;
- lid-open and power-button notifications call `pm_wakeup_dev_event()`;
- commit `56269d58523d` fixed those notifications to be hard s2idle wake
  events.

There is no Apple platform suspend driver or SMC “enter sleep” key in current
asahi-wip. The `macsmc-reboot` comment mentioning `susp` describes a reboot
reason, not the s2idle entry mechanism. Therefore adding the J614s SMC node
can provide battery/lid/button plumbing, but it cannot make CPU suspend safe.
The SMC read-only DT prepared by ticket 061 deliberately omits reboot/RTC
NVRAM subnodes and is sufficient for a future wake-source test once the CPU
side exists.

## CPU-side blocker

Current asahi-wip `f4dd286f7888b348c757b9a2f28dd7bde4c3532b` includes
`cpuidle-apple`:

- state 0 calls ordinary `cpu_do_idle()` / WFI;
- state 1 saves x18–x30, unconditionally reads and writes
  `SYS_IMP_APL_CYC_OVRD` (`s3_5_c15_c5_0`), then executes deep WFI;
- both are registered as s2idle entry states.

The driver allowlist, expanded for M3 by `33bdeb453661`, ends at T6034. It
deliberately excludes T8132/T6040/T6041. Adding only `apple,t6040` would not be
a harmless enablement:

1. this raw-boot machine has `apple_sysregs_unlocked = false`, while the driver
   writes CYC_OVRD unconditionally;
2. T6040 WFI/WFIT has already lost architectural state on secondaries, which
   is why m1n1 `features_m4` carries `broken_wfi = true` and parks them in WFE;
3. m1n1 still sets `features_m4.sleep_mode = SLEEP_NONE`, explicitly recording
   that the older deep-sleep mode is not known for M4;
4. working Linux boots use `idle=nop`, which removes WFI/WFIT globally.

With `idle=nop` and no T6040 cpuidle driver, generic s2idle can only spin in its
idle loop. It may remain logically wakeable, but it does not establish a
low-power state and is not a meaningful suspend test. `maxcpus=1` does not fix
the missing retention contract; it merely avoids exposing additional cores.
Conversely, enabling ordinary or deep WFI to make a one-core test “real” would
reintroduce the unreviewed fatal boundary.

## Device-side incompleteness

Even after a safe CPU idle mode exists, J614s system suspend requires verified
wake/PM behavior for the AIC, PMGR domains, SMC ASC, DockChannel keyboard,
simpledrm/firmware scanout, and eventually the chosen persistent-storage and
USB/ATC paths. Current B0 intentionally omits most of those devices. A first
CPU-idle experiment must not be combined with full system suspend.

## Required order before any live proposal

1. Upstream or an Apple-silicon PM maintainer supplies/reviews a T6040-specific
   idle contract: register-retention behavior, any permitted CYC_OVRD handling
   under locked sysregs, wake IRQ semantics, and per-core/cluster scope.
2. Audit the implementation statically against `broken_wfi`, then build a
   storage-disabled `idle=nop` control and a one-boundary cpuidle candidate.
3. Validate one secondary core's bounded idle/resume independently of s2idle,
   with exact hashes, watchdog, DebugUSB, and a separate rig ticket. Do not
   infer safety from M3/T603x.
4. Validate the ticket-061 read-only SMC node and lid/power hard-wake events
   without entering deep idle.
5. Only after both halves pass, propose a RAM-root s2idle cycle. Add device
   suspend one subsystem at a time; persistent-root suspend comes last.

No direct sysreg/MMIO/SMC write experiment is justified now. Continue using
`idle=nop`; suspend remains outside B0 and the initial usable-RAM-distro
milestone.
