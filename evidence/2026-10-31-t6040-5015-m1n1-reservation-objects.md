# 5015: m1n1 reservation variants built on the M4, three objects (claude, 2026-10-31)

**Result:** the 5015 m1n1 patch series (0001–0006) builds on `damsleth/m1n1`, and three standalone
objects exist. They are the enrolled 5019 object with **only the m1n1 stage changed** (kernel, DTB,
initramfs and bootargs are 5019's bytes: the DTB `1a49d19d…`, the initramfs `82a86064…`, the
kernel gzip `2fcc01e1…`, bootargs `maxcpus=1 idle=nop …`). Each was built twice byte-identical,
passes `t6040-raw-object-verify.py --strict`, and passes `t6040-image-preflight.sh` (window-free).
None has been enrolled or booted.

| object | m1n1 patches | what it adds | object sha256 | m1n1.bin sha256 |
|---|---|---|---|---|
| ~~5015a~~ | 0001–0004 | superseded (moved to `/mnt/sd/superseded-20261031/`): still had the over-copying reads fixed by 0007 | `622e8de1…` | `b148f2eb…` |
| `/mnt/sd/wallace-5015b/wallace-5015b.build1.bin` | 0001–0005, 0007 | CTRR_C range, TrustCache, SEP/coprocessor chain reservations, length-checked reads | `b1b550f30a89ef4e0c3511d43ce2cd36d7fba6b96ab52d81b38a2c9d7a866bc1` | `af53700904a38882…` |
| `/mnt/sd/wallace-5015c/wallace-5015c.build1.bin` | 0001–0005, 0007, 0006 | B + start bit from the PMGR clusters table | `9bee06bef2b1d925a591eada8a8dfb5b1fea379cdeb0533853b7308917497a5d` | `7de7777108fa3940…` |

Each directory has `SHA256SUMS`, `m1n1.bin`, `m1n1.elf`, `Image.gz` and `bootargs.txt`. **B is the
recommended first boot.** The first versions of A, B and C (built before the review below) are in
`/mnt/sd/superseded-20261031/` with a README; do not enroll them, and delete them when convenient.

## Source and toolchain

- Source: `damsleth/m1n1` `main` `214f93d` (PR #1 merged; `80badc91` is now reachable, which
  unblocked this). Patches from `patches/m1n1-ctrr-c-v1/`. 0001–0004 apply cleanly to both
  `80badc91` and `main` (`git am`, checked). Branches in the tmpfs clone: `wallace-5015` (0001–0005 and 0007),
  `wallace-5015-0006`.
- Built **natively on the M4** in the bookworm chroot: gcc 12.2.0 (Debian), `rustc 1.99.1` stable
  from `rustup-init` (sha256 checked against `static.rust-lang.org`'s published hash) with target
  `aarch64-unknown-none-softfloat`. Command: `make -j1 TOOLCHAIN= ARCH= USE_CLANG=0
  M1N1_VERSION_TAG=<tag>`, plain defaults (no `RELEASE`, no `CHAINLOADING`), which leaves
  `EARLY_PROXY_TIMEOUT` undefined, so the build is window-free: no "Waiting for proxy connection"
  string in any variant. Version tags: `v1.6.0-wallace-80badc91-5015<b|c>-…-gcc12`.
- **Not byte-comparable to the enrolled m1n1** (`bf4b2462…`, 1,097,728 B): that was built on the
  Mac with clang/LLVM (`$llvm_bin` in `scripts/t6040-build-hpm2-candidates.sh`) and flags that are
  **not recorded in the repo**. These builds are 1,114,112 B (16 KiB aligned). The objects are
  therefore 16 KiB larger than 5019's (33,193,984 B for A, vs 33,177,600 B). A same-toolchain
  baseline (`80badc91` unpatched, gcc) and the patched build differ only in `kboot_prepare_dt` growing
  by 288 B and in gcc's inlining choices for two static functions (`dt_set_sep`,
  `dt_set_sio_fwdata` swap between inlined and emitted); the source diff is exactly three files,
  160 insertions. If CJ prefers the Mac toolchain, `git am` the same patches on `~/code/m1n1` and
  build with the flags used for `bf4b2462`. Recording those flags would close the gap.

