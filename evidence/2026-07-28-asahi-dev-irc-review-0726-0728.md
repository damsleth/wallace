# #asahi-dev trawl 2026-07-26 → 07-28: five items that touch our tree, two clean negatives

Read-only review of the three days CJ pointed at (all three read in full; 07-28 was still in
progress, covered to 21:48 UTC). Nothing posted anywhere. Claims are marked **measured** (someone ran
it on hardware), **hypothesis**, or **unanswered**. Local verifications I did myself are called out.

## Two clean negatives, stated up front

- **PCIe / WiFi: nothing.** Not one message in three days on apcie, PHY-IP, clkgen, CIO3 PLL,
  link-up, BCM4388, brcmfmac, `apple,mriya`, or WLAN. Our op-115 / `_initializePhy` work is entirely
  our own lane. (Adjacent only: a new `yuyuyureka/m1n1` branch **`t8140-pcie`**, head `a7857af8bb6a`,
  "pcie: Add initial t8140 support" — a second M4-cohort `pcie_init()` worth an offline diff against
  our D1/D2 decode.)
- **macOS-not-binding-Linux-CDC-gadgets: nothing.** Nobody upstream has reported our ticket-173
  symptom. That wall stays ours, and the panel dmesg conclusion (M4 side healthy, `udc=configured`,
  macOS has no host-side CDC-ethernet driver for a generic gadget) is unchallenged.

## 1. NVMe — independent corroboration of what I verified separately today

The IRC trawl independently surfaced yuka's ANS **reg[3]=NVMMU / reg[9]=NVMe** split, matching the
finding I verified against our own ADT and fault log in
`evidence/2026-07-28-upstream-review-nvme-reopened-pcie-d2-confirmed.md`. Two additions from IRC:

- **It also explains a loose end we recorded:** our "m1n1 `0x29120` vs Linux `0x28120` TCB-status"
  discrepancy is exactly a two-base-vs-one-base artifact.
- **On-hardware status is weaker than it first looks.** enverbalalic (real M4 Max / t6041) hit an
  SError on yuka's Linux branch, root-caused it to **`pmgr` and `pmgr1` being swapped between their
  two DTs** — not hardware — and after fixing it reported **"but no `/dev/nvme*` still"**
  (*measured*, cause unknown, nobody answered). His m1n1-side "nvme is not complaining"
  (*measured but weak* — "not complaining" ≠ a read returned data; no read result was posted). And
  yuka's "it worked on the t6040 remotely" is *ambiguous* — in context most likely "booted without
  SError on flokli's j773s", **not** `/dev/nvme*` appearing. **Do not quote either as "NVMe works
  on M4".** Our ticket 174 stands as written: the m1n1 read-only probe is the decisive test.

## 2. AIC locked-sysreg belief is CONTRADICTED — but do not act on it for our board

**Verified locally:** `docs/DEVLOG.md:174-176` says *"Upstream testing on 2026-07-21 still classified
T6040/T6041 as locked even on macOS 26.6 RC / 27 beta 4; **do not remove this patch**."*

**07-28 21:47, flokli, measured on real t6040:** `msr((3,5,15,1,3), mrs((3,5,15,1,3)))` **works on
macOS 26.6**; yuka: "so 26.6 has it unlocked on all M4*". That encoding is exactly
`SYS_IMP_APL_VM_TMR_FIQ_ENA_EL2` (`drivers/irqchip/irq-apple-aic.c:187`) — one of the two registers
our flokli patch comments out.

**Why we must NOT remove the patch yet**, three caveats:
1. Only that one register was tested; our patch also skips `SYS_ICH_HCR_EL2`.
2. It was tested from the m1n1 proxy, not from Linux `aic_init_cpu` in hyp mode.
3. **Our board is paired to 25F84 = macOS 26.5.2, not 26.6.** The unlock may be a 26.6-iBoot
   property we do not have.

Action taken: DEVLOG amended to record the contradicting measurement plus these caveats. Removing
the patch is a separate, testable experiment (and only after a firmware-pairing decision).

