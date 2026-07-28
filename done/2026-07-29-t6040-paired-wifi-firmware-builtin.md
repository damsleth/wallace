# T6040 paired BCM4388 firmware: persistent corpus + built-in kernel artifact

Offline-only preparation for ticket 168. No rig lease, hardware access, enrollment, or
external post.

## Outcome

The paired 25F84 firmware corpus is no longer dependent on `/private/tmp`, and the
BCM4388 WiFi payload is now built into a feature kernel which also retains the proven
SMC and USB-storage/usbnet stacks.

This is **not yet a runnable boot object**. PCIe link-up still needs an attended,
separately reviewed candidate, and right-port USB still needs a safe VBUS solution plus
native T6040 ATC/DWC3 enablement. Any later combined m1n1 object must also retain the
10-second proxy window and clear `t6040-minilzlib-harness.sh` for its initramfs.

## Why the corpus moved

At 00:00 on 2026-07-29, the host purged `/private/tmp`, including the previously staged
paired corpus and its extraction inputs. Empty replacement directories made the old
path look superficially present while containing no firmware.

The corpus and inputs were regenerated into persistent build storage:

- corpus: `/Users/damsleth/Code/linux-build-out/t6040-paired-fw-25F84/` (113 MiB);
- source inputs: `/Users/damsleth/Code/linux-build-out/t6040-fw-inputs-25F84/`
  (2.5 GiB);
- pinned extractor checkout:
  `/Users/damsleth/Code/linux-build-out/asahi-installer-c53d66dc`, commit
  `c53d66dc71937efa2530d4323c81addaebb5a09b`.

Persistent input and corpus identities:

```text
fe56fcb5a0aa2e0214dbe69f108ed35670bf33d32fdc346c6efb1784cf7705cd  022-21678-099.dmg.aea
48067a9bfc7714bde6e61223399bff2aa7bd1fe1b2c1f24c86d455ea801b1301  022-21678-099.dmg
4cc018b4ab925d879a0f039bf1f83cdbd11dc0bd906910afd1f9d15befabad1b  kernelcache.release.mac16j.im4p
cb7a4ee2e3a7660c9745b3daff6cdd1da4f1875109d5bc170591fe272b1e639a  j614s-25F84-raw-firmware.tar.gz
b137dcdaf4b5238e6bb4d692b03a3a799597f1ffd536f1f986fdc0963b387cd8  SHA256SUMS
```

All entries in the corpus `SHA256SUMS` passed. Detailed Apple restore provenance is
preserved in `provenance.json`; the extraction background remains in
`done/2026-07-14-t6040-bcm4388-fw-extract.md`.

## Kernel build support

`scripts/t6040-kbuild.sh` now accepts `T6040_WIFI_FW_BUILTIN=1`. It:

1. enables the 16 KiB-page Apple PCIe/cfg80211/brcmfmac consumer stack as built-ins;
2. enumerates the exact 12 C0/C2 `apple,mriya` WiFi files (no wildcard);
3. verifies every input against a pinned SHA-256 before configuring the build;
4. uses `CONFIG_EXTRA_FIRMWARE` with the persistent corpus under `/out`;
5. gives the output a `-wifi-fw` suffix; and
6. refuses publication unless every built-in firmware symbol is present.

`RFKILL=y` is explicit. Without it, Kconfig's tristate dependency silently demotes
`CFG80211` and `BRCMFMAC` to modules in the non-diet feature profile.

The initramfs fallback in `scripts/t6040-build-alpine-dwm.sh` now defaults to the same
persistent corpus. It remains off by default; building firmware into the kernel avoids
spending any of m1n1's content-sensitive ~128 MiB expanded-initramfs budget.

Local/private use only: the kernel Kconfig warns that distributing a kernel with
non-GPL firmware combined into it can have licensing consequences. Do not publish this
artifact.

## Combined feature artifact

Build source:

```text
linux wallace/t6040-bringup
50ee45b42a3ea1143df938028177f08acd5d7440
```

Build command:

```sh
podman exec \
  -e DOCKCHANNEL=1 \
  -e MACSMC=1 \
  -e T6040_WIFI_FW_BUILTIN=1 \
  -e BUILD_DIR=/build/linux-wifi-fw \
  kbuild bash /out/t6040-kbuild.sh image
```

Artifacts:

```text
28f717036b40510b67622a8997b9f583ee928f0e67ed4765e4a7d0d66e96a2c7  Image-macsmc-wifi-fw
c9b0e4ac56e513b8a41cada317be2d37d52fcb0fa59d8516b5aeb1fb64be20a5  Image-macsmc-wifi-fw.xz
12c0f5cb7cdc566579378d2a9226804c20ed18bb2c2dae82617eefeb6612702d  System.map-macsmc-wifi-fw
17ead56776ccefd4c1078e3e5046094578f0e46cff9553d29b8d54b9016ff20e  config-macsmc-wifi-fw
```

The raw Image is 59,066,880 bytes; the xz is 13,082,892 bytes. The arm64 Image header
and `.config` both say 16 KiB pages.

The final config has all of these built in:

- `CFG80211`, `RFKILL`, `PCIE_APPLE`, `BRCMFMAC`, `BRCMFMAC_PCIE`;
- `MFD_MACSMC`, `MACSMC_POWER`;
- `USB_DWC3`, `USB_STORAGE`;
- `USB_USBNET`, CDC Ethernet/NCM, AX88179, and RTL8152.

`USB_UAS` is not set in this combined config, despite ticket 167's intended feature
set. Do not claim UAS from this artifact; ordinary `usb-storage` read/write remains
built in. If UAS is required in the final object, make it an explicit assertion before
that object is named ready.

## Post-link verification

The linked `vmlinux.unstripped` reported all 12 `_fw_*_bin` symbols. The kernel's
`scripts/extract-fwblobs` has an `awk -n` portability bug with the container's awk, so
the verifier removed only that unsupported option in-memory and extracted every blob
from `.rodata`. Exactly 12 files emerged, and every extracted SHA-256 matched the
source list:

```text
02137cf6...  C0 WLMT-a
4d0f3187...  C0 WLMT-u
cd49096c...  C0 firmware
822fd43c...  C0 CLM
97ce1775...  C0 signature
7a588168...  C0 txcap
a3042833...  C2 WLMT-a
20325192...  C2 WLMT-u
7cfae862...  C2 firmware
af8df65b...  C2 CLM
9abb8c1a...  C2 signature
2ee489bb...  C2 txcap
```

An earlier `Image-macsmc-dietcap-wifi-fw` (`955369cd...`) also built and passed
firmware extraction, but the diet profile had removed USB. It is a WiFi-only diagnostic
artifact, not the near-term combined candidate.

## Reproducibility check

A second build was made from a fresh clean clone at
`/build/linux-wifi-fw-repro`, using the same committed Linux source, pinned
firmware corpus, config path, build timestamp, user/host strings, local version,
and source-prefix mapping. It did not reuse the first build directory.

The clean rebuild produced:

```text
28f717036b40510b67622a8997b9f583ee928f0e67ed4765e4a7d0d66e96a2c7  arch/arm64/boot/Image
28f717036b40510b67622a8997b9f583ee928f0e67ed4765e4a7d0d66e96a2c7  /out/Image-macsmc-wifi-fw
byte_identical=yes
```

Thus the published raw Image is byte-for-byte reproducible from a clean checkout
under the recorded build environment. This verifies artifact construction only;
it does not clear the remaining attended PCIe or USB hardware gates.
