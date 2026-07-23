# t6040 Linux bring-up — NEXT STEPS

Handoff state (2026-07-13): mainline Linux boots to a BusyBox shell on the
M4 Pro with working internal keyboard, watchdog, and a **fully remote dev
loop** — two-way m1n1 proxy AND Linux shell (`/dev/ttydc0`) over one DebugUSB
cable; reboot via `macvdmtool`. No screen-reading or physical access needed.
Operational details, recipes, and history: `DEVLOG.md`. Long-term: `ROADMAP.md`.
Read the DebugUSB link rules in DEVLOG before touching the rig.

## Immediate storage-path gate: map USB ports, then smoke host mode

The first USB2-host kernel/DT/initramfs set now builds and passes static checks;
hashes and exact no-root boot procedure are in
`done/2026-07-21-t6040-usb-host-smoke-preflight.md`. Do **not** boot its current
three-port DTB yet: an independent review identified an avoidable role risk
because the physical DWC3 index carrying the DebugUSB/DFU tether is unknown.

Rig ticket 057 is the reviewed, approved next step. It captures the existing
ADT over KIS using RAM reads only (no Linux boot, USB init, MMIO, PMU/SPMI, or
target-memory writes); procedure and helper hash are in
`done/2026-07-21-t6040-usb-port-map-adt-preflight.md`. After CJ approval and
capture, build a single-port DTB that leaves the DebugUSB port disabled, repeat
the hash/cross-review, then propose the no-`root=` USB enumeration smoke. Only
after that device remains present for 10 seconds should an external distro
rootfs be populated or mounted.

**Result 2026-07-21:** the initial KIS attempts failed even after a cold start
because the tether was on the wrong physical port. Moving it to the previously
proven top-left/rear port restored KIS. Ticket 057 then captured the ADT
successfully and established the authoritative map: `usb-drd0 = left-back`,
`usb-drd1 = left-front`, `usb-drd2 = right`. Keep `usb-drd0` disabled because it
carries DebugUSB. Build/hash/cross-review only the one-port DTB matching the
external drive, then run the no-`root=` smoke. Exact capture result:
`done/2026-07-21-t6040-usb-port-map-adt-result.md`; failed-attempt history:
`done/2026-07-21-t6040-usb-port-map-adt-attempt.md`.

**Drive selection 2026-07-21:** the external drive is on the right-side port,
so the live candidate is exclusively `usb-drd2` /
`t6040-j614s-dcuart-usb-host-right.dtb`, SHA-256
`9bee944b8bb0d6d7ab541962ea2edc9a57c4069fedcd6c32db21e3b824a43759`.
Ticket 063 is proposed with the independently reviewed six-file manifest; do
not substitute the left-front or retired all-port DTB.

**Smoke result 2026-07-21:** ticket 063 ran once. The right-side DARTs and xHCI
controller initialized cleanly at `0x392f00000`/`0x392f80000` and
`0x392280000`, but both the initial and ten-second reports showed only the two
root hubs. No child USB device or `sd*` appeared; the shell remained responsive
and there was no SError, DART fault, reset, or NVMe probe. Do not populate the
rootfs yet. Ticket 064 has now bounded the failure: the saved ADT contains a
right-side SPMI HPM (`hpm2`), T6040 ATC PHY (`atc-phy2`), and shared `acio2`
parent, but the Linux DT exposes none of that physical-link path. The
force-host patch creates xHCI while its generic PHY handles are absent; it
cannot establish CC/orientation, eUSB2-repeater state, or host PHY mode. Exact
analysis: `done/2026-07-21-t6040-usb-right-no-connect-analysis.md`.

