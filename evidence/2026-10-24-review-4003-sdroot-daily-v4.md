# Independent review: ticket 4003 SD-root daily v4 (trackpad integrated, ticket 301)

Reviewer: independent (non-builder) offline review, 2026-10-24. No rig, lease,
card, enrollment or boot.

**Verdict: PASS-with-notes.** Hashes, build identity, config union, DT node and
HIDF blob check out. Not boot-tested as a combination (as the note says).

## Findings

- `m1n1-alpine-sdroot-daily-v4.build{1,2}.bin` = `32eac091b1f7…8408`
  (25,886,720 B); Image `a9a2096f…` both builds; System.map `93cfaa38…`;
  config `96e83d85…`; kernel member `69ae3ba7…`; initramfs `f089ffa7…`
  (= daily v3's); DTB `c5c3b4c3…`. The decompressed kernel member hashes to the
  Image `a9a2096f…`. Build1/build2 are byte-identical in every artifact.
- Strict verifier PASS both builds (exact bootargs, entry `0x800`, members as
  above); preflight OK, no FAIL/WARN.
- Config union: `diff` of non-comment lines vs `config-trackpad-reset-contract`
  (the 230 kernel `Image-trackpad-reset-contract`, `80c15f58…`) adds only
  `PPP=y`, `PPPOE_HASH_BITS=4`, `PPP_ASYNC=y`, `SLHC=y` and `CRC_CCITT m→y`
  (a PPP dependency). Against `config-alpine-sdroot-daily-v2.build1` it changes
  only `HID_MULTITOUCH m→y` and adds `HID_MAGICMOUSE=y`. As claimed. It is also
  identical to the pre-existing `config-…-trackpad-nbcon-ppp-cpufreq`.
- DT: `hid@514600000` (compatible `apple,t8122-dockchannel-hid`, `status=okay`,
  `keyboard`, `multi-touch { firmware-name = "apple/tpmtfw-j614s.bin"; }`).
  I resolved phandles to node paths in both `t6040-j614s-dcuart-wifi-cpufreq-sdroot.build1.dtb`
  and the 230 fixture `t6040-j614s-dcuart.dtb` (`30b01736…`): the three HID
  nodes' properties (reg, mboxes, iommus, firmware-name) are identical. ANS/NVMe,
  SPMI, `smc_rtc`, `smc_reboot` disabled (see ticket 5000 review).
- HIDF blob in the initramfs `lib/firmware/apple/tpmtfw-j614s.bin` = `a1f4131d…`
  (79,960 B); `/init` and `/shutdown` = the 3006-tested hashes.
- Kernel strings (`strings -a`) for the Image match the 230 Image on the probed
  counts (`firmware-name`, `apple,t8122-dockchannel-hid`, `multi-touch`); PPP
  strings present, `pcie-apple` present. `build1-patches-and-asserts.txt` lists
  16 patches applied OK and all six assertion headings.

## How it could be wrong

1. *Config contains something outside the claim.* Ruled out by the diffs above.
2. *kbuild script hash.* Evidence cites `de179323…`. The current
   `scripts/t6040-kbuild.sh` is `0e347c41…` (commit f430d1f added an opt-in
   `T6040_TYPEC_PD_WAKEUP` block under `T6040_TYPEC_PD`). `de179323…` is exactly
   the blob at 59e80f8, so the cited hash is a historical commit's; the later
   diff is flag-gated and the 301 build log lists no SPMI/tipd patch. Ruled out
   for the artifact, but a rebuild must use 59e80f8 or the same flags only.
3. *Trackpad+PPP+SD-root combination untested.* True and unmitigated offline.
4. *Firmware load after switch_root.* The HIDF blob is only in the initramfs;
   if the HID driver requests it after the SD root replaces `/`, the request
   fails. Cannot be settled offline; 301's boot check (touch, haptic) covers it.

## Notes

- The stale unsuffixed `Image-…-cpufreq` (`43e1a7d4…`) is a different, older
  artifact from the same tree; do not confuse it with `…-daily301.buildN`.

## Commands run

```text
shasum -a 256 Image-…-daily301.build{1,2} System.map-…build{1,2} config-…build{1,2} Image-alpine-sdroot-daily-v4.raw-object.build{1,2}.gz m1n1-alpine-sdroot-daily-v4.build{1,2}.bin
gunzip -c Image-alpine-sdroot-daily-v4.raw-object.build1.gz | shasum -a 256
diff <(grep -v '^#' config-A|grep .) <(grep -v '^#' config-…daily301.build1|grep .)   # vs trackpad-reset-contract, daily-v2, trackpad-nbcon-ppp(-cpufreq)
python3 scripts/t6040-raw-object-verify.py --strict …   # x2
scripts/t6040-image-preflight.sh --kernel Image-…daily301.build1 --initramfs initramfs-sdroot-daily-v3.build1.cpio.gz --object … --bootargs '…' --m1n1 m1n1-sdroot-hardened.bin
dtc -I dtb -O dts … ; phandle-resolving python comparison of hid@514600000 vs t6040-j614s-dcuart.dtb
cmp m1n1-alpine-sdroot-daily-v{3,4}.build1.bin; strings -a Image | grep -c …
git log/show for scripts/t6040-kbuild.sh across commits; git diff 59e80f8 f430d1f -- scripts/t6040-kbuild.sh
```