## Independent review and 0007

A fresh subagent was given only the code (no conclusions) and reviewed 0004-0006 against m1n1's ADT helpers
and the ADT dump. Findings and what was done:

- **Real, latent: `ADT_GETPROP_ARRAY` over-copies.** It expands to `adt_getprop_copy(..., sizeof(arr))`,
  whose Rust implementation (`rust/src/adt.rs`) calls `copy_raw` (copies the property's full size into
  the buffer) and only then compares the length. Verified in the source here. A memory-map entry over
  16 bytes would overrun the `u64[2]` stack buffers in the TrustCache (0004) and chain (0005) reads. It
  can't trigger on J614s (every entry is 16 bytes, including the all-ones ones). **Fixed in 0007**: one
  helper reads with `adt_getprop` and checks `len == 16` before `memcpy`, rejects empty, all-ones and
  wrapping entries, and one table drives TrustCache and the chain. `dt_set_sep` has the same pre-existing
  pattern; left alone (not ours).
- **Hardening: address overflow and reversed ranges.** `base + size` wraps and an aligned end below the
  start were not rejected. Both are now (0007).
- **0006: no bound on `bitpos + core`.** `1u << bit` is undefined for bit ≥ 32. 0006 now falls back to the
  old formula for bit ≥ 32. Real values peak at 14.
- **Checked, nothing wrong:** FDT headroom (96 KiB vs about 112 bytes), initialisation order (`adt` and
  `cpu_features` are set before `kboot_prepare_dt`), `-mstrict-align` (the 0006 read uses `memcpy`),
  `adt_getprop` use, and that the ADT dump matches the code (clusters `[4, 262150, 655366]`, region sizes
  16 KiB aligned, RTBuddySeg/SEPFW/SEPPatches contiguous, `TrustCache-*` all-ones entries are never read).
- **Not a defect, scope:** `DeviceTree` (0x94000, already reserved as the `adt` phram node) and
  `BootKC-rw` (m1n1 and its payload slot) are not reserved by these patches. The stop-path bit layout is
  an assumption (the same helper is used on both paths).
- Pre-existing and left alone: the `WARNING: M4+ SMP-RO` printf in the CTRR block lacks a trailing newline.

After 0007 the series is applied as 0001–0005, 0007, then optionally 0006 (they touch different files).
B and C were rebuilt from the amended series; each was built twice identical, strict-verified and
preflighted again.

## What each patch does, and why

- **0004 (TrustCache).** The ADT memory-map names `[adt_end, adt_end + 0x60000)` as TrustCache. It is
  the 384 KiB between the ADT end and the m1n1 base on every recorded boot, and it is where 205's
  first fault always lands. Gate check done: `features_m4` does not set `apple_sysregs_unlocked`, and
  T6040's cores (Brava Chop E/P) map to `features_m4`, so the block runs on J614s.
- **0005 (SEP/coprocessor chain).** Same memory-map, same kind of region. In the 2026-07-28 ADT dump
  iBoot lays out a contiguous chain: DeviceTree → TrustCache → BootKC slot (m1n1 + payload live here)
  → RTBuddySeg `+0x9C000` → SEPFW `+0x574000` → SEPPatches `+0xC000` → uStuff `+0x4000` → preoslog
  `+0x40000` → BootArgs `+0x4000`. m1n1 declares usable RAM as `[phys_base, phys_base + mem_size]`,
  which spans all of it. `dt_set_sep()` is the only code that reserves SEPFW and returns early when the
  DT has no `sep` alias (J614s has none), so none of these is reserved today. **This is hygiene, not a
  fix for 205** (wallace-rex): 205's oops is ESR `0x9600004f`, a level-3 *permission* fault, the CTRR
  signature, whereas a memory-controller or TZ carve-out violation would be an external abort or
  SError. For the July-29 second fault (`0x10006724f90`) the chain doesn't contain it unless the boot
  object was 1.4–6.9 MiB, and that boot was the rollback loader; it is undecided. A reserved
  `preoslog` also stays intact for later reading.