**Storage-free pivot, 2026-07-23:** the powered hub's supply is unavailable, so
ticket 065 is cancelled unrun. Ticket 066 built and host-validated a
reproducible Alpine 3.24.0 aarch64 RAM-root: 3.9 MB compressed, loaded entirely
through m1n1, with a DockChannel Alpine shell and no storage dependency. Ticket
067 then booted it successfully: Alpine 3.24.0/aarch64 reached a responsive
shell, the RAM-only write test passed, `/proc/partitions` was empty, and no
storage controller probed. The internal keyboard did not register, however:
MTP firmware reached `Keyboard ready`, but the 7.1.3 USB-host kernel stopped
with a zero-ID HID device and no `/dev/input`. This is a kernel/DockChannel
receive-path regression, not an Alpine userspace issue. Offline ticket 069
found no config, DT, or HID-source omission and tested the mailbox driver's
unmasked W1C-acknowledge/threaded-drain window as a possible lost-RX race.
Ticket 071 booted the exact mask/drain/re-arm candidate once. Alpine and ttydc0
worked and `/proc/partitions` stayed empty, but input registration remained
absent: empty `/proc/bus/input/devices`, no `/dev/input`. The race correction
is therefore not a sufficient HID fix.
The independently reviewed local control, ticket 070, was run and repeated once
at the maintainer's request. Both attempts handed off, showed kernel text, then
returned to the Asahi/m1n1 logo without presenting the Alpine framebuffer
shell. With no ttydc0 in that old kernel there is no post-handoff host log, and
the keyboard could not be tested. Do not retry the old-kernel/Alpine
recombination, and do not retry ticket 071. Offline ticket 072 has now built
and statically verified the observation-only current-kernel trace across
DockChannel hard IRQ/pending bits, FIFO drains, DCHID event/report parsing,
STM-ready state, and identity/interface creation. The exact storage-disabled
candidate is `Image-hid-state-trace` (`e7138c03...`) with the unchanged
ticket-071 DTB (`2782b922...`) and ticket-067 config (`8e11399b...`). It adds
read-only counters and sparse semantic logs but no receive kick, retry, new
MMIO access, or control-flow change. Independent exact-artifact review passed.
Ticket 074 then ran once: ttydc0 TX delivered the Alpine banner and prompt, but
RX accepted neither LF, CR, nor the terminal-position response, so none of the
trace commands could run. The host KIS daemon, raw PTY, and persistent reader
were healthy. The pre-registered stop was taken and recovery restored
`Running proxy...`. Do not repeat 074 unchanged. Offline ticket 075 built a
bootarg-gated initramfs reporter that automatically emits the same bounded
trace/input/partition inventory over working ttydc0 TX without requiring an
inbound shell command. Its exact reproducible archive is
`d5b790c63276816a3d69071797da459918717924885174d2a8b84225c6b24093`;
host gating/output tests and embedded-script identity pass. Independent exact
artifact review passed with the rig untouched. Ticket 076 is the resulting
one-shot TX-only capture proposal and remains proposed pending explicit
maintainer approval; do not run it from an unanchored short-lived process.
Analysis, preflight, and result:
`done/2026-07-23-t6040-alpine-hid-regression-analysis.md` and
`done/2026-07-23-t6040-alpine-hid-rx-rearm-preflight.md`, and
`done/2026-07-23-t6040-alpine-hid-rx-rearm-result.md`. Trace artifact and
procedure:
`done/2026-07-23-t6040-alpine-hid-state-trace-preflight.md` and
`done/2026-07-23-t6040-alpine-hid-state-trace-result.md`. Automatic reporter:
`done/2026-07-23-t6040-alpine-hid-trace-auto-reporter.md`; replacement
preflight: `done/2026-07-23-t6040-alpine-hid-trace-auto-preflight.md`. Old
control preflight and result:
`done/2026-07-23-t6040-alpine-keyboard-control-preflight.md` and
`done/2026-07-23-t6040-alpine-keyboard-control-result.md`.
Artifact, preflight, and result:
`done/2026-07-23-t6040-alpine-ramroot-artifact.md`,
`done/2026-07-23-t6040-alpine-ramroot-preflight.md`, and
`done/2026-07-23-t6040-alpine-ramroot-boot-result.md`. The powered USB test may
be revived later when a valid fixture exists; HPM/ATC remains the
persistent-root blocker. Exact initial USB run result:
`done/2026-07-21-t6040-usb-host-right-smoke-result.md`.

## Bootable-build ladder: B0 first, persistent root later

The next honest machine-level milestone no longer waits on USB or internal
NVMe: boot picker → enrolled raw m1n1 object → self-contained Alpine RAM distro
on simpledrm/fbcon with internal keyboard, watchdog, and no host payload upload.
The detailed experiment contract and safety gates are in
`docs/BOOTABLE_BUILD_EXPERIMENTS.md`.

After approved trace capture 076, ticket 077 decodes the exact HID boundary,
078 builds one minimal evidence-backed repair candidate, and 079 turns the
working result into a release-like RAM distro. In parallel, 080 audits the
raw-object payload layout and builds a host verifier. Ticket 081 packages one
self-contained object and prepares a tethered one-object proof without
`linux.py`; 082 prepares, but does not execute, reversible enrollment and cold
boot. Every live step still gets a separate reviewed exact-hash rig ticket and
explicit approval. U-Boot/EFI is B1 after this direct-m1n1 B0 proof unless the
layout audit proves it is required.

Persistent Linux state remains B2: tickets 023/032/060 resume the external USB
root path only with a powered/self-powered fixture or reviewed T6040 HPM/ATC
support. Internal NVMe remains blocked by SPTM/CoastGuard. Do not fold storage,
SMP, cpufreq, PCIe, or enrollment into the first self-contained boot.

Keep the first USB smoke at `maxcpus=1 idle=nop`. The DT's extra `cpu@10105` is
correctly disabled and 14 cores are available, but Linux secondary-core bring-up
is still a separate staged experiment (tickets 005/034); do not combine it with
the first USB-host test.

**Upstream correction, 2026-07-21:** a bounded m1n1 experiment on M4 Pro
measured DockChannel-UART on AIC input **816**; the ADT's 360 is wrong. The
standard USB-smoke DT uses `apple,poll-mode`, so this does not change its console
behavior, but all newly built DTBs must carry 816. Yuka's WIP `more-t6041`
branch also reached a shell on M4 Pro with all cores and PMGR, providing strong
family-level SMP evidence. It is not a J614s-ready artifact (its inherited CPU
topology and memory-channel domains do not match this 14-core board), so ticket
034 remains the gate and the USB smoke stays single-core. Full 11–21 July log
review: `done/2026-07-21-asahi-dev-log-review.md`.

## 0. Retire IRQ-360 diagnostics; evaluate the direct IRQ-816 driver offline

The 2026-07-14 diagnostics below are retained as experiment history. They used
the ADT-provided input 360, now known not to be the UART interrupt. Their direct
FIFO observations remain valid, but they cannot establish whether the real AIC
input 816 works or fails. Do not run ticket 059 or any other 360-based image.
Instead, audit the direct `apple,dockchannel-uart` driver from `more-t6041`
(data register first, `earlycon=dockchannel,mmio32,0x50882c000`, `ttyDC0`) and
adapt it to the measured J614s DT before proposing a new live console test
(offline ticket 062).

The storm-bounded UART TX/RX BIT(2)/BIT(1) diagnostic ran once on 2026-07-14.
Linux reached BusyBox and TX worked, but neither an LF-terminated nor a
CR-terminated host command was echoed or answered. The image was not retried;
DebugUSB recovery restored a fresh proxy. Full hashes and result:
`done/2026-07-14-t6040-dockchannel-irq-retest.md`.

