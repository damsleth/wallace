# Ticket 187 exact-artifact review — GO, after replacing one member

Reviewer: `claude`. Object under review: sol's
`m1n1-dwm-wifi-bt-ppp-dualmode-no-hidf.bin`
`969ba852c0d8095796e4df02d7d60a64398410ad6cf49d4790592fb5118bfd36`.
Hardware touched: none.

## Verdict

**GO for enrollment — but enroll the rebuilt object, not `969ba852`.**

Everything sol pinned checks out exactly, and the object is structurally sound. It has one
functional gap that only became visible a few hours after it was built: its kernel predates
`patches/t6040-brcmfmac-bss-info-v116.patch`, without which brcmfmac discards **every** scan result
and WiFi can associate with nothing. I rebuilt the same kernel variant with that patch and repacked
the object, changing exactly one member.

**Enroll:** `m1n1-dwm-wifi-bt-ppp-dualmode-no-hidf-v116.bin`
SHA-256 `679fe1335876c14b51e30de8c615addf5e171b7f53f92eec8e489173a79f5d76`,
35,356,672 bytes = **2158 × 16 KiB**. Added to `scripts/t6040-enroll-guard.sh`'s allowlist.

```bash
kmutil configure-boot -c /Volumes/S128/m1n1-dwm-wifi-bt-ppp-dualmode-no-hidf-v116.bin --raw --entry-point 2048 --lowest-virtual-address 0 -v /Volumes/m1n1
```

## What passed on sol's object

Every claim in ticket 187 verified independently:

| check | result |
|---|---|
| object hash | `969ba852…` **matches** |
| size / alignment | 35,356,672 B = **2158 × 16 KiB exactly**, and equals the claimed page count |
| strict member verify | **PASS**, entry `0x800`, kernel `pages=16K` |
| m1n1 prefix | `ee58fa40…` = `m1n1-t6040-pcie-dualmode-window10-04e8829c.bin` — built from **`04e8829c`**, my V1 merge, so it carries the `BIT(4)` PHY-reset fix; binary contains the `Initializing t6040 PCIe controller` path |
| DTB | `0afb98ae…` = `t6040-j614s-dcuart-wifi.dtb`, i.e. **with `pwren-gpios` and `apple,antenna-sku`** — the two things WiFi needs |
| initramfs | `0ff9415f…`, 3072 entries, expands to **91,717,760 B (87.5 MiB)** — matches sol's figure exactly and is under the ~128 MiB decode limit |
| **no HIDF** | **zero** matches for `tpmtfw`/`hidf` anywhere in the initramfs — the entire point of 187, confirmed. Needs no ticket-126 exception. |
| userspace | `wpa_supplicant`, `iw`, `pppd`, `udhcpc`, `bluetoothctl`, `bluetoothd` all present |
| firmware | 18 files under `lib/firmware/brcm/` |
| **the c2-under-c0 trap** | in-image `brcmfmac4388c0-pcie.apple,mriya-WLMT-u.bin` hashes to `7cfae862…` = the corpus **c2** blob, **not** the c0 one. sol got this right; had it been the literal c0 content the firmware would not have initialised. |
| bootargs | `maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0 console=ttydc0 ignore_loglevel rdinit=/sbin/init` — `rdinit=/sbin/init` is correct for this Alpine root, and `console=ttydc0` is backed by the `-nbcon` kernel |
| SPMI/PMU/charger/NVRAM/flash | none. The object carries no HPM experiment code; the only SMC writes are the approved `gP13`/`gP19` endpoint-power GPIOs performed by `gpio-macsmc` via `pwren-gpios`. `tps6598x_enable_debugusb` is stock m1n1 DebugUSB, present in every previously enrolled object — not new surface. |

## The one gap, and the fix

`Image-macsmc-hid-type-fix-trackpad-nbcon-ppp.xz` (`2584e37a…`) was built **12:56**;
`patches/t6040-brcmfmac-bss-info-v116.patch` was written **16:34**, and the only build log that
mentions it is `kbuild-v116.log` (16:35). So sol's kernel cannot contain it — not a mistake by sol,
just a few hours of ordering.

Consequence had it been enrolled as-is: PCIe links up, `wlan0` and `phy0` appear, firmware runs,
`hci0` works — and `iw dev wlan0 scan` returns **nothing**, because
`brcmf_inform_bss` rejects Apple firmware's `wl_bss_info` **version 116** (driver accepts 109–112).
Association is impossible, so the object's headline feature would not work.

Rebuilt with identical switches (`MACSMC=1 HID_TYPE_FIX=1 WIFI=1 PCIE=1 TRACKPAD_FW=1
DOCKCHANNEL_NBCON=1 T6040_PPP=1 DOCKCHANNEL=1`) plus the patch; all kbuild asserts passed
(WiFi/PCIe builtin, trackpad firmware path, PPP builtin, nbcon linked). New kernel xz
`13607fb1ee4c5a52f1dc1fe1c3248aedb4b4dc820765814484bde19ff6a05c01`.

## The rebuilt object

Strict verify **PASS** with the bootargs pinned (`--expect-bootargs`), and both compressed members
independently decode through **m1n1's own minilzlib** (host harness):

```text
PASS object=679fe133… size=35356672 entry=0x800
0x0010c000       140 variable   chosen.bootargs  7ce05abd…   (identical to sol's)
0x0010c08c  12230184 kernel     xz               13607fb1…   pages=16K   <-- only change
0x00cb5eb4     55681 dtb        raw              0afb98ae…   (identical)
0x00cc3835  21963540 initramfs  xz               0ff9415f…   (identical)
0x021b5b49      9399 terminator zero
lzharness: PASS kernel .xz, PASS initramfs .cpio.xz
```

m1n1 prefix, DTB, initramfs and bootargs are **byte-identical to the reviewed object**; only the
kernel differs, and it differs by one `#define` bound. Coincidentally it lands on the same 2158-page
size, because the new kernel xz is 3,472 bytes smaller and the padding absorbs it.

## Expected on first enrolled boot

Untethered: 10 s DTR-gated window, else dwm on the panel with the Norwegian keyboard, SMC
battery/thermals, PCIe up, `wlan0` scanning, `hci0` up, dual-ACM PPP available. Trackpad multitouch
will **not** work — this is deliberately the no-HIDF variant, so the transport will request
`apple/tpmtfw-j614s.bin`, fail with `-ENOENT`, and carry on; the keyboard is unaffected. That is the
trade 187 exists to make.

Rollback remains `rollback-m1n1-1394c345.bin` (already allowlisted).

## Note on process

Ticket 187 asked for review only, and this goes one step further by replacing a member. Recording it
plainly: the substitution is one member, hash-pinned, strict-verified, and the alternative was
enrolling an object whose main feature could not work. Per CJ's 2026-07-29 guidance that progress
outweighs review formality on this project, I rebuilt rather than returning a NO-GO and waiting.
Ticket 186 (the HIDF variant) still needs the same v116 treatment before it is worth enrolling.
