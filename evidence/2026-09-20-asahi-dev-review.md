# Asahi development catch-up: implications for Wallace / T6040

Reviewed 2026-09-20 by Astra. Scope: Linux hardware enablement for J614s,
MacBook Pro 14-inch M4 Pro. This is an offline assessment and proposed work
order, not a new hardware validation or a replacement for NEXT_STEPS.md.

## Recommendation

Prioritize a narrowly scoped NVMe IOQ-size correction and an upstream idle/WFxT
baseline audit. Finish the existing SD-root/trackpad integration and corrected
right-port USB test alongside that work. Keep the SD-first removable boot design.
Do not spend the next cycle porting Thunderbolt, transplanting M3 display/GPU
support, changing distributions, or redoing already-completed artifact reviews.

The strongest new finding is unusually concrete: the September NVMe investigation
matches Wallace's failure signature exactly, and our local Linux and working
m1n1 code contain the precise register-value discrepancy that the revised
upstream candidate fixes. This reopens a specific *hardware queue-size contract*,
not the previously rejected generic queue-depth/concurrency hypothesis.

## Sources and limits

Read in full: AGENTS.md, COORDINATION.md, NEXT_STEPS.md, ROADMAP.md, DEVLOG.md
(including Corrections and dead ends). Also checked relevant tickets, the earlier
NVMe evidence chain, SPMI_SAFETY.md, and local kernel/m1n1 source.

Reviewed every textual chat entry in all 33 supplied HTML files: **2,772 messages
and 11 action/attachment entries**, August 19–September 20. August 18 is absent.
September 20 is a partial day (capture clock 19:01 UTC; last chat 18:56 UTC).
Matrix attachments and expanded messages behind links are not all embedded in
these files; this is not a claim to have reviewed every linked image, paste, or
external codebase. Joins/quits and social discussion carry no implementation lead.
The [source manifest](2026-09-20-asahi-dev-review/sources.json) records counts and
SHA-256 hashes. Readable working transcripts are in `.tmp/irc-review/`.

IRC links below identify original message IDs; their supplied local HTML copies
are the evidence for the historical statements. Supplementary public source
checks were made on September 20. A report of working hardware, a submitted
series, a maintainer branch, linux-next, and a released mainline kernel are
separate milestones.

Local source anchors at review:

- Linux HEAD `4f2429104009e3964ddcc326d8490ac25bfb1a5c`.
- m1n1 HEAD `80badc91e62c8b4228a857730f160ffb62a29335`.
- These identify inspected checkouts, **not the hashes of any booted Image**.
- No rig operations, image builds, enrollment, patch application, external
  messages, or ticket allocation were performed for this review.

CJ confirmed on September 20 that no firmware, enrolled-loader, or SD-fixture
changes occurred since August 19. Use that unchanged baseline for the proposed
comparisons. This does not resolve contradictions between older tickets and
later August 19 records: identify the actual pinned artifacts and latest evidence
before a live run, without assuming a new enrollment or filesystem repair is needed.

## 1. NVMe: promote IOQ size semantics to the first investigation

### What changed

On August 29–30, Ivaylo and Yuka reported that changing MAX_PENDS from 64 to 63
avoided newer-controller failures. That alone was weak evidence. Sven correctly
questioned whether it merely hid another bug.