This does not rehabilitate the old "dead IRQ across all 4096 AIC inputs"
claim: that scan still enabled the FIFO with MTP's wrong RX BIT(3), while the
corrected run could not use RX to retrieve `/proc/interrupts`. A TX-only,
self-reporting initramfs then ran once. It printed its instruction banner, took
the approved probe line during the TX-silent interval, and never emitted its
post-window report. The BusyBox timeout path works in an arm64 PTY test, so the
timing strongly suggests the RX event stalled the shared IRQ-driven TX
completion path or tripped the guard. Exact result:
`done/2026-07-14-t6040-dockchannel-irq-tx-report.md`.

The replacement diagnostic ran once on 2026-07-14 (rig ticket 001, reviewed
and approved; result:
`done/2026-07-14-t6040-dockchannel-rxirq-txpoll-result.md`). It left RX
interrupt-driven on BIT(1), never unmasked TX BIT(2), and relayed ten
per-second telemetry samples flawlessly over polled TX. The outcome is the
pre-registered matrix's third row exactly: after the single approved
`IRQ_BIT1_PROBE` injection, the handler never entered (`total=0`), the raw
local `IRQ_FLAG` stayed 0, `DATA_RX_COUNT` stayed 0 at every sample, the
joined `/proc/interrupts` row (`virq=42`, AIC2 hwirq `65896`) stayed at zero,
and userspace received nothing. **The injected bytes never entered the AP-side
FIFO, so AIC delivery was never exercised**; investigate mask-write or
pre-handoff perturbation, not AIC delivery. Neither storm cap triggered.

One pre-run claim is corrected: the AIC driver encodes IRQ hwirqs as
`((die + 1) << 16) | input`, so die-0 input 360 displays as hwirq 65896
(`0x10168`), not 360; the telemetry's explicit virq→hwirq join is what made
the zero count interpretable.

The sharpest open question is a build delta: the earlier TX-only reporter
received the probe once in an IRQ-mode build, while this build saw no byte
arrive at all. Offline ticket 049 (`rx-path-delta-analysis`) scopes that:
diff the probe/startup IRQ-block writes and RX_THRESH timing between the two
builds and analyze the dock-side KIS agent's flow-control interaction with
AP-side IRQ_MASK state.

The ACK/read-order audit is also pre-run evidence. Safe m1n1 commit `eed11760`
only accesses the UART data FIFO and never touches its IRQ mask/flag block, so
it cannot leave BIT(3) set before handoff. The older working DockChannel/HID
stack uses RX BIT(1), W1C-acks the child IRQ in its irqchip, masks RX in its
hard handler, and only afterward reaches its threaded/data-consumption path.
The current mailbox driver instead W1C-acks RX and wakes its thread while RX
remains unmasked. Thus the diagnostic preserves its existing W1C semantics and
tests whether reassertion stops when RX is masked; it does not assume that
drain-first is required.

Pre-registered interpretation matrix — **filled 2026-07-14: row 3 matched**
(the other rows are retained for reference; none of their conditions
occurred):

| Cap/flag | Post-mask result | FIFO movement | Pre-registered conclusion |
|---|---|---|---|
| no cap; `total=0`; current `rx_count>0`, raw `irq_flag&2` | no `/proc/interrupts` delta on the telemetry-mapped virq | bytes present | historical only: would have tested ADT input 360, now known not to be the UART route |
| no cap; small RX count | stabilizes below 1,000 | FIFO drains and probe is delivered | corrected RX IRQ works; old dead-IRQ claim is withdrawn |
| **no cap; no RX count/flag** ✅ | **no delta** ✅ | **FIFO remains zero after injection** ✅ | **bytes did not reach this build; investigate mask-write or pre-handoff perturbation, not AIC delivery** |
| cap at RX 1,000 with `cap_flag&2`; `hard=0` | `post_cap` stabilizes near zero and `cap_mask=0` | either | RX-data-triggered storm is real, but local masking stops it; repair completion/ACK handling |
| cap at RX 1,000; hard-disable at total 1,024 | `post_cap=24`, `hard=1`, flag remains asserted | `hard_fifo > cap_fifo` | bytes continued arriving during the masked storm; sticky source remains coupled to FIFO data flow |
| cap at RX 1,000; hard-disable at total 1,024 | `post_cap=24`, `hard=1`, flag remains asserted | `hard_fifo == cap_fifo` | storm is decoupled from new data after masking; reproduce sticky/reasserted BIT(1) and audit flag semantics |

Exact hashes, MMIO delta, audit, and both the artifact record and the run
result are in `done/2026-07-14-t6040-dockchannel-rxirq-txpoll.md` and
`done/2026-07-14-t6040-dockchannel-rxirq-txpoll-result.md`.

Keep the standard 5 ms full-poll mode for current boot artifacts. Do not retry
any completed BIT(1)/IRQ-360 image, and do not publish the old scan as a
hardware erratum: it targeted the wrong AIC input and, in the last run, no byte
reached the FIFO.

Ticket 049 is done (`done/2026-07-14-t6040-dockchannel-rx-path-delta.md`): the
static delta audit rules out direct software flow-control coupling and shows RX
setup itself did not change between the builds. Its proposed ticket-059 timing
follow-up is superseded by the measured IRQ-816 correction; ticket 059 is closed
and must not be revived unchanged.

The IRQ-816 correction comes from the #asahi-dev logs, not our rig: yuka's
measurement experiment and enverbalalic's reproduction on real T6041 hardware
both show the ADT's dockchannel-uart input 360 is an Apple copy-paste error and
the real AIC input is **816** on t6040/t6041 (full trawl:
`done/2026-07-21-asahi-dev-irc-review.md`). Our `total=0` RX result is consistent
with having listened on input 360. **Next step is ticket 062**
(`dockchannel-irq816-path`): rebuild the DT on IRQ 816 with the data reg
(`0x50882c000`) first for earlycon, make the RX/TX bits a DT property, then
propose a fresh interrupt-driven `ttyDC0` rig retest.

