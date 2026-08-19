# Ticket 303: binary exact-review of buildB (v2-PHY USB2-native rebuild)

Date: 2026-08-19. Reviewer: fable (this session), offline, no rig.
**Non-builder review**: the buildA/B/C v2phy artifacts were produced by the
sibling fable session (`evidence/2026-08-18-t6040-usb2-v2phy-rebuild.md`); this
session did not build them, so the COORDINATION non-builder requirement is met.
This session authored the v2 slice fix and the SPMI driver, not these binaries.

## Verdict

**PASS — `Image-usb2-native-right-v2phy.buildB` is the correct, reproduced
artifact for the ticket-108 re-run.** Every pinned hash re-derived
independently and matched; the fresh-vs-fresh reproduction is byte-exact; the
config is byte-identical to the proven Jul-29 baseline; the v2 fix is present
and the v1-only failure marker provenance holds.

**One required documentation correction** (does NOT change the artifact's
fitness): the rebuild doc mis-describes the config — see finding F1. The gate
that actually governs correctness (config byte-identity to the reviewed
baseline) passes, and the safety conclusion holds, but the doc's specific
wording is false and must be fixed before it guides a rig operator.

## Independently verified (every hash re-computed this session)

| Check | Expected (303 pin / doc) | Observed | Result |
|---|---|---|---|
| buildB Image sha256 | `802483060f21…09a5be` | same | ✓ |
| buildB System.map sha256 | `793adc5611…d2359` | same | ✓ |
| buildB config sha256 | `221666c6d3…d809e543` | same | ✓ |
| buildB == buildC (Image/System.map/config) | byte-identical | `cmp` clean on all three | ✓ fresh-vs-fresh reproduced |
| buildA disqualified & distinct | 21 bytes differ, `88e064d5…` | `cmp -l` = 21 lines, hash matches | ✓ |
| config == Jul-29 baseline | `221666c6…` (= `config-…-usb2-native-right.hid-build1` and `config-pcie-…-right{,.build1}`) | all four equal | ✓ |
| DTB | `6df8af39…` | `6df8af393c43c4a50143…` | ✓ |
| committed v2 patch (HEAD) | `b7f02c3c…` | same; source-reviewed; touches 0 DT lines | ✓ |
| version string | git sha `4f2429104009` | `Linux version 7.1.3-g4f2429104009-dirty … 2026-08-03` | ✓ |
| v2 PHY markers | present | `phy-apple-t6040-usb2`, `apple,t6040-atcphy`, `Failed forced host-mode init` — each ×1 | ✓ |
| distinct from broken v1 | ≠ `3caa0f78…` | ≠ | ✓ |
| distinct from Aug-4 clobber | ≠ `fa927c56…` | ≠ | ✓ |

The v2 delta carries no new kernel string (a constant + a comment), so the
identification correctly rests on config-equality + the applied-patch hash +
this provenance chain, exactly as the rebuild doc states. That chain is sound:
buildB ← Jul-29 script `@11f2547` + pinned flags + tree `@4f2429104009` + patch
`b7f02c3c` (independently source-reviewed, `2026-08-04-…-slice-v2-independent-
review.md`), and buildC reproduces it byte-for-byte from a virgin tree.

## Safety: the run does NOT touch the deny-by-default SPMI bus (verified)

The rebuild doc's DTB-drift argument says the new `wifi.dts` include nodes
(SPMI RTC, keyboard-backlight pwm-leds, internal NVMe) are "driverless ... and
therefore inert." The *claim of built config* behind it is wrong (see F1), so
I verified inertness empirically at the Image level rather than trusting it:

| Controller a new DT node needs | config | in the Image? (System.map) |
|---|---|---|
| Apple SPMI bus (`spmi-apple-controller`) | `SPMI_APPLE=m` | **0 symbols** — bus never instantiates |
| Apple PWM (`pwm-apple`) | `PWM_APPLE=m` | **0 symbols** |
| Apple SPMI NVMEM | `NVMEM_APPLE_SPMI=m` | **0 symbols** |
| Apple NVMe | `NVME_APPLE=m` | **0 symbols** |

The safety-critical one: with no Apple SPMI **controller** in the running
kernel (and these images cannot load modules), the SPMI bus is never brought
up, so the newly-included SPMI RTC/NVMEM nodes **cannot probe** — Linux issues
no SPMI transaction during the run, and the deny-by-default SPMI envelope is
not entered. `SPMI=y` (core) and `RTC_DRV_MACSMC=y` (SMC RTC, permitted) are
present but neither instantiates an Apple SPMI bus.