- **0006 (PMGR clusters-table start bit).** From wallace-rex's ADT reading: PMGR `clusters` =
  `[4, 0x40006, 0xa0006]` = {ncores 4 @ bit 0, 6 @ 4, 6 @ 10}; each P cluster has core 5 fused off.
  m1n1's `1 << (4 * cluster + core)` is right for E and P0 but sets bits 8..12 for the five P1 cores
  where macOS sets 10..14: P1 core 0 aliases P0 core 4 and core 1 hits P0's harvested bit 9. m1n1's own
  comment on that write says "Without this, IRQs don't work", so this is not obviously harmless. 0006
  reads `/arm-io/pmgr` `clusters` and uses `bitpos + core`, falling back to the old formula on
  chips with unlocked sysregs, when the table is missing or short, or when a non-zero cluster has a zero
  bitpos. It also applies to the stop path. **Logic test** (a standalone harness with the function body
  and the real table): clusters 0 and 1 unchanged, cluster 2 `8..12 → 10..14`, all three fallbacks return
  the legacy bit. It is optional and separate, because its effect needs P1 cores to run (`maxcpus ≥ 10`).
  What `+0x4` does in hardware is unknown.

## What macOS does with these regions after boot (wallace-rex, 2026-10-31)

- **DeviceTree:** read at boot to build the registry, then walked in place and read-only at run time.
- **TrustCache:** read at boot and again by the run-time trust-cache query path; never written or freed.
  It must stay reserved (CTRR).
- **BootKC:** on macOS it is the kernel itself. Linux needs none of these regions for function; reserving
  them is protection only. The ADT region is already reserved. Reserving the rest of the BootKC slot beyond
  m1n1 and its payload only matters if CTRR_D covers part of it, and 5015 step 2's D read decides that.
  **Keep that hypothesis soft:** the enrolled object is `--raw`, so iBoot has no Mach-O segments to derive a
  const range from. Reserving the whole slot is cheap but is not evidence-driven yet.
- **preoslog:** mapped on demand by the kernel via the loader-info lookup and only read; iBoot writes its
  own pre-OS log there (macOS exposes it as `kern.preoslog`). Nothing in the kernel writes it, so keeping it
  reserved (0005) leaves iBoot's log readable later (a ring with a header; decode TBD).

## How to check a boot of B (read-only, no rig action needed beyond booting it)

On the booted M4: `perl scripts/t6040-fdt-memreserve.pl` (this change). On the current 5019 boot it
reports 16 entries and `TrustCache gap [0x10004220000, 0x10004280000): NOT reserved`. A boot of B must
instead show `RESERVED`, plus new entries for the TrustCache range, RTBuddySeg, SEPFW, SEPPatches,
uStuff, preoslog and BootArgs. Also compare `/proc/iomem` (the same ranges show as `reserved`), and
check that everything 5020 checked still passes (desktop, Wi-Fi, BLE, pstore). For C, whether all 14
cores still start is visible in m1n1's log line per CPU ("Starting CPU n … Started"), which needs the
m1n1 log (5027's phram MTD, or DebugUSB) rather than anything in the running system today.

## Risks

- m1n1 is the first stage: a build that does not boot means that entry does not come up. Rollback is
  the other boot volume (the m1n1 DebugUSB rollback) or re-enrolling 5019 (`28127903…`).
- First m1n1 here built by a different compiler than every earlier enrolled one (see above).
- 0004/0005 call `fdt_add_mem_rsv()` more times; the FDT buffer has 96 KiB headroom
  (`dt_bufsize += 6 * SZ_16K`), and each entry is 16 bytes.
- Step 3 of 5015 (SMP trial) must still use the 217 cow-report RAM-root harness, not the NVMe root:
  those artifacts are on the Mac. These m1n1 binaries can be dropped into that harness.