## 0.1 Extend the proven T6040 PCIe path through PHY setup

The former register-map blocker is solved. Static analysis of the paired macOS
kernelcache proves the two new T6040 groups target ADT reg[5] (CIO3 PLL at
`0x415046200`) and reg[6] (PCIe clkgen at `0x415044000`). m1n1 main
`eb23c423` / curated `da1791a0` apply them and then run the reused T6031/T8122
sequence. The separate `t6040-j614s-dcuart-pcie` kernel DT builds cleanly and
describes BCM4388 WiFi/BT on port 0 plus the GL9755 SD reader on port 1.

The initial approved diagnostics ran on 2026-07-14. The first completed all 77
AXI tunables and stopped after `pcie: No common tunables`. The traced retry on
main `81da3522` delivered the real failure earlier: AXI tunable `[70]`, manifest
operation 90 in that build, printed `done`; before `[71]` was announced, m1n1
took an asynchronous SError (`L2C_ERR_STS=0x82`) in the proxy `P_CALL`
trampoline and rebooted. Because the fault is asynchronous, `[70]` is only the
delivery boundary, not proof of the causal write. The sanctioned DebugUSB
recovery restored a stable proxy. Linux never handed off, no PHY/port/PERST
operation ran, and no storage was accessed. Exact trace:
`logs/t6040-console-20260714-pcie-axi-trace.log` (SHA-256
`41774ef8866e775de30ca2c98957d167085943163fe24d25c7aaca29eb177860`).

Offline disassembly then exposed a real ordering difference. J614s has eight
PCIe `clock-gates`; `ApplePCIEBaseT8132::_enableRootComplex()` enables gates
0–6, applies AXI then CIO3 and clkgen tunables, and only afterward enables gate
7 (`APCIE_PHY_SW`). m1n1 previously enabled all eight before AXI. Main
`6efe2d45` and curated `954fd4cf` reproduce Apple's staging and retain the
diagnostic return before the first PHY register access.

The separately approved staged run used main binary SHA-256
`c2a5b7e27bb8d56479f46d6b485a195d2eb1cd64a3b86fbe3c90db1f00424735`
and the exact 105-operation subset in
`done/2026-07-14-t6040-pcie-clock-diagnostic.tsv` (SHA-256
`ce86e51aa3d278da1d9ef9eb35fca3208859f4993480de5b6af3268dc03ef4e6`).
It produced the same result: AXI `[70]` at `0x4160013fc` printed `done`, then an
asynchronous SError arrived before `[71]`, with `L2C_ERR_STS=0x82`. It never
reached CIO3, clkgen, the late gate, PHY, ports, Linux, or storage. Therefore
early `APCIE_PHY_SW` enable was not the cause. Exact transcript:
`logs/t6040-console-20260714-pcie-staged-gate.log` (SHA-256
`c31275546280b9df2dbf9b014d2e6411cfb708f87f1c803e10b11e2cdb95ec2f`).
DebugUSB recovery restored a fresh, quiescent proxy.

The no-new-address follow-up ran at m1n1 main `00760c79`
(`v1.6.0-68-g88ce1ee3`), binary SHA-256
`2997b07647007f99df6ad094a2da55d66a9f7accd6758bb134d3fa92b76d0c72`.
It placed `dsb sy` and a read-only `L2C_ERR_STS` sample before the first and
after every existing traced RMW, aborting on a nonzero result without clearing
status. AXI `[70]` again printed `done`, proving its barrier completed and its
status sample was zero; the same SError then arrived before `[71]`. Thus the
status becomes visible only with the delayed exception and cannot attribute an
individual write this way. Transcript:
`logs/t6040-console-20260714-pcie-barrier.log` (SHA-256
`cebc058921b62b2f594855bb65db28b312570b6c707f5a29a29480c31c04667b`).
Recovery restored a fresh quiescent proxy. Full result:
`done/2026-07-14-t6040-pcie-barrier-diagnostic.md`.

The zero-PCIe-write trace-volume control ran at main `3e772779`
(`v1.6.0-72-g3e772779`), binary SHA-256
`c9296b8d1ca146a32c7a1ba1bf17b7091281588ab90d16a69f0718c5a8fa04ea`.
It enumerates the same ADT AXI entries and prints the identical 77 pre/`done`
pairs, but returns before enabling any PCIe clock or reading/writing controller
MMIO. It nevertheless produced the same SError after `[70] done`. This proves
that the traced SError is entirely a console/log artifact, not a PCIe access.
Transcript: `logs/t6040-console-20260714-pcie-trace-dry-run.log`, SHA-256
`52431e2a9a7d87642fde917419f3e8e666672434953cad23466c13b61968742d`.

The exact mechanism was bounded offline. The 16 KiB m1n1 log buffer was
`0x105ce7a4000..0x105ce7a8000`, ending exactly at the top of normal RAM; every
SError reports that exclusive end in `L2C_ERR_ADR`. When the log device becomes
writable, `iodev_console_write()` first flushes its retained 8 KiB console
backlog. The identical post-allocation stream contributes another 9,274 bytes:
the ring crosses its end during `[61] done`, then the asynchronous error is
delivered 1,082 bytes later after `[70] done`. The zero-PCIe-write upper-guard
control ran at main `eed11760` (`v1.6.0-75-ga61fd099`), binary SHA-256
`1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b`.
It keeps the active 16 KiB ring one unused 16 KiB page below top-of-RAM and
repeated the identical dry-run trace. All 77 entries and the completion marker
printed without SError, and the base kernel reached its BusyBox shell. This
live-proves the upper guard and fully exonerates the PCIe sequence from the
traced `[70]` failure. Exact m1n1 transcript:
`logs/t6040-console-20260714-logbuf-upper-guard.log` (SHA-256
`2e8624d795bc6bddab24b932a530bf7f992f35732402ed041bfc308857260d63`).
Full result: `done/2026-07-14-t6040-logbuf-upper-guard-control.md`.