## 3. ATC PHY t6040 tunable inventory — measured, and it reshapes ticket 170

yuka dumped and corrected the real t6040 atcphy tunable set (**17 entries** vs t8132's 44). The
termbin pastes expire, so the corrected t6040 list is transcribed here:

```
ATC0AXI2AF, ATC0AXI2AF_LIOA, ATC_COMMON_CFG, ATC_FABRIC, AUS40CMN_SHM,
AUSPLL_CORE, CIO4PLL_CORE, LN0/LN1_RX_CFG_TX_OF_RXCLK, LN0/LN1_RX_EQ_CIO_DFLT,
LN0/LN1_RX_TOP_CIO_DFLT, UC_REGS_CIO_DFLT, USB2PHY_DEV, USB2PHY_DFLT, USB2PHY_HOST
```

Consequences for the DT authoring in ticket 170:

- **`CIO3PLL_*` is renamed `CIO4PLL_CORE`** on t6040 ("they grew tb5 in t6040" — chaos_princess).
  All `ACIOPHY_*`, `AUSCMN_*`, `AUX_TOP`, `CIO_SHIM`, `CLKMON_CFG` are **gone**; new `AUS40CMN_SHM`,
  `UC_REGS_CIO_DFLT`, `USB2PHY_DFLT`.
- **`apple,tunable-laneX-usb` will come out EMPTY** from adt2dt — the only per-lane tunables are the
  three `*_CIO_*` ones. yuka's own read: *"I doubt USB3 will work"* (**hypothesis**, explicitly
  unresolved: "if that means we just don't need them? Idk").
- **Hopeful precedent (measured, but on t8132 not t6040):** yuka got t8132 working with **no new
  tunables at all** — just the existing t8122 table plus an alias `ATC0AXI2AF → ATCAXI2AF`.
- **Operational fact (measured):** "atcphy does not start to do things unless you plug sth in".
- yuka floated adding a **"reset-only" mode in atcphy** — close in spirit to our force-host approach
  and worth watching as the upstream shape.
- t6050 shares the same tunables, so this is an ATC generation, not a one-off.

This pairs with our own `AppleT6040TypeCPhy::_sRegisters[44][8]` decode. **Ticket 170 updated.**

## 4. Two cheap wins for our images

- **`CONFIG_EXTRA_FIRMWARE`** (07-27, chaos_princess/jannau/chadmed, measured working by sofus):
  build firmware **into the kernel image** instead of staging it in an initramfs. No wildcards
  accepted (jannau). This is strictly better than the `T6040_WIFI_FW=1` initramfs staging I added
  earlier today, because it costs no initramfs budget against the ~128 MiB decode limit. **Ticket
  168 updated** with both options.
- **`apple,dart-vm-size` is now mandatory** — a missing property gives
  `failed to read 'apple,dart-vm-size': -22`; fix is e.g. `apple,dart-vm-size = <0x0 0xa0000000>;`.
  Needed for any **new DART node**, i.e. exactly the `dart-usb2` nodes ticket 170 will author.

## 5. Collaboration opening worth a drafted message (CJ sends, never us)

**sven now has a working SPRR/SPTM-emulating hypervisor booting macOS** (m1n1 **PR 643**,
"14 files changed, 1412 insertions"; boot time down to 1–2 min; SMP fixed by jannau's one-liner —
drop `clpc=0` from boot-args, which had been preventing use of the performance cores). On 07-28
18:13 he said *"next up: time to get a M4 and see what SPTM/TXM needs additionally"*; yuka offered
remote access and sven **declined for now** (buying one; busy until the weekend).

Why this matters to us more than to anyone: **a working M4 hv is what would let us trace
`AppleHPMInterface::roleSwap()` and `ApplePCIEBaseT8132::_initializePhy()` live** instead of
statically decoding a kernelcache — the exact technique that would have caught today's PhyCommon
attribution skew and settled the SWDF outcome. We have a physical M4 Pro with a mapped port
topology, a paired 25F84 corpus, and a documented tether. A drafted offer of J614s access/traces,
timed for when his M4 arrives, is queued for CJ (see the drafts ticket).