## DTB content — the run DT actually arms the v2 eUSB2 host path (verified)

The pinned `6df8af39…` bytes match, but the Aug-4 `934dd7b2…` DTB is gone from
disk, so I decompiled the pinned DTB (`dtc -I dtb`) to confirm it contains the
USB delta rather than only trusting the hash:

- `usb@392280000`: `dr_mode = "host"`, `status = "okay"`,
  `apple,force-host-mode`, `phys = <… 0x03>` (PHY_TYPE_USB2), `phy-names =
  "usb2-phy"`.
- `phy@392a90000`: `compatible = "apple,t6040-atcphy"`, `reg` = both banks
  `0x3_92a90000/0x4000` + `0x3_92800000/0x4000`, `status = "okay"`.
- both `apple,t8110-dart` usb2 DART instances present.

The run DT arms exactly the path the v2 slice fixes — no more (no USB3 PHY, no
retimer, no role switch).

## Finding F1 — the rebuild doc's config/driverless characterization is factually wrong

The doc (`2026-08-18-…-rebuild.md`) argues the config is a minimal, drift-free
delta with, verbatim, "no BT, no NVMe" (§Config gate) and
"# CONFIG_BLK_DEV_NVME is not set" / `drivers/nvme/host/apple.c` "is not
compiled under this config" (§content delta). The actual config
(`221666c6`, byte-identical to what the doc pins) contains:

```text
CONFIG_BT=y
CONFIG_BT_HCIBCM4377=y
CONFIG_BLK_DEV_NVME=m
CONFIG_NVME_APPLE=m
```

So: BT is **built in** (and linked into the Image — 38 `hci_bcm/bcm4377`
symbols in System.map), and NVMe is a **module** (`=m`), not unset, and its
`apple.c` **is** compiled (into `nvme-apple.ko`). The same imprecision extends
to the DTB-drift argument's "no SPMI, no PWM ... built": `SPMI=y`, `PWM=y`,
`LEDS_PWM=y`, `RTC_DRV_MACSMC=y` are all built in; only the *Apple controllers*
(`SPMI_APPLE`, `PWM_APPLE`, `NVMEM_APPLE_SPMI`) are `=m`. The inert-at-runtime
conclusion holds — but because those controllers are `=m` and unloadable
(0 symbols in the Image, table above), not because the subsystems are absent.

**Why the artifact is still fit despite the wrong prose.** The property that
matters is what runs in the booted kernel, and that is verified good by two
independent facts:
1. **NVMe is absent from the Image.** `grep -c 'apple_nvme|nvme_probe|
   nvme_core_init' System.map.buildB` = **0**. `=m` plus these images' inability
   to load modules means the NVMe driver never enters the running kernel, so
   the ticket-227 dead-controller-teardown hazard genuinely cannot fire. The
   doc's conclusion is right; its reasoning ("not set" / "not compiled") is
   wrong.
2. **This exact config was already booted healthy.** `221666c6` is the config
   of the Aug-4-booted image `3caa0f78`; that boot was healthy (SD up, no NVMe
   crash) and failed only at dwc3 — the fault v2 fixes. BT `=y` was therefore
   live in the Aug-4 run and is part of the proven daily-driver baseline; it is
   orthogonal to the 108 pass/fail (USB child + right DART/xHCI + console).

**Required action:** correct the rebuild doc so no rig operator or future
builder relies on "NVMe is not set" or "no BT" — state instead that NVMe is
`=m` and absent from the Image (verified by System.map), and that BT is `=y`
(baseline, inert to the USB observation). This is a doc fix, not a rebuild:
the binary and its config are byte-identical to the reviewed baseline and need
no change.

## Gates still open before the 108 rig run (unchanged by this review)

- CJ sign-off + the rig (serialized for 230 at last check).
- Run fixture per the rebuild doc: `IMAGE=Image-usb2-native-right-v2phy.buildB`,
  DTB `6df8af39…`, `initramfs-sdroot-hardened.cpio.gz`, `maxcpus=1`. Do **not**
  boot buildA.
- Expectation unchanged: v2 restores the path to xHCI root hubs; a child on the
  bus-powered S128 stick only if VBUS is already live (the SPMI PD driver /
  ticket 229 R0 read is the path to VBUS, not this image alone).