The Apple-ordered 105-operation path was restored at main `f46d6e35`
(`v1.6.0-78-gf46d6e35`), binary SHA-256
`8fd7319047187f9ca05a6924462a4f24360fcc1d9e4279b089dc83a5acb05744`.
It retains the proven upper guard, per-RMW barriers/status samples, exact
manifest SHA-256
`ce86e51aa3d278da1d9ef9eb35fca3208859f4993480de5b6af3268dc03ef4e6`,
Apple clock-gate order, and hard return before operation 106, the first PHY
write. The approved run completed all 105 operations: all 77 AXI entries, the
RC write, all seven CIO3 PLL entries, the PCIe clkgen entry, and the late
`APCIE_PHY_SW` gate. It then took the intentional stop before PHY, handed off
the PCIe-free base DT, and reached BusyBox with no nonzero L2 status or SError.
Exact transcripts and hashes are in
`done/2026-07-14-t6040-pcie-guarded-clock-diagnostic.md`.

The exact shared-PHY continuation ran at m1n1
main `85b01036` (`v1.6.0-81-gb5ced9ba`), binary SHA-256
`add3cef43947dab1605bd95ad602b6dcbf8e89de0a3f1b43f278005cd52dd9da`.
It completed operations 1–114, including all five controller PHY tunables,
reference-clock availability, both clock acknowledgements, reset release, and
T8122 pre-tunable control. It then stopped after printing the pre-line for
operation 115, the first PHY-IP PLL RMW at `0x417040090`; no `done` or exception
followed. Linux did not hand off and no port or storage access ran. The
351-operation manifest SHA-256 is
`d4496968ee8fc1202bd4d47247fc6bbaa36f0a3f7cc872a81efabe72327c50fc`.
Exact result and transcript:
`done/2026-07-14-t6040-pcie-phy-diagnostic.md`.

The reviewed read-only isolation then ran once at main `dc7124fb`, binary
SHA-256
`5616b05fdd21a35990102ce8b711920ec8c442f75c89ce6cfe27da2f24adef67`.
Operations 1-114 again completed. The pre-read marker for the ADT-derived
32-bit access at `0x417040090` printed, but no value/completion, L2C status, or
exception followed. Thus operation 115 stalls on its read side; the earlier
combined RMW cannot implicate its write half. No operation-115 write, later PHY
entry, port, Linux PCIe, NVMe, or storage access ran. DebugUSB recovery restored
a quiescent proxy. Exact review, artifacts, result, and transcript:
`done/2026-07-14-t6040-pcie-op115-cross-review.md` and
`done/2026-07-14-t6040-pcie-op115-read-result.md`.

Do not try a write-only operation 115 or move the later PHY-clock poll ahead of
the tunables without new static evidence. Continue offline route-finding for
the missing PHY-IP aperture precondition/Apple transition, then require a new
manifest, cross-review, and explicit approval for any changed live sequence.

## 1. Provision and test the J614s trackpad firmware
`event0` is Apple DockChannel Multi-touch and `event1` is the keyboard. The
transport's missing firmware loader and stuck-start error path are fixed and
live-tested in kernel build #12: repeated opens now independently request
`apple/tpmtfw-j614s.bin` and return `-ENOENT`, with no invalid resets or stale
`-EINPROGRESS`. Retrieve the paired HIDF blob from this target's Asahi ESP at
`vendorfw/apple/tpmtfw-j614s.bin`, or process its
`asahi/all_firmware.tar.gz` with `asahi-fwextract`, then rebuild with
`TRACKPAD_FIRMWARE=/path/to/tpmtfw-j614s.bin`, and retest motion. If MTP then
requests its reset GPIO, stop: the now-derived `gp1c` function resolves through
the ADT's `smc-pmu` node, and PMU writes are forbidden by the project rules.
No tactile click is expected yet (the haptic actuator is a separate interface).
Full finding:
`done/2026-07-12-t6040-trackpad-firmware.md`.

## 2. Review and upstream the proven T6041 PMGR quirk
The full 214-domain topology now boots to BusyBox **3/3** with the exact minimal
temporary policy: preserve firmware-active domains, disable only `disp_cpu`,
and skip auto-enable only on `dispext0_cpu` and `dispext1_cpu`. Both CPU skips
are individually necessary at bank granularity; the `sys`, `fe`, and five old
ANE exclusions are unnecessary. Legacy raw fails 3/3. Full matrix and hashes:
`done/2026-07-12-t6040-pmgr-matrix.md`.

The supported shape is now implemented and live-tested in build #14. The
two-patch draft starts with `patches/t6040-pmgr-t6041-bindings.patch`, then
`patches/t6040-pmgr-t6041-quirks.patch` selects preserve-active and the two CPU
auto-enable exceptions from `apple,t6041-pmgr-pwrstate`; Linux `37339d595765`
removes the experiment-only properties from the standard DT. The series passes
checkpatch and both binding schemas validate. No further policy bisection is
needed.

Next, in leverage order:
1. Ask flokli for the J773s PMGR policy (draft only here; maintainer sends).
2. If pre-userspace attribution becomes necessary, first add a bounded
   polled/atomic TX primitive to the DockChannel mailbox. Do not register the
   current `ttydc` kfifo/workqueue path as a printk console: it is not safe in
   atomic or panic context and can recurse through its own error printk.

