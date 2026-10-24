# Asahi development review, 21 September–24 October 2026

Internal Wallace engineering research; Astra, 2026-10-24. This is Apple Silicon Linux hardware enablement.

## Scope and evidence

Read all 4,008 talk messages in 34 consecutive daily HTML snapshots in `tmp/logs/`, including follow-ups and corrections. The October 24 file ends at 16:00 UTC; this is not a claim to cover the rest of that day. Joins/quits were excluded. Source hashes and message counts are in `2026-10-24-asahi-dev-review-sources.json`; a numbered transcription is in `2026-10-24-asahi-dev-review-messages.txt`. References below give date and original message ID, which are searchable in that transcription and anchor the original HTML.

Compared against AGENTS, COORDINATION, NEXT_STEPS, ROADMAP, DEVLOG (including corrections/dead ends), and the September review/candidate evidence. NEXT_STEPS remains the authority for locally demonstrated capability. No rig access, build, enrollment, partition writes, or external communications were performed. This review does not promote outside reports to Wallace test results.

Live GitHub checks confirmed the merge dates of m1n1 PRs 688, 689, 695, 698, 719 and 732. Lore and cyberchaos pages could not be retrieved through the web tool; their submission/branch status below is attributed to the logs, not independently asserted as merged. Follow those links before importing code and pin immutable revisions.

## Assessment

There is substantial directly relevant progress: another J614s has reported working Linux NVMe, M4 Pro/Max device trees have been submitted, a working older dockchannel-HID branch provides a comparison target, and M4 Pro macOS hardware tracing is now practical at the login screen. These make it more attractive to converge on shared support instead of extending isolated local workarounds.

There is no demonstrated resolution in this corpus of Wallace's runtime MM/COW fault 205, no M4 Pro ATCPHY/Thunderbolt 5 driver completion, and no validated T6040 accelerated GPU, panel brightness, audio, camera, or suspend solution. Our `maxcpus=1` daily baseline and write restrictions remain justified.

## Findings and integration decisions

### 1. NVMe: independent same-board success; retain the controlled experiment

On October 5 Hel3zi booted the 14-inch M4 Pro/J614s with Yuka's kernel, then reported visible namespaces/partitions and a clean benchmark after building RTKit, NVME_APPLE and SART into the kernel (#35757647; follow-up #35757660). Earlier absence of devices was a missing-module problem, not evidence that hardware initialization failed (#35757107). Framebuffer and keyboard backlight also worked (#35757033).

This is strong corroboration that Linux storage on our exact model is attainable. However, the setup used modified m1n1 with DAPF and PCIe initialization bypasses and an HV boot. The pasted benchmark report does not establish write durability, repeated cold boots, or equivalence to Wallace's direct boot. Do not inherit those broad bypasses.

