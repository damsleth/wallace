# Ticket 305: binary exact-review of the PD/VBUS image (buildA) — FAIL (must-fix)

Date: 2026-08-19. Reviewer: opus (non-builder — `fable` built buildA in
`/build/linux-usb2pd-fa`; this session did not). CJ requested the review as the
gate before the attended run.

## Verdict: FAIL — do not run buildA as-is

The kernel/DTB/patch provenance is all correct, and the hpm2 PD endpoint itself
is exactly the sanctioned one. **But the artifact does not honor its own stated
gate — "hpm2 ONLY via the DT gate" (ticket 305, CJ's 2026-08-19 sign-off).**
Because this image is `SPMI_APPLE=y` (the deliberate, signed-off change so the
hpm2 bus instantiates), and the PMU SPMI bus is left enabled with the macsmc
nvmem consumers wired, the run will issue SPMI reads **and writes to the
abbey-pmic PMU** — a second SPMI endpoint that was never reviewed or signed off,
and that `SPMI_SAFETY.md` forbids (sole endpoint = right-port hpm2; no PMU
writes).

**Required fix (builder, `fable`):** in `t6040-j614s-dcuart-usb2-native-right-pd.dts`,
set the PMU SPMI bus `spmi@509014000` (or at least its `pmic@e` child)
`status = "disabled"`, leaving **only** `spmi@309198000`/`usb-pd@c` (hpm2)
enabled — that is what "hpm2 ONLY via the DT gate" requires. (Alternative:
build `NVMEM_APPLE_SPMI=n` so the abbey-pmic nvmem provider never binds and the
smc-rtc/smc-reboot cell lookups find no provider; the DT disable is the more
explicit gate and is preferred.) Then rebuild and re-review.

## What passes (verified independently)

| Check | Result |
|---|---|
| buildA Image / System.map / config / DTB sha256 vs 305 pins | ✓ `5a136710` / `9bf2f204` / `51aa40f0` / `36e5c462` |
| PD stack built-in: TYPEC, TYPEC_TPS6598X, TYPEC_TPS6598X_SPMI, SPMI, SPMI_APPLE, USB_DWC3_APPLE, USB_ROLE_SWITCH, PHY_APPLE_T6040_USB2 | ✓ all `=y` |
| Image markers: `tps6598x-spmi`, `usbc,sn201202x,spmi`, `phy-apple-t6040-usb2` | ✓ each ×1 |
| Apple SPMI controller linked into the Image (=y, so the bus does come up) | ✓ 14 `apple_spmi` syms in System.map |
| PD patch provenance | ✓ committed `77fd00b`; PHY slice v2 `b7f02c3c` |
| hpm2 endpoint matches SPMI_SAFETY | ✓ `spmi@309198000` / `usb-pd@c` reg `<0x0c 0x00>` (controller 0x309198000, SID 0x0c); connector `power-role="source"` `data-role="host"` |
| Exactly one SPMI PD node (no hpm0/1/5) | ✓ `usbc,sn201202x,spmi` ×1 |
| USB2 data path armed (dwc3 host + phys + atcphy banks) | ✓ (carried from the 108 v2phy path) |
| `ans_nvme` disabled despite NVMe=y (227 hazard out) | ✓ builder's DT override present |

## The failure, in detail

Built-in and active this boot: `SPMI_APPLE=y` (controller, 14 syms),
`NVMEM_APPLE_SPMI=y` (abbey-pmic nvmem provider), `MFD_MACSMC=y`,
`RTC_DRV_MACSMC=y`.

The DTB leaves the PMU SPMI bus enabled:

```
spmi@509014000 { status = "okay";              // PMU SPMI bus
  pmic@e { compatible = "apple,abbey-pmic","apple,spmi-nvmem";
    nvmem-layout { rtc-offset@2100; boot-stage@f801; boot-error-count@f802;
                   panic-count; shutdown_flag; ... } } }
```

and the macsmc SMC node consumes those cells (status okay):

```
smc@50c600000 { status="okay";
  rtc    { compatible="apple,smc-rtc";    nvmem-cells=<0x5d>; }              // rtc_offset
  reboot { compatible="apple,smc-reboot"; nvmem-cells=<0x5e 0x5f 0x60 0x61>; } // shutdown_flag, boot_stage, boot_error_count, panic_count
}
```

Consequence at runtime:
- `apple,smc-reboot` reads `boot_stage`/`panic_count`/… at probe and **writes**
  `boot_stage`/`shutdown_flag` on the reboot/shutdown path — over SPMI to the
  abbey-pmic PMU.
- `apple,smc-rtc` reads `rtc_offset` over SPMI.

On every previous signed-off image `SPMI_APPLE` was `=m` (unloadable), so the
abbey-pmic nvmem provider never registered and these lookups were inert. 305 is
the first image where the SPMI bus is live, so it is the first where these PMU
SPMI transactions actually fire.

The FAIL rests on grounds that don't depend on how the PMU-nvram permission is
read:

1. **The artifact contradicts its own gate.** Ticket 305 and CJ's sign-off both
   say "hpm2 ONLY via the DT gate," enumerating the permitted transactions
   (WAKEUP + reads + SSPS-S0 + INT_MASK1 + W1C INT_CLEAR1). buildA also brings up
   `spmi@509014000` and reads/writes the abbey-pmic — a second endpoint (SID
   0x0e) that the sign-off never enumerated. An exact review fails on the
   mismatch alone (same standard as 303's F1, but here it changes *runtime
   behavior*, not just prose).
2. **It confounds the run's own falsifiers.** 305's falsifiers key on SPMI
   errors/behavior at the hpm2 endpoint; first-ever-live PMU-SPMI traffic
   mid-experiment, plus the ticket's STOP condition "any SPMI error outside the
   envelope / any write beyond the signed-off set," would trip at probe and
   muddy the observation.
3. **The permission question is CJ's to answer explicitly, not the reviewer's
   to assume.** There *is* a standing CJ grant for smc_reboot/smc_rtc nvram
   (boot-policy/clock) writes — arguably these very cells — but that grant was
   about the SMC/gpio-macsmc path; whether it extends to raw Linux **SPMI
   transport** to the abbey-pmic is not something this review should assume.

Two exits, either closes the FAIL:
- **Preferred — `fable` applies the DT gate** (disable `spmi@509014000`). This
  is not new territory: every prior proven boot ran with `SPMI_APPLE=m` and
  these nvmem lookups finding *no provider*, so disabling the PMU SPMI bus
  restores exactly the known-good runtime behavior.
- **Or — CJ explicitly widens the 305 sign-off** to include the abbey-pmic
  nvmem cells over SPMI, if CJ judges the standing nvram grant to cover the SPMI
  transport. Then buildA is in-envelope as-is.

## After the fix, re-review checklist

1. DTB: `spmi@509014000` (PMU) disabled; only `spmi@309198000`/hpm2 enabled;
   confirm no other SPMI child is `okay` with a built-in driver.
2. Optionally a second build for byte-reproducibility (305 was a single build;
   the builder offered one).
3. Then the attended run may proceed with CJ present, per the 305 procedure.

The rest of the image is sound; this is a one-line DT gate (or one Kconfig
line), not a redesign.

---

## ADDENDUM 2026-08-19 — CJ widened the envelope; verdict → PASS

The FAIL above was correct against the then-current sign-off. CJ then chose exit
#2: **the 305 envelope now includes the abbey-pmic boot-policy/RTC NVRAM cells
over SPMI**, and `SPMI_SAFETY.md` was rewritten to allow that bounded path
(Entry 2). Brick-risk analysis that supported the decision (all primary-source,
this session):

- The abbey PMU is exposed to Linux **only** as an NVMEM provider —
  `drivers/nvmem/apple-spmi-nvmem.c` is the sole binder of `apple,spmi-nvmem`,
  it is not a regulator and has no voltage/rail path. Linux cannot set a rail
  through it.
- Only `nub_spmi0`/`pmu1` (abbeyL1, SID 0x0e) is in the Linux DT; `abbeyF1`/`F2`
  (nub-spmi1/2) and `btm` (SID 0x0b) have **no** Linux DT node and **no** driver
  (`grep '"...btm"'` in drivers/ is empty), so Linux never touches them.
- The cells are boot-policy/RTC scratch (boot_stage, panic_count, rtc_offset,
  shutdown_flag), written by iBoot/macOS every boot; worst-case corruption is a
  DFU-recoverable boot-policy hiccup, not a voltage event or permanent brick.
- This is the same stack production Asahi runs on every M1/M2 boot.

So there is **no brick risk** in what buildA's Linux stack can actually reach.
A blanket "allow nub-spmi0/1/2" would *not* be certifiable (raw register writes
to an abbey SID could hit rail control = permanent damage), so the policy allows
only the bounded nvmem path and keeps raw-register / voltage / `btm` / RESET
prohibited.

**Verdict: PASS** — buildA is in-envelope as-is under the widened policy; no DT
change is required. One safeguard carried into the run procedure (ticket 305):
the attended operator must confirm the probe-time nvmem **reads** look sane
(boot_stage/panic_count/rtc_offset) **before** any Linux-initiated reboot
exercises the abbey **write** path, because the cell offsets were
project-measured, not inherited.

**Reviewer discretion on byte-repro:** 305 was a single build. For this volatile,
attended, warm-reboot-recoverable chainload I accept the single build — every
component was individually reviewed and the run is non-persistent. The honesty
note stays on the ticket; it is not a blocker for the attended run.

**Optional-conservative DT gate (NOT required), handed to fable:** if a future
image wants the PMU SPMI bus dark, the one-liner is
`&nub_spmi0 { status = "disabled"; };` (bus-level; also covers future children).
Under the widened envelope buildA does not need it.