Done this session: raw determinism, requested core-infra and PMGR1 isolations,
live ADT regeneration, `no_ps` parent filtering, and safe always-on generation
(no policy by default; explicit legacy flag only).

## 3. Solve protected T8140 NVMe queue ownership

The power and coprocessor side is now proven. Linux forces the three gated PCIe
parents actual-on, activates the CoastGuard SART, allocates RTKit buffers,
boots ANS, and reads `APPLE_ANS_BOOT_STATUS_OK`. The remaining failure is not a
DT, PMGR, SART, or RTKit problem.

T8140 protects both the legacy linear-queue/NVMMU setup and the standard NVMe
queue registers. Main-BAR reads/writes at `MAX_PEND`/AQA fault; the secure BAR
at CPU PA `0x44dcc0000` is readable and contains iBoot's disabled-controller
admin queue state. Static analysis of the paired macOS kernel and
IONVMeFamily resolved the real interface: Apple calls `_pmap_iommu_ioctl`,
whose NVMe backend enters SPTM with service 6 operations 0–8 for controller
initialization, TCB authorization, admin/I/O queue registration, and queue
activation.

The exact service-6 operation 0 + operation 4 sequence was implemented in
`patches/t6040-nvme-sptm-debug.patch` and tried once. Raw m1n1 reports
`SPRR_CONFIG_EL1=0` and `GXF_CONFIG_EL1=0`; Linux reached
`before protected admin queue setup`, then hung at Apple GENTER
(`.inst 0x00201420`). No SPTM call returned. The watchdog recovered to m1n1.
Do not repeat that call unchanged, and do not resume direct main- or secure-BAR
writes.

The preservation question now has a structural answer: iBoot's secure ASQ/ACQ
buffers (`0x101005db000` / `0x101005dc000`) live in ordinary RAM that m1n1 does
not reserve, and the macOS path performs service-6 TCB authorization for each
command. Preserving only those queues cannot provide a complete Linux NVMe
path. Keep further work static: determine whether raw boot can acquire the
required protected execution state through a documented loader transition or
whether storage must wait for upstream M4 SPTM support. No Identify command has
run; never mount, repair, format, flush, or write the namespace.

The service-6 ABI is now fully decoded from the paired M4 target kernelcache
(Darwin 25.5.0, RELEASE_ARM64_T6041; ticket 007,
`done/2026-07-14-t6040-sptm-service6-abi.md`). Selector `x16 = op | (service<<32)`,
read directly off the kernel's per-(service,op) GENTER veneer table; service 6 =
NVMe with exactly 9 veneers, ops 0..8 (0 = init, 1 = TCB auth, 4 = admin queue
setup with the ASQ/SQ-depth/ACQ/CQ-depth arg layout already reproduced; the
enable/query ops map to the named `AppleANS2CGv2Controller` methods). The decode
confirms the blocker is **not** ABI knowledge: each veneer's shared guard-enter
helper bumps a per-thread reentrancy counter and spins on `mrs s3_6_c15_c8_0`
before GENTER, requiring a live GXF gate. Raw m1n1 boots with `GXF_CONFIG_EL1=0`
and an unconfigured GENTER entry vector, so GENTER wedges (no dispatch, no
fault). The remaining question — whether raw boot can enter SPTM guarded state
at all, or storage waits for upstream — is ticket 008's go/no-go.

Ticket 008 go/no-go is now written (`done/2026-07-14-t6040-nvme-sptm-route-finding.md`):
**internal NVMe under raw boot is NO-GO near-term.** M4 HW advertises GXF
(`AIDR_EL1` bit 16), but m1n1 leaves it off (`features_m4` omits `mmu_sprr`), and
even enabling m1n1's M1/M2-style GXF only yields m1n1-owned guarded code, not
Apple's signed SPTM — which is what the controller's TCB/SART/queue mediation is
anchored to. There is no documented loader transition for a third-party boot
object to acquire genuine SPTM state; that becomes the #asahi-dev question
(ticket 010). Daily-driver storage goes through USB-attached root (tickets
009/031/032), which never touches the SPTM-gated internal controller. Do not
spend rig time forcing service-6 GENTER from raw boot.

Exact current transcript: `logs/t6040-console-20260714-nvme-sptm.log`.
Full cumulative analysis: `done/2026-07-13-t6040-nvme-map.md`;
SPTM/GENTER ABI: `done/2026-07-14-t6040-sptm-service6-abi.md`.

## Storage investigation history (superseded by #3 above)
The maintainer approved the exact CoastGuard writes. The retry established two
separate boundaries:

1. A handshake-only SART probe still reset, while a zero-MMIO SART probe booted.
   `patches/t8140-sart-defer-scan.patch` now defers the protected-entry scan
   until the first client has the complete ANS power context. With that fix,
   both the SART-only DT and the full DT with `nvme-apple` unloaded reached
   BusyBox.
2. Loading `nvme-core.ko` succeeded. Loading `nvme-apple.ko` reset the target.
   Yielding phase checkpoints made the exact last successful point
   `before ANS CPU control read`; the fatal operation is the first read of
   `0x209600044`, before any CoastGuard write, SART entry access, or namespace
   command.

Read-only ADT-derived PMGR inspection found that firmware leaves `ANS` at
`0x0f0000ff`: target and actual state `0xf`, with AUTO_ENABLE clear. Linux's
T6041 PMGR probe otherwise enables automatic gating before the NVMe module's
first access. `patches/t6040-pmgr-ans-no-auto.patch` adds an NVMe-only build
exception, and `dts/t6040-j614s-dcuart-nvme-ans-hold.dts` independently selects
the same existing bring-up policy. Both compile; the hypothesis is not yet
live-verified. The last diagnostic reached BusyBox, but its log relay replayed
historical PMGR output and the m1n1 proxy then remained unresponsive after the
documented kisd/re-entry recovery. Stop live work until DebugUSB is healthy.

