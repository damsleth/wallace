# Ticket 303: the v2-PHY USB2-native rebuild — minimal delta, byte-reproduced

Date: 2026-08-18. Agent: fable (offline, kbuild container only, no rig).
Ticket: 303. Purpose: produce the artifact for the ticket-108 re-run — the
reviewed Jul-29 integrated image plus exactly one change, v2 of the PHY
slice (`b7f02c3c…`, the dwc3 `-EINVAL` fix, reviewed in
`evidence/2026-08-04-t6040-usb2-slice-v2-independent-review.md`).

## Why the naive rebuild was wrong, twice

1. **Name-derived flags failed loudly (2026-08-04).** Reconstructing the
   profile from the image name missed `T6040_INTEGRATED=1`; kbuild's
   fail-closed gate rejected it. The authoritative flag set lives in
   `evidence/2026-07-29-t6040-integrated-wifi-bt-usb2-dualmode-candidate.md`.
2. **Today's kbuild script produces a different kernel for the same flags.**
   Measured against the true Jul-29 baseline (`221666c6`), the current
   script's config drifts by 23 lines, and the substance is **=m → =y
   promotions**: `NVME_CORE`/`BLK_DEV_NVME`/`NVME_APPLE`, `SPMI_APPLE`, and
   `NVMEM_APPLE_SPMI` all become built-in. NVMe **linked into the Image** is
   an active hazard to the 108 observation (ticket 227's dead-controller
   teardown kills all block I/O), and a built-in Apple SPMI controller would
   let the new wifi.dts SPMI nodes probe. Caught by ticket 303's config
   byte-identity gate before any artifact was kept.
   *(Corrected 2026-08-19 per the binary review's F1: an earlier revision
   of this section blamed "Bluetooth added, NVMe built-in vs none" — that
   was read off a diff against the clobbered Aug-4 config. BT=y was already
   in the Jul-29 baseline, and the baseline's NVMe is `=m`, not unset.)*

**Resolution:** build with the Jul-29 script itself —
`scripts/t6040-kbuild.sh` at wallace commit `11f2547` ("integration: retain
keyboard fix in USB2 candidate"), staged as `$OUT/t6040-kbuild-jul29.sh` —
against the current kernel branch tip. The v2 patch deliberately kept the
v1 filename, so the historical script picks it up unmodified.

## Incident found on the way: the Jul-29 canonical artifacts were clobbered

The canonical `$OUT` names `Image-/System.map-/config-macsmc-hid-type-fix-
nbcon-ppp-usb2-native-right` no longer hold the Jul-29 pins: they were
overwritten on **2026-08-04 13:37** (the sibling's `T6040_TYPEC_PD`
compile-proof build; today's script still carries the ticket-130 overwrite
guard, so that overwrite was either `KBUILD_OVERWRITE=1` or predates the
guard). The pinned originals survive and were verified byte-exact today:

```text
3caa0f78…  Image  — from Image-…-usb2-native-right.xz (decompressed) AND .hid-build1
1ea47f23…  System.map — .hid-build1
221666c6…  config     — .hid-build1 (also config-pcie-…-right{,.build1})
```

The Aug-4 binaries that sat under the canonical names are preserved as
`*.aug4-clobber`. Nothing pinned was lost; the lesson is that **the
canonical `$OUT` name of a pinned artifact is not the pin — the hash and a
frozen copy (`.xz`, `.build1`) are.**

## Exact build

- Flags (pinned, Jul-29 doc): `DOCKCHANNEL=1 DOCKCHANNEL_NBCON=1
  HID_TYPE_FIX=1 T6040_INTEGRATED=1 T6040_PPP=1 MACSMC=1 WIFI=1 PCIE=1
  USB_HOST=1 USB_HOST_PORT=right T6040_USB2_NATIVE=1 NPROC=8`
- Script: `t6040-kbuild-jul29.sh` = `scripts/t6040-kbuild.sh @ 11f2547`
- Kernel tree: `wallace/t6040-bringup @ 4f2429104009` (current tip)
- Patches staged in `$OUT`: current repo state; the Jul-29 script applies
  only patches whose files are unchanged since Jul 29 — with one exception,
  the PHY slice at **v2** (`b7f02c3c…`), which is the entire point.

### The complete content delta vs the Jul-29 image (3caa0f78), stated honestly

1. The v2 PHY slice hunk (probe default `PHY_MODE_USB_HOST` + comment).
2. `arch/arm64/kernel/traps.c` (+5 lines, the 205-track oops improvement —
   the only kernel-tree change since Jul 29 that reaches the Image; the
   other tree delta, `drivers/nvme/host/apple.c`, is compiled only into
   `nvme-apple.ko` (`CONFIG_NVME_APPLE=m`), which is **absent from the
   Image** (0 matching System.map symbols) and can never load — these
   images have no module loading. *(Wording corrected 2026-08-19, F1: the
   baseline has NVMe `=m`, not "not set".)*
3. The version string's git sha (`-g4f2429104009` vs `-g298e42e8f64d`).

### Config gate

Build A's generated `.config` is **byte-identical** to the pinned Jul-29
baseline `221666c6…` — the profile is exact, zero drift. To state the
baseline's contents correctly (F1): `BT=y` (part of the proven Aug-4-booted
baseline, orthogonal to the USB observation); NVMe, `SPMI_APPLE`,
`PWM_APPLE` and `NVMEM_APPLE_SPMI` are all `=m` — compiled as modules,
**absent from the Image** (0 System.map symbols each), and unloadable in
these images. Inert at runtime because the controllers cannot enter the
running kernel, not because the subsystems are unbuilt (`SPMI=y`, `PWM=y`,
`RTC_DRV_MACSMC=y` cores are in).

### DTB for the re-run

My build regenerated `t6040-j614s-dcuart-wifi-usb2-native-right.dtb` →
`6df8af393c43…` (the Aug-4 run's pinned `934dd7b2…` bytes are gone from
disk). Source-level review of the drift: the profile's two USB DTS files
are unchanged since Jul 29; the included `t6040-j614s-dcuart-wifi.dts`
gained 44 lines (SPMI RTC node, keyboard-backlight pwm-leds, internal NVMe
node — the daily-driver v2/v3 work), and the delta contains **zero**
`usb|dwc3|atcphy|phy` tokens. Under this image's config every one of those
new nodes is inert at runtime: their controllers (`SPMI_APPLE`,
`PWM_APPLE`, `NVME_APPLE`, `NVMEM_APPLE_SPMI`) are `=m`, absent from the
Image (0 System.map symbols, verified in the binary review), and these
images cannot load modules — so no Apple SPMI bus ever instantiates and
the nodes cannot probe. Pin for the re-run: `6df8af39…`.

## Artifacts — buildB/buildC are the deliverable; buildA is disqualified

| Artifact | SHA-256 |
|---|---|
| **`Image-usb2-native-right-v2phy.buildB`** (56,068,608 B) | `802483060f217250aa764d6cd97c627aec3ecf935dd12e4161e49ec3f709a5be` |
| **`System.map-usb2-native-right-v2phy.buildB`** | `793adc56118fd28c43cc310b28e0db3a9130ae4c664364cb730a51c3e98d2359` |
| **`config-usb2-native-right-v2phy.buildB`** | `221666c6d31eefe44c7d15e83400e04f37567a32d617b0b795ccb5eed809e543` (= Jul-29 pin, byte-identical) |
| `t6040-j614s-dcuart-wifi-usb2-native-right.dtb` (regenerated) | `6df8af393c43c4a5…` (full hash pinned in ticket 303) |
| PHY slice patch v2 | `b7f02c3cb06b0ed6e490d473a2efd99f61b8cd1ab089a0a09f72ecdec7b60a30` |
| `Image-usb2-native-right-v2phy.buildA` — **tainted, kept for the record** | `88e064d5e42fe43af28cb7433392543ee25b5a7b9849b5339600ae19509e4afa` |

Note on identity: v2 adds no new kernel string (the delta is a constant and
a comment), so v1-vs-v2 binaries are distinguished by hash and by this
provenance chain, not by a strings marker. The `.config` equality with the
pin plus the applied-patch hash carry the identification.

## Reproducibility — the two-build protocol caught a real stale object

Build A ran in `/build/linux-usb2v2-fa`, a dir **reused** from the aborted
current-script attempt; build B in the virgin `/build/linux-usb2v2-fb`.

**A vs B: 21 bytes differ.** One code byte inside
`brcmf_inform_bss.isra.0` (+0x31) and the 20-byte build ID that follows from
any input change. System.map and config are byte-identical, so the layout is
the same and exactly one function body differs.

Mechanism, with the aligned facts: the aborted first run used the *current*
kbuild script, which applies `t6040-brcmfmac-bss-info-v116.patch` whenever
the file exists in `$OUT`; the Jul-29 script never references it (0
matches). `git reset --hard` reverts the patched source, but `git clean
-qfd` does **not** remove gitignored files — build objects survive — and one
brcmfmac object escaped recompilation. Build A therefore carries one
v116-influenced byte; pristine cfg80211 (build B) is what the Jul-29
baseline had. Build A is disqualified on protocol regardless of mechanism.

**Build C** ran in a third virgin dir (`/build/linux-usb2v2-fc`) so the
reproducibility pair is fresh-vs-fresh. (Its first attempt failed on a full
container disk — the tainted `fa` and partial `fc` trees were removed, my
own dirs only, and the run repeated.)

**Build C result: Image, System.map and config all byte-identical to
build B.** The candidate is reproduced fresh-vs-fresh:

```text
80248306…  Image-usb2-native-right-v2phy.{buildB,buildC}   56,068,608 B
793adc56…  System.map-usb2-native-right-v2phy.{buildB,buildC}
221666c6…  config — byte-identical to the pinned Jul-29 baseline
```

Preflight (`t6040-image-preflight.sh`) passes on the candidate with the run
bootargs and `initramfs-sdroot-hardened.cpio.gz` (keymap, kernel markers,
console ordering, `maxcpus=1`). Container build dirs `fa`/`fc` were removed
after artifact extraction (re-derivable: script `@11f2547`, flags, patches
and tree state all pinned here); `fb` is retained for the binary reviewer.

Rule for the recipe: **never reuse a build dir across kbuild script
versions** — `git clean -qfd` leaves ignored build objects, and a patch-set
change between runs can leave stale objects that survive make's dependency
check. A reused dir is fine within one script/patch-set; across versions,
start virgin.

## For the 108 re-run (claude, or whoever takes the rig)

- `IMAGE=Image-usb2-native-right-v2phy.buildB`
  with `t6040-j614s-dcuart-wifi-usb2-native-right.dtb` (`6df8af39…`) and
  `initramfs-sdroot-hardened.cpio.gz`, `maxcpus=1` — same fixture as the
  Aug-4 run, kernel swapped. Do not boot buildA; it is the tainted
  incremental build kept only for the record.
- Binary exact-review must be done by a non-builder (fable built; claude or
  CJ reviews) per COORDINATION.
- Expectation unchanged from the v2 review: xHCI root hubs restored; a
  child on the bus-powered S128 stick only if VBUS is already live (the R0
  read, ticket 229, remains the attended way to know).
