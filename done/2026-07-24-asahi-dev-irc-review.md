# #asahi-dev IRC review, 2026-07-22 → 2026-07-24 — findings

Follow-on to `done/2026-07-21-asahi-dev-irc-review.md`. Read the 07-22/23/24 logs
(browser, Anubis-cleared). 07-24 is only early-morning UTC so far. Project policy:
agents never post upstream; drafts for CJ only.

## 1. PMGR pwrstate encoding — DIRECTLY questions our 214-domain quirk (highest)

yuka, **07-24 07:15–07:19** and **07-22 05:08**:
- "I'm slightly unsure about the t6040/t6041 pwrstate nodes … on t6000 vs t6002
  and t6020 vs t6022 they actually had different pmgr devices in the adt … big
  diff between t6020 and t6021: less memory channels, less dispexts."
- "I think I'm missing something in the **new pmgr adt encoding that marks these
  devices as active/inactive** — because with the current adt2dt interpretation,
  a **t6040 adt (j614s) has all the memory channels and dispexts of t6041 still
  present and active (!no_ps)**."
- 07-22: "good catch with the ps_dispext3_cpu. **the t6040 I tested on does not
  (really) have that node**."

**Why it matters for us:** this is the exact machine (J614s = t6040) and the exact
subsystem as our live-tested 214-domain PMGR quirk (preserve firmware-active,
disable `disp_cpu`, skip auto-enable on `dispext0/1_cpu`). yuka is saying the
adt2dt no_ps interpretation likely **over-counts** active domains on t6040 —
t6041's extra memory-channel/dispext domains appear active in the t6040 ADT but
the silicon lacks them. Our quirk empirically boots 3/3, so we may be papering
over the same mis-encoding with the preserve-active policy. **Action: a
reconciliation ticket (below) — compare our no_ps domain set against yuka's
finding; if there's a real active/inactive encoding bit we both missed, it
supersedes the preserve-active workaround and is the correct upstream shape.**
This is a strong collaboration point (our PMGR quirk is further along; yuka has
the multi-die comparison).

**Resolved locally 2026-07-24:** the concern does not reproduce in the exact
live-captured J614s/25F84 ADT (`7a92e6e4...`). Its existing `no_ps` bit cleanly
marks AMCC/DCS 16–31 and every dispext2/3 record inactive; the generated
214-domain DT contains only AMCC/DCS 0–15 and dispext0/1. No new parser bit is
needed for this board. The preserve-active quirk therefore remains a separate
raw-boot ownership policy. Ask yuka for the exact board/firmware/record bytes
before generalizing; evidence and a draft-for-CJ message are in
`done/2026-07-24-t6040-pmgr-active-encoding.md`.

## 2. sven: SPRR/SPTM emulation under hv on M4 (bears on our NVMe blocker)

**07-23 19:41–20:03**, sven + chaos_princess: sven is prototyping **SPRR
emulation with shadow pagetables** + patching XNU (replace genter/gexit/locked
msr/mrs with `hvc`; lazy-fill shadow PTEs, redirect unknown addrs to a stage-2
no-access page to trap SPTM's new mappings; handle the EL0 SPRR JIT flip via
commpage/on-disk libsystem patch). "this is all gonna be so very cursed. i think
i love it." This is the concrete start of **making hv work on M4 despite locked
sysregs/SPTM** — the "watch this space" in our ROADMAP is now active work.
Relevance: a working M4 hv reopens macOS-driver tracing *and* is the most
plausible eventual route to observe/enter the SPTM-guarded NVMe path our tickets
051–055 decoded. Track sven's progress; do not build here.

## 3. yuka: m1n1 usb/tps6598x (HPM) refactor — bears on our USB-root blocker

**07-23 19:21–19:26**: yuka refactoring m1n1 usb/tps6598x to iterate HPMs
("do a thing for each hpm", "find hpm index X"). Our USB-host smoke (ticket 064)
bounded the no-enumerate failure to the **Linux-absent SPMI HPM + ATC PHY
physical-link path**. yuka improving m1n1 HPM (tps6598x PD-controller) handling
is the upstream track that would eventually give T6040 USB host its CC/orientation
path. Our ADT confirms the HPMs are `usbc,sn201202x,spmi` on `nub-spmi-a0/a1`
(hpm0/1/2/5). Track; the HPM/ATC path stays the USB-root gate.

## 4. atc-phy tunables (bears on ATC PHY / USB3-TB, deferred)

**07-23 11:33 / 12:16**: chaos_princess asks if `tunable_LN1_RX_TOP_USB_EQA`
(in `/arm-io/atc-phy0`) exists on M3/M3Pro; jannau: "exists for both but is None
for M3, M3Pro has values." Confirms ATC-PHY tunables are populated on the Pro
dies — relevant when the deferred `atc-phy,t6040` driver work resumes (ticket
023, upstream-track). Not actionable here yet.

## 5. Minor / confirming
- **cs42l84 = the headphone jack codec** (chadmed, 07-23 11:26) — confirms our
  audio map (ticket 040); magsafe-side "biip" on t6030 was the jack codec.
- **nickchan**: m1n1 4-level-paging PR (07-22 18:44) — m1n1 infra, watch.
- **yuka** drafting an Apple Feedback re: "failure to start secondary cores on
  t6050 from a raw custom kernel object" (07-22 18:36) — same class as our raw-boot
  SMP; if Apple/yuka clarify, it informs ticket 005/034.
- yuka: macOS 27 beta slow-boot on MacBook Neo (FB filed) — unrelated to us; a
  reminder to keep our paired macOS at 26.x, not 27 beta (also breaks chadmed's
  DCP, per 07-21 review).

## Actions
1. **New ticket: PMGR pwrstate active/inactive reconciliation** (P1, pmgr) —
   the highest-value item; see below.
2. Track sven's hv/SPRR (SPTM), yuka's m1n1 HPM refactor (USB-root), and the
   atc-phy tunables — all upstream, no build-here.
3. Draft-for-CJ opportunity: our 214-domain PMGR quirk + no_ps data is directly
   useful to yuka's pwrstate question; a shared note would help both (CJ posts).