The August 31 discussion then corrected itself twice: an apparent macOS trace
with value 63 was actually **m1n1 running under m1n1**; macOS wrote `0x400040`.
Simply reducing the driver's overall queue depth moved the error rather than
solving it. Those intermediate statements must not become project facts.
[August 31 investigation](https://oftc.catirclogs.org/asahi-dev/2026-08-31#35649541)

On September 6, Yuka isolated the distinction: on M4 the queue-create command's
`qsize` was ignored; offset `0x1210` determined the I/O queue sizes. M3 Max still
respected `qsize` with both 14.x and 27.x firmware. The old register name obscured
a generational change in meaning.
[September 6 result](https://oftc.catirclogs.org/asahi-dev/2026-09-06#35666515)

The revised [Yuka commit 42839287](https://cyberchaos.dev/yuka/linux/-/commit/42839287f85c8c36b63579371af533fcd1b8c970)
explicitly implements this: older hardware retains MAX_PEND programming; the
T8132 variant registers CQ/SQ bases and writes `(depth - 1)` into both halves of
`APPLE_ANS_T8132_IOQ_SIZE`. I retrieved its full commit/diff through the GitLab
API; a [snapshot is preserved](2026-09-20-asahi-dev-review/42839287f85c8c36b63579371af533fcd1b8c970.json).
The publicly readable `nvme-7.3` driver also contains the new register semantics.

### Why this is directly relevant

| Observation | Wallace | September investigation |
|---|---|---|
| Firmware assertion | `[7454]`, CQ Host I/O DB error | Same |
| Eager-completion crash fields | head 63, status/valid `0x4`, error `0x1 / 0x20000` | Same fields on August 31 |
| Host queue allocation/wrap | 64 entries | 64 entries in failing case |
| Local Linux write to `0x1210` | `64 | (64 << 16)` | New semantics imply 65 entries |
| Working local m1n1 write | `63 | (63 << 16)` | New semantics imply 64 entries |

Local references: `../linux/drivers/nvme/host/apple.c:1163`,
`../m1n1/src/nvme.c:414`, and
[Wallace E1–E5 evidence](2026-07-30-t6040-nvme-linux-wrap-assert-E1-E5.md).

**Inference:** a firmware/host ring-size disagreement is a compelling explanation
of Wallace's first-wrap assertion. It is not yet a demonstrated T6040 fix. The
old exclusion compared allocations, software wrap logic and create-CQ `qsize`;
it did not prove which input this firmware actually used. That evidence even
left firmware-derived ring size as an open possibility. Shrinking depth while
preserving the off-by-one relationship would naturally move the crash boundary.

### Integration proposal

1. Audit the exact known-failing Image's source/config/patch manifest against
   `42839287`, including actual DT resource translation, selected compatible,
   IOQ registration order, and the value written to `0x1210`.
2. Prepare a minimal T6040-applicable patch through Wallace `patches/` and kbuild.
   Keep allocations, tags, CQ wrap, workload, IRQ mode, and firmware constant.
   Follow the revised queue-registration contract; do not globally subtract one
   for older controllers or just reduce `max_queue_depth`.
3. Include the modern crashlog decoder so any recurrence reports firmware queue
   sizes. Inspect already-captured logs first; avoid spending a boot solely to
   reproduce an unchanged known failure when existing evidence suffices.
4. Two clean builds, normal preflight and exact review; then a separately ready
   read-only test at `maxcpus=1`, initially with storage-free userspace if feasible.
   Prove repeated wraps with sustained, counted reads and repeatable hashes,
   rather than treating GPT enumeration or a short mount as success.
5. Only after read stability, return to ticket 211's separately bounded write
   soak on the **label-and-GPT-type-verified exFAT `linux` partition**. Do not
   hardcode p3/p4 from old notes: they disagree. Resolve the actual partition
   identity before writes; never raw-write the namespace or APFS.

Move threaded-IRQ tickets 203/210 behind this discriminator. Keep them as fallback
if the size contract is verified correct and the assertion persists. Preserve
201's decoder work and 195's admin-traffic hypothesis; neither needs deletion.

The September 6 observation that `reg[9]` can serve all NVMe accesses also makes
the old split-window implementation worth comparing offline. It does **not**
justify reviving the already-refuted blind doorbell-window move. Keep this
cleanup separate from the queue-size experiment.

The macOS 15+ NVMe changes also include dropping obsolete PRP-null handling and
requiring page-aligned admin buffers. September 16 warns against cherry-picking
the former without the latter. Audit the full dependency set rather than copying
one apparently helpful register edit into a newer base.
[Admin-buffer dependency](https://oftc.catirclogs.org/asahi-dev/2026-09-16#35702411)

On September 17–20 the M4 driver/bindings were reported queued in `nvme-7.3`,
but not yet flowing through block into linux-next. M3 NVMe/PCIe/SMC DT work was
waiting on that dependency. Do not infer availability from a branch's version
number or an IRC statement that something is upstream.
[Queue/dependency status](https://oftc.catirclogs.org/asahi-dev/2026-09-19#35712182)

## 2. SMP, idle and firmware: a better baseline, not a claimed fix

Yuka recommends `idle=nop arm64.nowfxt` for M4 booting on August 28. On September
18 the WFxT override was reported applied, expected in linux-next the following
week. The [submitted patch](https://lists.openwall.net/linux-kernel/2026/08/11/2453)
adds an early feature override; merely appending the parameter to an old kernel
that does not implement it does nothing useful.
[Applied report](https://oftc.catirclogs.org/asahi-dev/2026-09-18#35708757)

Wallace has a local `idle=nop` implementation. Source inspection also shows an
important qualification: its `arch/arm64/lib/delay.c` already skips **WFIT** when
`idle=nop`, but still enters **WFET** loops when WFxT is advertised. The inspected
`idreg-override.c` lacks the new `arm64.nowfxt` alias. Thus the recommended upstream
baseline differs from ours, but it is incorrect to say our kernel simply forgot
to guard WFIT. Audit emitted code and effective CPU capabilities as well as strings.

Proposed next step for 205/217/209: compare equivalent idle implementations and
introduce the supported WFxT disable in an isolated storage-free candidate. Use
the same uninstrumented reproducer, topology and firmware, with fresh boots and
at least four repetitions per variant; retain one-core controls and CPU-tagged
oops evidence. If it passes, expand to mixed-cluster and all-core load before
changing the daily profile. Keep `copy_highpage` perturbations out.

The official [August progress report](https://asahilinux.org/2026/08/progress-report-7-2/)
claims an early multicore crash was fixed in M4/M5 work. It does not identify
Wallace's COW failure or prove the same mechanism. Yuka's public experimental
WFI branches concern state loss; those are useful comparison material, not
additional patches to pile onto the candidate. No explicit diagnosis of
Wallace's page-lifetime/TLB hypothesis appears in this log set.

M5 Pro/Max's inability to start secondary CPUs in raw boot mode is a **different
failure**. The apparent August 27 success was later identified as base M5, not
T6050. Wallace already starts all fourteen T6040 cores. Do not use that discussion
as evidence that a macOS update cures ticket 205.
[Correction to M5 claim](https://oftc.catirclogs.org/asahi-dev/2026-08-27#35639437)

Sven brought up all M4 Pro secondaries on August 28 using the then-current
26.6.x environment. His later machine inventory identifies an M4 Pro **Mac mini**,
not our J614s laptop. Useful same-SoC comparison, not board equivalence.
[Same-SoC observation](https://oftc.catirclogs.org/asahi-dev/2026-08-28#35641717)

Record OS firmware, system firmware/mBoot, ADT hash, m1n1 and kernel together.
Avoid an OS/firmware upgrade as the first experiment: it changes several variables
and firmware ABIs at once.

## 3. USB/SPMI: finish the bounded USB2 path; inspect upstream transport changes

The logs distinguish working M3 ACE3/SPMI support from the newer M4 Pro PHY and
SPMI-interface work. On August 29 the newer IRQ-register interface was still an
explicit investigation topic. Reports of USB working on another generation do
not establish that J614s VBUS or IRQ delivery is solved.

The immediate Wallace step remains attended ticket 305 with the translated
`0x509198000` DTB. **3009 already passed** in `tickets/done/`, with DTB hash
`eaf8cceb8c22d19f71ea0175397a96bd41ff6ebf56ab0719da7da0272f068acf`;
305 records `runnable:true`. NEXT_STEPS still saying it waits for 3009 is stale.
Readiness still requires checking the current fixture and pinned files before
operation. Do not substitute the superseded raw-address DTB.

Compare current upstream SPMI/tipd changes offline for transport paging, error
returns, IRQ register layout, clear/mask semantics, locking and detach behavior.
The September 20 discussion endorses m1n1
[PR 636](https://github.com/AsahiLinux/m1n1/pull/636), which factors out HPM iteration.
The retrieved PR snapshot is still open; an approval conversation is not a merge.
More importantly, Wallace forbids generic HPM iteration: adoption requires
preserving exact endpoint selection, not silently enabling every controller.

Run success must mean a real passive USB device enumerates, survives detach/replug,
and progresses through the existing read-only then bounded-write fixtures.
Root hubs alone are not USB storage support. If 305 only achieves sane PD status,
record partial success and investigate that boundary; do not add arbitrary
role-swap commands.

Local policy needs reconciliation before future artifact composition:
AGENTS/NEXT_STEPS summarize hpm2 as the only endpoint, while SPMI_SAFETY Entry 2
and 305 record an August 19 bounded abbey NVMEM exception. Preserve the narrower
current user instruction for new work; do not infer fresh PMU permissions from
this review. A stale safety summary and a specific approved artifact are not
interchangeable. No new access scope is proposed here.

## 4. Boot/U-Boot: retain SD-first, test the proxy-to-host boundary explicitly

September 2–11 U-Boot reports first blamed missing compatibles, then distinguished
base M3 from Pro/Max/SPMI machines, and found additional attach/replug behavior.
The `asahi-v2026.07-1` tag adds M3 USB support, but reports after it still had root
hubs without storage devices on some configurations. Backdoor proxy/device mode
can alter the outcome.
[Proxy caveat](https://oftc.catirclogs.org/asahi-dev/2026-09-05#35662622)
[Later unresolved differences](https://oftc.catirclogs.org/asahi-dev/2026-09-11#35680279)

This supports Wallace's SD-first choice. Keep 3012–3020, the single owner of PCIe
PHY/link initialization, watchdog coverage and one-shot RAM proxy fallback.
For eventual 3018 USB boot, explicitly test cold boot with media present, boot
after a DTR proxy window, attach after U-Boot starts, detach/replug, both cable
orientations, and return to the rollback proxy. Neither Linux USB success nor
M3 U-Boot support proves T6040 U-Boot support.

The August 29 bootargs discussion confirms `/chosen/bootargs` as the kernel
handoff mechanism (subject to forced kernel cmdline settings). Make ticket 3020
verify the final effective cmdline through the *actual* U-Boot handoff, including
`maxcpus=1`, required idle flags, console ordering and Norwegian layouts. Do not
assume an m1n1 argument survives another bootloader's replacement of bootargs.

PSCI through UEFI runtime services is a promising longer-term path for upstream
CPU power management. It requires coordinated resident m1n1 memory reservations,
U-Boot/EFI and kernel support. Preserve architectural room for this, but do not
redesign the immediate direct-`booti` milestone around an RFC. A direct boot path
cannot be assumed to exercise an EFI-runtime conduit.

## 5. WiFi/Bluetooth: reduce the downstream patch burden after baseline recovery

The September 20 WiFi result is concrete: BCM4388 RX buffers need bidirectional
DMA mapping because firmware also reads them. IntegralPilot reports association
working and requests tests outside T8122.
[Result and pre-review link](https://oftc.catirclogs.org/asahi-dev/2026-09-20#35712739)

I retrieved [IntegralPilot/linux PR 1](https://github.com/IntegralPilot/linux/pull/1)
and its diff at head `73eedf272d6f74b261dcd179e13d7ff1c407e2d5`. The diff contains the
BCM4388-specific DMA_BIDIRECTIONAL selection. The PR body specifies basic 5 GHz
WPA2-PSK tested on T8122; it is open, not merged. Its evolving split already differs
from the 15/20-commit counts in IRC: the retrieved body describes 23 commits,
including an independently submitted authenticated-event fix. Pin commits, not
conversation counts. [PR metadata snapshot](2026-09-20-asahi-dev-review/wifi-pr.json).

Wallace already has working BCM4388 association/DHCP/traffic. Compare this series
against the existing downstream stack, especially RX mapping, firmware selection,
BSS-info v116, authentication events, rev-6/c2-under-c0 naming and antenna SKU X3.
Do not stack duplicated brcmfmac changes. Regression checks should cover association,
reassociation, sustained bidirectional traffic, idle-to-active recovery and BT
coexistence. Use the working local stack until a replacement passes.

August 20's Broadcom channel-priority/coexistence discussion matters for real BT
audio plus 2.4 GHz WiFi. The BCM4378 advertisement quirk is a different chip and
should not be copied blindly. September 1–2's AMKOR firmware extraction fix
(installer PR 439) illustrates why a generic family match is insufficient; audit
our paired BT firmware mapping, but do not rename a currently working J614s blob
because a T6031 needed a different supplier suffix.

## 6. Trackpad: integrate our proven result, follow DockChannel upstreaming

DockChannel HID v2 was sent September 18; v3 and another revision were discussed
rapidly afterward. This is progress in getting the input stack upstream, not a
new report that Wallace's trackpad is broken or fixed.
[Submission](https://oftc.catirclogs.org/asahi-dev/2026-09-18#35708112)

Complete ticket 301: paired approved HIDF blob, the proven nine-byte v2 two-phase
power-request exchange, touch and haptics in the normal daily image. Compare the
latest reviewed DockChannel series for reset/power/open/close and transport changes
before replacing the local patch. The series revision number “v2” is unrelated
to the firmware message's version-2 format. Preserve touch/haptic regression tests
and Norwegian keyboard behavior. Keyboard-layout cleanup was still recruiting
contributors; it does not supply a Norwegian-layout replacement.

## 7. Display, GPU and video: useful progress with strict generation boundaries

M3 DCP progressed materially: T6030 internal display, then backlight after adding
the missing panel node on September 9, and T8122 testing on September 19. The
latter exposed XRGB's unused byte being interpreted as opacity; ARGB/KWin worked
while a console stayed black. `appledrm.show_notch` changed the symptom. That
is valuable future debugging knowledge, not a recommended T6040 boot argument.
[Panel fix](https://oftc.catirclogs.org/asahi-dev/2026-09-09#35674693)
[XRGB finding](https://oftc.catirclogs.org/asahi-dev/2026-09-19#35710288)

Results varied by SoC: T6031/T6034 had early endpoint/startup failures on September
16, and external-display modesets remained problematic on T8122 September 19.
PRs 607/608 are references, not a generally working M3 recipe and certainly not
T6040 support. Relevant contracts include firmware ABI, the board panel node,
carveouts/segment-ranges, firmware-compat propagation, DART mappings, DCP versus
PIODMA address spaces, and physical display-controller resources. Derive each
from our board; do not copy T602x addresses or assume RTKit startup proves DCP.

DCP is independent of GPU rendering and may eventually provide brightness,
better cursor behavior and lower display power with software rendering. Prepare
an offline J614s DCP/firmware-gap inventory as roadmap D/G work, but keep simpledrm
as the working fallback. No matching 26.x T6040 DCP contract is established here.

No maintainer-endorsed complete G16/T6040 kernel+firmware+m1n1+Mesa stack appears
in these logs. September 16 explicitly disputes a third-party M4 GPU claim.
That does not prove the claim technically impossible; it supplies no acceptable
basis to mark Wallace GPU ready. Keep roadmap F and its existing smoke gate.

AVD v1 reached linux-media September 18. Earlier work covered H.264/H.265/VP9,
M3 AV1, firmware packaging, interchange layouts and VA-API/V4L2 userspace. Color
artifacts sometimes came from downstream presentation/conversion: dmabuf-wayland
or OpenGL changed them, so decoder output and renderer output need separate tests.
Interchange metadata/plane-offset corrections matter only with a matching stack.
Track AVD as its own future capability; video decode is neither GPU acceleration
nor camera/ISP support, and AVE encoding remains a separate unsupported track.
[AVD submission](https://oftc.catirclogs.org/asahi-dev/2026-09-18#35708406)

## 8. Thunderbolt, DART and suspend: future functionality, not a VBUS shortcut

The August 19–September 19 work brings XDomain networking and USB3-over-USB4
through a substantial series. DART apertures, additional streams, coherent DMA,
remapping and deferred flushes materially affected throughput. One experiment
was corrected after comparing the wrong kernels. Adopt architectural lessons,
not benchmark numbers as T6040 expectations.

PCIe tunneling reappeared experimentally on September 1; it was not thereby a
finished hotplug implementation. DP tunneling still needed separate work. Long
hub chains/unplug exposed object-lifetime problems. Suspend caused DART SErrors;
blocking suspend while ACIO was active and adding proper ATCPHY PM handling were
part of the discussion. USB wake sources and SMC wake integration remained open.
[PM failure](https://oftc.catirclogs.org/asahi-dev/2026-08-25#35630515)

For Wallace, high-speed Type-C requires the **M4 Pro PHY**, PD/SPMI/interrupt
handling, ACIO reset/mailbox, DART, and host stack to agree. M3-compatible bindings
and USB4net success are not that contract. Avoid DART deferred-flush/performance
experiments while diagnosing unrelated CPU-MM faults; DART IOTLB and CPU TLB
behavior are different domains. Future USB4 work must include hotplug and suspend
boundaries, not merely successful enumeration.

## 9. Audio, camera and power: keep the dependencies visible

M3 audio made real progress, including fixes for missing J615 woofers and a wrong
headphone IRQ DT entry. The original speaker-count inference was corrected in
conversation. Use this as a warning against board aliases by chassis appearance:
J614s needs its own topology and tuning evidence. Speaker enumeration alone is
insufficient; safety-daemon IV sense and calibrated routing matter. Shared GPIO
support and a prepared macaudio upstream branch reduce future downstream burden.
Audio DT dependencies include I2C, MCA/I2S, ADMAC, NCO and its clock reference.
[DT dependency discussion](https://oftc.catirclogs.org/asahi-dev/2026-09-19#35711483)

PMP v1 work targets earlier hardware and is not T6040 power management by analogy.
M3 PMP and DCP observations can guide architecture review. Use existing SMC
telemetry to measure actual idle/load power, clocks and temperatures once the
baseline is restored. `idle=nop` remains a bring-up workaround; sustained
performance and battery behavior belong in daily-driver acceptance.

M3 camera/microphone progress does not close J614s camera or AOP support. No
reviewable T6040 camera/audio/suspend solution emerges from this log set.
Coil-whine/headphone-noise anecdotes and per-model microphone gain changes should
remain model-specific observations, not guessed fixes for Wallace.

## 10. Upstream strategy and maintainability

The logs clarify that DT submissions need not follow strict product release
order: send ready basic support. On September 4 Yuka specifically withheld
T604x DT submission because PMGR was not sufficiently understood. Wallace's
working PMGR description is consequently useful comparison material, but local
boot success does not establish upstream-quality domain correctness.
[PMGR blocker](https://oftc.catirclogs.org/asahi-dev/2026-09-04#35659527)

Plan an offline DT/PMGR diff against Yuka, including parent relationships and
translated address spaces, plus schema/style checks. Prefer subsystem-sized
changes and retain proof for each hardware block. Later upstream-facing work
must use the appropriate dependency tree; Jannau's strict-style cleanup creates
mechanical conflicts that should not be mistaken for hardware changes.

The logs repeatedly state Asahi's contribution/provenance restrictions. For our
mainline goal, that is a practical integration constraint: this agent-produced
report and existing binary-analysis-derived work must not be represented as
acceptable clean-room upstream contributions. The project's local-use progress
and externally acceptable patch provenance need separate accounting. Retain
origin and review history per patch; favor independently published upstream
implementations when retiring local experiments. Check the current
[Asahi contribution policy](https://asahilinux.org/llm-policy/) and
[copyright guidance](https://asahilinux.org/copyright/) before any future submission.
No external reporting is proposed now; CJ's upstream-posting deferral remains.

The hypervisor/SPTM-emulation work is a future enabler for hardware traces. The
August 28 conversation explicitly distinguishes a working M1 demonstration from
M4 porting still in progress. The qemu-sptm discussion later corrects an initial
claim about HV.framework: it uses TCG. Neither provides evidence of a usable
T6040 hardware-tracing environment. Do not reopen “Linux needs resident SPTM”;
Wallace's own NVMe reads already refute that.

## Proposed execution order and acceptance gates

| Order | Work | Existing track | Gate to move forward |
|---|---|---|---|
| 0 | Reconcile ticket/doc drift and pin firmware + baseline manifests | coordination | Know the actual enrolled object, fixture state and booted Image; no guessed status |
| 1 | Minimal IOQ-size candidate and dependency audit | 201/206, then 211 | Repeated read-only wraps/hash checks before any bounded NVMe write test |
| 1 | Standard idle/WFxT comparison | 205/217/209 | Fresh-boot repeated COW tests, then cluster/all-core stress; one-core daily until passed |
| 1 | Finish clean SD root and normal trackpad image | 215/216/301 | Real fsck if needed, normal desktop/network/input, clean shutdown and postchecks |
| 1 | Resume corrected attended USB2/PD fixture | 305, then 109+ | Real child + detach/replug, then separately gated file read/write persistence |
| 2 | Complete SD-stage2 bundle/proxy fallback | 3012–3020 | Reproducible bundle, preserved bootargs, exact media identity, read-only first light |
| 2 | Replace overlapping WiFi/input patches with reviewed equivalents | WiFi/301 | Existing J614s capabilities preserved through normal workload regressions |
| 3 | Inventory DCP/backlight and power-management gaps | D/G | Matching firmware and board contracts before live candidates |
| 4 | USB3/USB4, audio, camera, AVD and GPU | F/G | Actual T6040-specific support; do not infer from M3 or a demonstration elsewhere |

The order-1 lanes can progress independently offline. Live experiments still
serialize through the lease and exact-artifact gates. This does not ask for
subagents or allocate tickets under another agent's number block: Astra currently
has no allocation block in COORDINATION.md. Resolve that before new ticket adds.

### Documentation corrections to make when adopting this plan

- NEXT_STEPS §3: put the specific new IOQ-size evidence before IRQ threading;
  DEVLOG's dead end should remain for generic depth/concurrency changes, with an
  explicit exception for this newly evidenced register-semantic mismatch.
- NEXT_STEPS §6: 3009 is done; 305 is recorded ready for its attended fixture.
- NEXT_STEPS §2: 213/214 are already done; distinguish service implementation
  from acceptance on a repaired persistent root.
- Ticket 215 still records a missing rollback-proxy enrollment gate, while later
  work describes resumed rig access. Confirm current enrollment instead of
  assuming either stale record is live truth.
- Reconcile the summary and detailed SPMI policy scopes before new composition.
- ROADMAP completion criteria should separately track the six requested I/O/input
  capabilities, stable multicore, daily usability/power, and upstream inclusion.
  The present milestone text omits some explicit USB/NVMe requirements and calls
  the result “mainline” while Wallace still needs downstream patches.

A practical locally patched daily driver and an unmodified-mainline-supported
machine are distinct acceptance milestones. Improve the former immediately while
reducing the patch delta through the latter's actual merged dependencies. The
logs justify changing our investigation order; they do not justify marking any
unrun J614s capability complete.