A separate upstream regression was bisected on October 3: `c20bba234f3e` (do not reset controllers in NVME_CTRL_NEW state) broke nvme-apple namespace appearance (#35751229–35751247). Yuka's earlier October 2 suspicion about inert reg9/NVMMU accesses was superseded by the linux-next-only finding (#35751102 onward). This is distinct from our first-CQ-wrap assertion. [Regression thread](https://lore.kernel.org/all/94912d46-381d-4988-800a-6ef3b595233f@cyberchaos.dev/T/).

Recommendation: keep ticket 6001, the prepared RAM-only, one-CPU, read-only queue-size test, first. The new logs do not invalidate its hypothesis or justify combining it with a rebase. Afterwards compare the complete driver, SART and power-domain DT against Yuka's successful setup and [parts/21-dt-nvme](https://cyberchaos.dev/yuka/linux/-/commits/parts/21-dt-nvme). Preserve the proven two-base local mapping until a separately reviewed migration explains the replacement. Test namespace enumeration and repeated reads across many queue wraps; a controller node alone is insufficient. Writes remain a later gate, confined to label-and-GPT-verified exFAT `linux`.

M5 is a separate thread: October 7 assertions that reset was impossible were not established facts. Yuka had already demonstrated m1n1 init/shutdown/reinit (#35764737, #35764779). On October 18 T6050 NVMe worked after power-domain dependency corrections involving `ps_aphy_st{0,1}_aus5` (#35799012–35799031), and SART4 was submitted (#35799087). These are useful comparative evidence, not T6040 register recipes.

### 2. M4 Pro/Max DT submission is a convergence opportunity

Preliminary M4 DT appeared September 29 ([commit 4d473281](https://cyberchaos.dev/yuka/linux/-/commit/4d4732812bae3bf93bc5aa79c3dda557fd4426d0), #35738223); M4 Pro/Max device trees were reported submitted October 10 (#35776570). On October 15 Sven expected to pick them up after the next -rc1 (#35790096): submission is not proof of mainline inclusion. [Organized DT branch](https://cyberchaos.dev/yuka/linux/-/commits/parts/04-dt-more).

Board differences matter. M4 Pro Mac mini uses dispext0/1/2 without internal disp0, whereas MacBooks use disp0 plus dispext0/1; remove dispext2 on the MacBook, not disp0 (#35771066–35771151, October 8). Template IPSW ADTs can retain nodes removed by iBoot from a live board's ADT. Earlier uncertainty over which domains to delete must not become a shared-SoC deletion that breaks laptops. Use our live J614s ADT as the authority.

Recommendation: produce a property-by-property DT comparison: compatibles, interrupt routing, power-domain graph, SART/NVMe, PCIe, SMC, dockchannel and reserved GPIOs. Separate upstream-accepted definitions, pending definitions and Wallace-only differences. Retain SD, input and endpoint-power details that already work locally. Run schema checks on a separately built candidate before any baseline replacement.

### 3. Input: working reference, but the new upstream form initially failed

Dockchannel-HID v4 was sent September 25: [series](https://lore.kernel.org/asahi/20260925-apple-mtp-keyboard-final-v4-0-304c267518f4@gmail.com). On October 8 Yuka found that the new DT did not wake the M4 Pro coprocessor (#35771198–35771205), then rebased the older working implementation (#35771235 onward): [t604x-old-dchid-working](https://cyberchaos.dev/yuka/linux/-/commits/t604x-old-dchid-working). The t604x-prefixed commits were specifically identified as reusable with asahi-wip (#35771372). On October 15 jannau also cleaned up downstream dockchannel workqueue behavior (#35791588–35791591).

Our touch and haptics are already demonstrated (230); daily-image integration (301) remains useful work. Compare these references before replacing working local input. A new submission is not automatically a better tested J614s combination. Suggestions in IRC to toggle additional SMC GPIOs are not authorized exceptions to Wallace's endpoint rules.

### 4. USB: base M4 success does not solve M4 Pro/TB5

October 7 explicitly distinguished base M4's working USB path from M4 Pro's different ATCPHY and coprocessor (#35766990 onward). On October 23 Yuka still used `t8122,atcphy` successfully on base M4; its DT patches awaited SPMI/ATCPHY bindings, while Sven had begun M4 Pro tracing (#35818006–35818062). [Base-M4 USB DT reference](https://cyberchaos.dev/yuka/linux/-/commits/parts/51-dt-usb). ACE3/SPMI resubmission was planned after the merge window; ATCPHY submission awaited DP confirmation.

Recommendation: continue our narrow right-port USB2/VBUS work, including the corrected translated hpm2 address from ticket 3008 and the exact SPMI safety envelope. It is complementary to upstream high-speed work. Do not assume base-M4 third-port IRQ fixes or an M3 PHY compatible enable T6040 USB3/TB5. Track the new M4 Pro trace work before duplicating that reverse engineering.

### 5. m1n1 tracing is the largest new investigation capability

The September 26–27 M4 Pro macOS GUI progress developed into an upstream SPTM/emulation stack. Confirmed merged:

| PR | Change | Merge date |
|---|---|---|
| [688](https://github.com/AsahiLinux/m1n1/pull/688) | CTRR/CTXR register definitions | Sep 30 |
| [689](https://github.com/AsahiLinux/m1n1/pull/689) | Fix inverted WFI boot-argument condition | Sep 30 |
| [695](https://github.com/AsahiLinux/m1n1/pull/695) | SPTM initialization/sysreg virtualization | Oct 11 |
| [698](https://github.com/AsahiLinux/m1n1/pull/698) | SPTM/TXM support; M4 additionally needs emulation work | Oct 15 |
| [719](https://github.com/AsahiLinux/m1n1/pull/719) | Repair chainload after MachO.prepare_image signature change | Oct 16 |
| [732](https://github.com/AsahiLinux/m1n1/pull/732) | Hide unexplained AMCC interrupts from guest | Oct 19 |

On October 17 allocating stolen memory at the end of RAM removed the last bespoke SPTM binary patch (#35796504). October 18 gives the SPTM/TXM/kernelcache workflow and clarifies inputs are extracted Mach-O files, not wrapped IMG4 (#35799086–35799185). [HV documentation update](https://github.com/AsahiLinux/docs/pull/284).

Limitations are material: the AMCC workaround suppresses a symptom whose cause remains unknown; it is not a cache-correctness fix. October 23 M4 Pro still hung immediately after login, while login-screen tracing was considered sufficient for ATCPHY, DAPF and even GPU (#35817915–35818027). The earlier speculation about indefinite post-login uptime was superseded by these failures.

Recommendation: prepare a separate, pinned tracing environment when tracing becomes the next task. Keep the September NVMe payload and known-good DebugUSB path intact. Review the full dependency stack, host proxyclient/target pairing, WFI handling and chainload repair together. DAPF crashes on J614s were reported October 4 (#35755499) and still under investigation October 23; blanket disabling is not an acceptable daily-baseline fix.

### 6. SMP: do not confuse startup progress with fault 205

Sven reported intermittent M4 Pro secondary-start failures even without the HV on September 26 (#35730084), suspected a cache/MMU-enable startup race September 27, and reported substantially improved startup on October 5 (#35757004 onward). October 10 mentions aligned/static SMP stacks (#35775253). Another J614s test enumerated multiple P cores on October 5; that is a boot observation, not a stress result.

None demonstrates that our post-startup Linux MM/COW corruption is fixed. Keep `maxcpus=1`, retain the established reproducer and fail-stop conditions, and preserve the DEVLOG distinction between real fixes and timing perturbations. When a separate m1n1/kernel refresh is ready, repeat exactly the old reproducer and cold-start matrix, changing one component at a time.

### 7. New asahi-wip base: useful, but pin after the regression fixes

October 14 brought asahi-wip to 7.2.10 and included idle=nop/WFxT overrides (#35787256–35787274). That is downstream enablement, not proof an arbitrary stock kernel will boot M4 correctly; October 20 still noted missing WFIT support in 7.3 (#35805957).

Early 7.2 rebases had GPU object lifetime/pinning leaks, external buffer import failures, and USB probing problems. Follow-ups matter: the GPU leak and dma-buf import fixes were pushed October 20 (#35804462, #35808085); USB and GPU were reported working October 21 (#35809493–35809508). The regmap cache-init/exit locking fix is included (#35812527), useful because GPIO lockdep otherwise disables subsequent diagnostics. M1 Max suspend regression was separately traced to dropping `apple,dcs-min-ps` (#35810714–35810885), not a T6040 suspend fix.

`asahi-7.2.11-1` was tagged October 21; October 22's initial `asahi-7.2.12-1` tag was corrected after pointing at the wrong base, and `asahi-7.2.12-2` followed an Atlantic Ethernet fix (#35814636–35815869). These tag names are reported by the logs; resolve and record actual SHAs before use. October 23 USB recovery required `CONFIG_RESET_APPLE_CIO` and `CONFIG_USB4_APPLE_SOC` (#35816692–35816871); earlier discussion also required USB4 built-in on an M3 setup. Audit complete configs rather than attributing missing subsystems to silicon.

Recommendation: use the corrected late-October snapshot as an isolated integration candidate, not a replacement for the already built diagnostic. Carry Wallace patches via its existing build/patch workflow and verify all three Norwegian-keymap layers, actual boot Image, firmware and DT compatibility.

### 8. WiFi, KVM, GPU, media and desktop follow-on work

- **WiFi:** BRCM4388 v1 sent September 25 ([series](https://lore.kernel.org/asahi/20260925-brcm4388-submit-v1-0-b5cbc2cde2fb@gmail.com/T/)); chip support first, DT/PCI separately. October 20 the author reported it working atop 7.3 (#35806827). Useful for reducing our downstream delta; our working WiFi/BT baseline does not need emergency replacement. No new T6040 Bluetooth breakthrough identified.
- **KVM:** M3/M4 PMU/GIC SEIS workaround series progressed from October 8 v1 to [October 21 v2](https://lore.kernel.org/asahi/20261021-apple-m3-m4-kvm-v2-0-04905152cc2a@gmail.com/). Yuka reported testing the erratum across available devices October 20 (#35805534), but the exact tested CPU list must be checked in the mail before claiming T6040 coverage. Earlier testing explicitly did not include M4 Pro (#35769947–35769964). Relevant to future VM use, distinct from native SMP fault 205. Nested virtualization still produced host/guest hangs on M3 Max (#35775507–35775511).
- **GPU/display:** existing-driver rebase and interchange work is not evidence of G16/M4 support. M4 login-screen tracing opens a route to investigate it. No accelerated T6040 Linux GPU or panel-brightness completion identified. Simpledrm and keyboard backlight reports are not DCP panel-brightness support.
- **AVD:** v2 submission, firmware/driver protocol coupling, compressed interchange and compositor integration progressed. Later reports still contained YUV import/layout and direct-scanout issues. Keep kernel, avd-fw, VA-API wrapper and Mesa compatible; no T6040 decoding sign-off identified. Encoding remains separate work.
- **Audio:** macaudio v2/v3/v4 preparation and speaker feedback fixes chiefly concerned existing supported machines. The October 20–24 TAS2770/5770L 96-kHz issue reproduced on M1 laptops but not the mini; it is not a reason to remove protection on J614s or claim M4 audio done.
- **Per-process 4K pages:** p3s/warthog ran Wine/FEX games by October 9–10 after an initial SIGBUS typo was fixed (#35769082). Nevertheless maintainers explicitly said it could not ship in its current form (#35777077), and October 24 found another nondeterministic GCC failure, also reproducible on the older base (#35819958). Defer this invasive MM series while our own SMP/MM correctness remains unresolved.
- **Installer/boot:** GUI work is mostly UI/core refactoring, not new machine support. October 10 installer macOS-26 extraction was still nonfunctional (encrypted IPSW payload handling), while 26.6.2 was the M4 target for manual tethered development (#35775519–35775568). Target boot-volume firmware matters, not just the primary macOS version. No reason to replace our sanctioned SD-first development workflow with a new installation experiment.
- **Other generations:** M3 Ultra AIC power, M5 SART4/ANS dependencies, base-M4 USB and M1 suspend/audio fixes are useful comparisons, not interchangeable T6040 patches. September pinctrl discussions favor standard `gpio-reserved-ranges`; do not copy A18/M5 reserved pin numbers to our board.
- **Safety boundary:** October 24 Stockholm/secure-element discussion reinforces avoiding unknown SPMI/SEP endpoints; it supplies no new permitted transaction. Existing Wallace restrictions remain unchanged.

## Recommended sequence

1. **Finish the existing controlled NVMe read test (6001)** when CJ requests a rig session. Record queue-wrap behavior and RAM checksum evidence. New same-board success strengthens the payoff; it does not make the result predetermined.
2. **Do an offline convergence audit** of Yuka's t604x DT/input/storage branches and the corrected late-October asahi tag. Produce a minimal patch map and pinned candidate, preserving the daily baseline. Check controller-state regression handling explicitly.
3. **Complete practical integration already locally proven:** trackpad in the daily image, SD fsck/shutdown hardening, and the narrowly scoped right-port VBUS work. Preserve lease/preflight/safety gates for later hardware execution.
4. **Validate SMP separately** against fault 205 after the candidate passes single-CPU storage/input regression checks. Do not combine p3s, unproven power-domain experiments and SMP diagnosis.
5. **Use the new tracing stack for remaining hardware gaps**, especially T6040 ATCPHY/TB5 and DAPF, coordinating against the public work already underway without posting on the user's behalf. GPU/DCP/audio/suspend remain longer-term daily-driver blockers.

Mainline progress is meaningful, but upstream submission, downstream integration, and local daily-driver validation remain three separate milestones. No capability table entries should be marked complete on the strength of this review alone.
