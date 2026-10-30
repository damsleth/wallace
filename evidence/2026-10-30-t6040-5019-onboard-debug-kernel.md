# 5019: onboard debug kernel, built on the Mac from a reconstructed base (claude, 2026-10-30)

**Result:** standalone object `wallace-5019.build1.bin`, built twice byte-identical,
preflight OK, strict verify PASS. Not booted. Its base is a **reconstruction**, not
`4f2429104009` (CJ, same day: patch- or byte-identity with the M1-only base is not
required, progress is).

## Why a reconstruction

`damsleth/linux` was last pushed 2026-07-14 (`wallace/t6040-bringup` = `e9d2237`). The
M1-only commits, including the two-base NVMe driver, were not reachable. The 6002 audit
saved the M1 working-tree files in `evidence/2026-10-24-upstream-convergence/local-source/`.
Branch `wallace/reconstructed-4f24291` (commit `6d2e54a0d`, local only in
`/Volumes/CaseSensitive/linux`) replaces four files on `e9d2237`: `drivers/nvme/host/apple.c`,
`t6040.dtsi`, `t6040-pmgr.dtsi`, `t6040-j614s.dts`. The diff is saved as
`2026-10-30-t6040-5019-reconstructed-base.patch`.

## Equivalence checks against the 2234baad object (5014)

Recovered from the backed-up `wallace-nvmedesk.build1.bin`: m1n1 `bf4b2462`, kernel gzip
`a0bad4de` (Image `2234baad`), DTB `6d2d3da6`, initramfs `82a86064`.

- **DTB:** the plain nvmeroot DTB built here is `6d2d3da6`, byte-identical.
- **Kernel:** the 2234baad flag set on the reconstructed branch gives an Image of the
  same size, 55,443,968 bytes. brcmfmac and apple-nvme strings match. 4.56 MB of
  55.4 MB differ, nearly all in two data regions (offsets 16 to 20 MiB and 28 to 32 MiB)
  and about 0.4% elsewhere. The version string differs (`g6d2e54a0df87`, not
  `g4f2429104009`). Not explained further; no old System.map or config to compare.
  This is near-equivalence, not identity.

## 5019 build

Flags: the 2234baad set (`DOCKCHANNEL DOCKCHANNEL_NBCON MACSMC HID_TYPE_FIX T6040_PPP WIFI
PCIE CPUFREQ TRACKPAD_FW TRACKPAD_RESET_CONTRACT NVME NVME_IOQ_SIZE NVME_EXFAT NO_KVM`)
plus `T6040_BLE_HID=1` and the new `T6040_ONBOARD_DEBUG=1` (`scripts/t6040-kbuild.sh`;
FTRACE, FUNCTION_TRACER, DYNAMIC_FTRACE, KPROBES, KPROBE_EVENTS, DYNAMIC_DEBUG, IKHEADERS,
PSTORE, PSTORE_RAM, PSTORE_CONSOLE, each asserted `=y` after olddefconfig). The BT
pairing-race patch applied and compiled. Container: `debian:bookworm` (gcc 12.2), run
through `run-build.sh`, never an unquoted flag variable (an earlier round did that under
zsh, dropped every flag and built the wrong branch; those results were discarded).

| artifact | sha256 |
|---|---|
| Image (b1 == b2) | `41f9fdc3 60b536a2 4d4e8f84 a46526c9 2cd1faf3 6cb7d393 0b637781 abc32ef8` |
| kernel gzip member | `2fcc01e1…` |
| DTB `nvmeroot-ramoops` | `1a49d19d…` |
| m1n1 (window-free, from 5014) | `bf4b2462…` |
| initramfs (unchanged, 5014) | `82a86064…` |
| object `wallace-5019.build1.bin` (== build2) | `28127903 fb83ad4a 235eb887 964b21122e2b20d2 492b819dd9883264e652631c`, 33,177,600 B, 2025 pages |

Bootargs unchanged from 5014. Paths: `/Volumes/CaseSensitive/linux-build-out/5019/`.
`t6040-image-preflight.sh` (kernel, initramfs, object, bootargs, m1n1): OK, Norwegian
keymap layers untouched. `t6040-raw-object-verify.py --strict`: PASS.

## DTB: the ramoops region

`dts/t6040-j614s-dcuart-wifi-cpufreq-nvmeroot-ramoops.dts` adds a 2 MiB `no-map` ramoops
node at `0x10300000000` (console 256 KiB, ftrace 256 KiB, records 128 KiB). The address
is derived from recorded values (DRAM `0x10000000000`..`0x105ce7a8000`, kernel loaded
at `0x10008400000`, carveouts at or above the top), **not from a live `/memory`**. The
boot ticket must check `/proc/iomem` and mount pstore before relying on it.

## Not done / limits

- No boot. NVMe-root exposure rules from the 5008 gates apply: tester first (6001
  payload, no writes), then the NVMe root.
- The kernel is bigger (73.9 MB Image, 25 MB gzip); the object is 33 MB, well under
  the enrolled-object ceiling measured so far.
- The reconstructed branch is not pushed anywhere. `e9d2237` is the only GitHub base.