Also worth a drafted note: enverbalalic's **"no `/dev/nvme*` on t6041"** is exactly where our Linux
NVMe path also stops — our ANS/SART/CoastGuard measurements would be useful to him, and his
**`ps_ans` always-on** finding (below) is useful to us.

## 6. Smaller items, recorded so we don't re-derive them

- **`ps_ans` and the 5-minute watchdog reboot (measured, t6041).** enverbalalic had Linux
  "forcing a reboot every 5 min"; fix was *"same always-on as t8132 … `ps_ans`"*. **Verified
  locally:** our only `ps_ans` override is `dts/t6040-j614s-dcuart-nvme-ans-hold.dts`, which sets
  `apple,skip-auto-enable` — i.e. the *opposite* direction — and that is a diagnostic DT, not the
  daily driver. Our images also keep a userspace watchdog alive, so if we share this bug we may be
  papering over it. Worth a reconciliation against the 214-domain PMGR quirk before the next
  long-uptime claim.
- **macOS version choice (measured twice):** enverbalalic got **random iBoot panics rebooting from
  Linux via `macvdmtool`** after updating to the macOS 27 beta; yuka sees the same on t8132 and
  *"which is why I use 26.6RC"*. With flokli's 26.6 sysreg unlock, **26.6 looks like the sweet spot
  for M4** — relevant only if we ever move our pairing off 25F84, which would invalidate our whole
  enrolled-object/firmware corpus. Not a recommendation to act.
- **iBoot rejects appended stage-1 params because "the installer adds trailing zero bytes"**
  (measured, yuka). Same failure family as our hard-won 16 KiB-multiple rule — different mechanism,
  same lesson: iBoot is unforgiving about object length/padding.
- **SPMI/tipd design constraint (authoritative):** chaos_princess, the SPMI series author, says
  **polled SPMI cannot work for tipd — "tipd needs downstream irqs"**. Does not affect our attended
  one-shot 4CC write, but it bounds any future `tps6598x-spmi` adoption. yuka's `tps6598x-spmi` head
  is **unchanged** (`dcc5f1bc`) since our 07-24 audit — that audit stands.
- **RTKit management-message type may be 4 bits, not 8** (nickchan: bits `[55:52]`, not `[59:52]`,
  because the top 8 bits are the endpoint on 64-bit mailboxes; chaos_princess: "i think our oslog
  code is just wrong"; sven: the mask "might've just been a guess"). Shared code — would touch our
  SMC/ANS RTKit paths if it changes upstream.
- **DCP:** jannau — *"m4\* fuos support is busted in all of 15.x"*, so for J614s it is 14.x or
  26.x/27.x, never 15.x. Supports our 26.x pinning and track-don't-build posture on ticket 022.
  chadmed warns DCP 14.8.3 testers that not freeing stale framebuffer references *will* break it
  after some uptime.
- **macsmc upstreaming detail:** the Kconfig symbol is now **`CONFIG_MACSMC_POWER`**, and the
  charge-threshold/charge-inhibit properties were dropped during upstreaming then re-added in
  `asahi-7.1.5-2`. Also: with SMC firmware ≥ ~26.4 the MagSafe LED turns green whenever the SMC is
  told to stop charging, independent of the driver — worth knowing before we read anything into LED
  behaviour.
- **New nicks:** `mmediouni[m]` (Arm architecture, FEAT_TIDCP1), `sofus` (ISP/webcam, fast tester on
  t6030), `aites[m]` (trackpad haptics via DockChannel, `github.com/Ambioid/linux`), `nickchan`
  (RTKit bitfields, SPTM-version gist `https://gist.github.com/asdfugil/101ae32734938cf2c186ff330fba1e97`).
- **Tester coordination we could join:** flokli agreed to plug a USB-ethernet dongle into the j773s
  on 07-28; **no result had been posted by 21:48 UTC**. We have the physical M4 Pro and the port map
  — a natural place to contribute once VBUS works.