The recovery helper now makes the fresh kisd PTY raw and attaches its own
reader before DebugUSB traffic. A later recovery confirmed the complete m1n1
startup packet, but proxyclient then timed out while 3.2 KiB of historical
Linux output remained queued. The next reboot stopped after iBoot Stage2, and
then fell through to Apple's "macOS on the selected disk needs to be
reinstalled" screen instead of launching m1n1. The following DebugUSB VDM
failed; live work stopped with kisd detached. This proves only that Apple's
boot chain identified the selected system volume, not that Linux NVMe ran.

Run the recovery helper; it now requires a healthy `Running proxy` and three
unchanged console-size samples before returning. Then boot only the prepared
trace set and relay new `trace:` lines, not the historical PMGR backlog:

- `Image-sart-trace`:
  `0c4880522c4793629f6e9a25ea164c911801e67754ae43cd3a6b5b274e20e8e6`;
- `t6040-j614s-dcuart-nvme-ans-hold.dtb`:
  `cc2c48e30a09080117222d5f4c9fb795dfd6bb338d2cf26b23085ad947ffbefb`;
- `initramfs-dcuart-nvme-ans-hold.cpio.gz`:
  `ae80f82033e5f0d683ac09a3fa61e67c3c63e8a7c1be7593a0fd7fe687732873`.

The exact set was finally booted as Linux #24. `nvme-core.ko` returned zero;
`nvme-apple.ko` watchdog-reset the target. That boot did not have a kmsg relay,
so the absence of trace messages on ttydc does **not** move the fatal boundary
earlier than the prior `before ANS CPU control read` result. For the next
single retry, use the newly built trace-relay initramfs below and add
`EXTRA_BOOTARGS=t6040.trace_relay=1`; it relays only current-boot `trace:` lines
before the shell command is run.

- `initramfs-dcuart-nvme-ans-hold-trace.cpio.gz`:
  `8942b1bd009cd9fe0adeadea3de60d6f068120ae2b8327e0ae1df2c852f40ea5`.

Use the same Image and DTB hashes above. For agent-driven helpers, set
`T6040_KEEPALIVE=1` so kisd and the tty reader survive the automation shell.

That corrected retry is now complete. Its current-boot trace was identical to
the original through `reset work entered`, then stopped at
`before ANS CPU control read`. Therefore preserving ANS firmware state and
skipping AUTO_ENABLE did **not** move the boundary; the ANS auto-gating
hypothesis is disproven. Do not repeat this NVMe module load unchanged.

Next, boot the same trace-relay set but do not load either NVMe module. Capture
the software genpd state first (DEBUG_FS is enabled):

```sh
mount -t debugfs debugfs /sys/kernel/debug
cat /sys/kernel/debug/pm_genpd/pm_genpd_summary \
  | grep -E 'ans|apcie|fab3'
for d in ans apcie_sys_st0 apcie_sys_st1 apcie_phy_sw; do
    echo "--- $d"
    cat "/sys/kernel/debug/pm_genpd/$d/current_state"
done
```

This is read-only software-state attribution. Use it to decide whether a
separately reviewed raw PMGR-state trace is warranted; do not perform another
ANS MMIO read merely to reproduce the same SError.

Captured: the summary and per-domain files report `on` for `ans`,
`apcie_sys_st0`, `apcie_sys_st1`, and `apcie_phy_sw`; the filtered summary also
shows `fab3_soc`, `apcie_st0`, `apcie_st1`, and `apcie_gp` on. Linux therefore
does not believe the storage power chain is off.

The bounded raw-state diagnostic is now built and host-verified.
`patches/t6040-nvme-pmgr-snapshot-debug.patch` is selected only by the boolean
`apple,pmgr-snapshot-stop` in
`dts/t6040-j614s-dcuart-nvme-pmgr-snapshot.dts`. After normal allocation has
attached the declared genpd chain, it follows only those existing DT
`power-domains` phandles, reads each provider's declared scalar `reg` through
its parent PMGR syscon, and returns before `nvme_add_ctrl()`. Reset work cannot
queue, so no ANS, CoastGuard, SART-entry, mailbox, NVMe register, or storage
command is reached. Its diagnostic exit intentionally retains the genpd links
until reboot instead of requesting a cleanup power transition. Do not unload
the diagnostic module; reboot after collecting the trace.

Prepared artifacts:

- `Image-nvme-pmgr-snapshot`:
  `1a056fd855f2d56508e90dc5b9a789d8dc6dcaaf8f7b2284b759756213056541`;
- `t6040-j614s-dcuart-nvme-pmgr-snapshot.dtb`:
  `396d6ad1318764658728b4eb0b67a3961965428031e0aa52b2b59515633a977a`;
- `initramfs-dcuart-nvme-pmgr-snapshot.cpio.gz`:
  `7d44ee376cca2ca0caf44a713b329319b39e502dd29efa41f0b37f1e856be94c`;
- `nvme-core-pmgr-snapshot.ko`:
  `5e61ba16697daa382c5bb614fdaf3d5948a3818c11a630d5766e3b88ead36af7`;
- `nvme-apple-pmgr-snapshot.ko`:
  `21f00d39ad4f8f86df03c403d8d683addc6e4a65c2a8b204e2f7a57adac611f4`.

The single snapshot attempt is complete. Linux #25 reached BusyBox,
`nvme-core.ko` returned zero, and the diagnostic Apple module printed its full
snapshot plus `stopping before ANS MMIO`. The shell then answered two liveness
markers. The four storage values exactly match the earlier m1n1 snapshot:

