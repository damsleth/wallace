# T6040 post-B0 "usable machine" experiment ladder

Date: 2026-07-24. Companion to `BOOTABLE_BUILD_EXPERIMENTS.md` (B0 spine:
untethered RAM-distro → enrolled cold boot). This ladder covers the **enablement
lanes that turn B0 ("boot picker → m1n1 → Alpine login") into a usable machine**,
and is deliberately kept *out* of the B0 cold-boot proof per that doc's rules
(one boundary at a time). Everything here is post-B0 or parallel-offline; each
live step keeps the same gate: own hashes, independent review, preflight, rig
ticket, CJ approval, lease.

Current B0 state: ticket 100 passed the tethered single-object OpenRC boot,
including panel shell and internal-keyboard echo. Ticket 101 is approved for
the maintainer-executed enrolled cold boot but remains blocked on ticket 082's
identity/backup/object-review fields and the rig's NEEDS_RECOVERY state.

## Where each experiment stands (most are already readied)

| # | Experiment | Ticket | State | End-goal contribution |
|---|---|---|---|---|
| U1 | **maxcpus=2 SMP** → then all 14 cores | 005 (+034) | approved, pinned | responsiveness; the machine uses its cores |
| U2 | **cpufreq DVFS** (E 7-ps, P 19-ps to 4512 MHz) | 006 (+035) | approved, DT built (`a42bb096`) | thermals + performance scaling |
| U3 | **Interrupt-driven console** (IRQ 816) | 073 (+062) | approved, pinned | a non-busy-poll console; prereq for a printk console |
| U4 | **SMC**: power button, lid, battery status | 061 | offline, open | on-device power control + battery gauge (read-only keys) |
| U5 | **On-device framebuffer console** | 083 (+079/+100) | **done** | a real local shell on the laptop panel, not just ttydc0 |
| U6 | **PCIe link-up** (op-115 clkgen-PLL) | 068 (+058) | approved, pinned | unblocks WiFi/BT + SD reader |
| U7 | **WiFi/BT bring-up** after link-up | 044 → 030 fw | offline pre-review | networking |
| U8 | **Daily-driver feature DT** (integrate U1+U2+U3) | **new (084)** | to file, post-B0 | one DT the usable build actually ships |

## Sequencing / dependencies

```
B0 (Sol) ──► U1 SMP ──┐
                      ├─► U8 daily-driver feature DT ──► "usable RAM distro"
B0 ──► U2 cpufreq ────┤          (integrate, one gate at a time)
B0 ──► U3 IRQ console ┘
B0 ──► U4 SMC power/battery ─────► on-device power control
B0 tethered proof ──► U5 fbcon shell PASS; 101 makes it untethered
U6 PCIe link-up ─► U7 WiFi/BT ───► networking (then B2 USB root also unblocks)
```

Order rationale: U1/U2/U3/U4/U5 are independent single-boundary boots that each
extend B0; **U8 only integrates them after each has passed individually** (never
combine unproven boundaries). U6→U7 is the separate PCIe pole (also gates the
B2 USB-root persistent-storage path once the ATC/HPM physical link is solved).

## New experiments this ladder adds

### U5 — on-device framebuffer login (ticket 083, offline → gated rig)
A truly untethered *usable* machine
needs a login on the **internal panel**. simpledrm+fbcon already render the m1n1
framebuffer (proven at the BusyBox console). Experiment: add an OpenRC getty on
`tty0`/`/dev/fb0` console in the RAM distro, confirm keyboard input at that
console (depends on the HID restore, ticket 078), and verify the panel shows the
login at native resolution. No new MMIO; DT/framebuffer already provided by
m1n1. Offline: build the getty-on-fbcon initramfs delta + host-check init/service
ordering; then a gated one-shot rig boot. Pass: panel login prompt + keyboard
echoes locally with no ttydc0 dependency.

Ticket 079's exact Alpine/OpenRC B0 image contains the U5 delta:
its inittab respawns the local diagnostic shell on `tty0` and separately waits
for `ttydc0`; no ttydc0 dependency exists for the panel. Host validation and
two-build reproducibility pass at `ddd981711e91...`. Ticket 100 then
live-proved the panel shell and local keyboard echo, so 083 is done. A
conventional password-authenticated getty is distro hardening, not another
hardware boundary. Exact artifact and result:
`done/2026-07-24-t6040-alpine-b0-release-bundle.md` and
`done/2026-07-24-t6040-b0-alpine-openrc-single-object-result.md`.

### U8 — daily-driver feature DT (ticket 084, offline, strictly post-B0)
Once U1 (SMP), U2 (cpufreq), and U3 (IRQ console) have each passed a solo rig
boot, build **one** integrated J614s DT that carries all three (14 cores,
cluster-cpufreq, IRQ-816 console) on the proven base, host-validate (dtbs_check),
pin, and propose a single integration boot. This is the DT the usable RAM distro
ships. It is the *only* step that combines boundaries, and only proven ones.

## Explicitly out of scope here (tracked elsewhere)
- B0 itself and enrollment: `BOOTABLE_BUILD_EXPERIMENTS.md`; 081/100 passed,
  082/101 own the remaining enrolled cold boot.
- Persistent storage (B2): right HPM2 reaches S0; 096 still owns rollback,
  image 098 is complete (`1c493fad...`), and decomposed
  link/block/flash/root tickets own the remaining path. Internal NVMe remains
  behind SPTM.
- GPU (drm/asahi), audio, ISP/webcam, suspend: upstream-tracked (039/040/027);
  not on the usable-RAM-distro path. GPU mule prep 039 is complete: there is
  no current G16 candidate, and the ready evidence/test contract explicitly
  forbids reusing a G14 identity. Suspend analysis 027 is complete: current
  T6040 deep WFI is unsafe under locked sysregs, so keep `idle=nop`.
- Trackpad motion (004): a comfort, gated on tpmtfw provisioning (016).

## Milestone definition ("usable machine")
B0 + U1 + U2 + U4 + U5 = **the M4 cold-boots to an Alpine login on its own
panel and keyboard, all cores online with DVFS, power button and battery
working, no tether and no external anything.** U6/U7 (networking) and B2
(persistent storage) follow. That is the honest "usable daily-driver, minus GPU
accel / WiFi / persistent disk" target, all reachable with no forbidden writes.