```text
ans            raw 0x0f0000ff  target f  actual f  auto 0
apcie_phy_sw   raw 0x1400024f  target f  actual 4  auto 1
apcie_sys_st0  raw 0x1000030f  target f  actual 0  auto 1
apcie_sys_st1  raw 0x1000030f  target f  actual 0  auto 1
```

The genpd summary's `on` result was logically correct but incomplete:
`apple_pmgr_ps_is_active()` treats target-active plus AUTO_ENABLE as on even
when the actual state is clock-gated (`4`) or power-gated (`0`). Thus ANS itself
is fully active, while NVMe's other direct domain, `apcie_phy_sw`, is
clock-gated and both of that domain's `apcie_sys_st*` parents are power-gated
immediately before the fatal read.
This is the first evidence-backed new hypothesis since ANS auto-gating was
disproved.

The second diagnostic is now built and host-verified. The runtime-PM put/get
idea cannot work here because the T6041 preservation quirk marks every
firmware-active domain `GENPD_FLAG_ALWAYS_ON`; genpd therefore neither powers
the logical domain off nor re-enters its power-on callback.

`patches/t6040-pmgr-force-active-debug.patch` instead exports a diagnostic-only
helper from the existing PMGR driver. Under the provider's existing IRQ-safe
lock, it reads ACTUAL, skips providers already at `f`, and otherwise calls the
normal `apple_pmgr_ps_set(..., ACTIVE, false)` sequence. This clears automatic
gating, writes the existing PMGR state register, and polls ACTUAL. The Apple
diagnostic recursively follows only its declared DT parents, parents first,
then snapshots before/after and returns before `nvme_add_ctrl()`. On the known
snapshot it will write only `apcie_sys_st0`, `apcie_sys_st1`, and
`apcie_phy_sw`. It cannot queue reset work or access ANS MMIO. As before, do
not unload it; reboot after the trace.

Prepared artifacts:

- `Image-nvme-pmgr-force-active`:
  `3dc2e875b3834750b0211442a411ea96563f0308895cbdee10fddf0fa19bd6e2`;
- `t6040-j614s-dcuart-nvme-pmgr-force-active.dtb`:
  `f0165590215b14062e5082d7cc0d4a5f53723f2500a1f26d49f112a9f8465ce9`;
- `initramfs-dcuart-nvme-pmgr-force-active.cpio.gz`:
  `d5930ba513364acd17ca044fdf320163015c01a17bb8f00d474b0a342e14ce19`;
- `nvme-core-pmgr-force-active.ko`:
  `5e61ba16697daa382c5bb614fdaf3d5948a3818c11a630d5766e3b88ead36af7`;
- `nvme-apple-pmgr-force-active.ko`:
  `d18f2a2a25116d8ba4aaa054431217bd6123cd36b6eae1afbf8a78e0dbc5858d`.

The single force-active attempt is complete. Linux #26 reached BusyBox and all
three expected callbacks succeeded. The verified changes were:

```text
apcie_phy_sw   0x1400024f -> 0x0f0002ff  actual 4 -> f  auto 1 -> 0
apcie_sys_st0  0x1000030f -> 0x0f0003ff  actual 0 -> f  auto 1 -> 0
apcie_sys_st1  0x1000030f -> 0x0f0003ff  actual 0 -> f  auto 1 -> 0
```

ANS and every already-active provider remained unchanged. The diagnostic
printed `PMGR force-active verified; stopping before ANS MMIO`, and the shell
answered both liveness markers. The target was then rebooted rather than
unloading the module and returned to a quiescent m1n1 proxy.

This is the first successful physical-state correction at the fatal boundary.
The third diagnostic is now built. After the same before/after verification,
`patches/t6040-nvme-ans-read-debug.patch` performs exactly one `readl()` of
ANS CPU_CONTROL `0x209600044`, logs its returned value, and immediately exits
through the no-detach path. It does not queue reset work or write CPU_CONTROL.
The DT contains only `apple,pmgr-force-active-read-stop`; neither earlier stop
property is present. Strict checkpatch, full kernel/module link, patch reversal,
DT inspection, marker inspection, and initramfs module comparison all pass.

Prepared artifacts:

- `Image-nvme-ans-read`:
  `47514760a0ca729e7f46c5c71d8cbd403d205a55ee0bdbff59f7f8cdce47cbcc`;
- `t6040-j614s-dcuart-nvme-ans-read.dtb`:
  `01c7511d71d6072e23a72ddac0cbd10795587e830e99f77df988f9d998a2761d`;
- `initramfs-dcuart-nvme-ans-read.cpio.gz`:
  `3c1cfe3dddcbd02b8a4c0ee5eaaecf147627ee5fde17b8ae4250749de65b9c44`;
- `nvme-core-ans-read.ko`:
  `5e61ba16697daa382c5bb614fdaf3d5948a3818c11a630d5766e3b88ead36af7`;
- `nvme-apple-ans-read.ko`:
  `0562b9e66424f2727efd9a4eac9502b7c8c9dd82606e081214d70ffc92b5ac8a`.

Run this once with the current-boot relay. A successful read justifies a later
force-active controller-boot attempt; another reset disproves the
parent-gating hypothesis. Never mount, repair, format, flush, or write the
namespace. Prior exact output:
`logs/t6040-console-20260713-nvme-pmgr-force-active.log`.

## Parked (revisit after pmgr)
- USB gadget console → gadget-Ethernet + SSH (EP0 dies post-enumeration;
  `done/2026-07-11-t6040-usb-gadget-plan.md`).
- cpufreq throttle offsets (t6030 offsets SError on t6040 P-clusters; needs RE
  or #asahi-dev answer).
- ATC PHY tunables (USB3/TB) — blocked on t6040 PHY reg-bucket offsets;
  USB2-only fallback is fine for now.
