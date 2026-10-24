# Ticket 5002 / 305 run 8 candidate: the "pddiag" PD image, two clean builds, preflight, self-review

Date: 2026-10-25. Builder and reviewer: claude (Mythos Wallace session).
Offline: kbuild container only; no rig, no lease. CJ asked for this build
on 2026-10-25 ("apply the wakeup patch and the readback sketch, two clean
builds, preflight, and write the review evidence. No rig.").

## What the image is

The run-7 "pdwake" image plus exactly two things:

1. **`patches/t6040-spmi-apple-zero-write-encoding.patch`** (`64dcbaf`,
   sha256 `233e99090fcb8760…`), already wired into the repo kbuild under
   `T6040_TYPEC_PD_WAKEUP=1`. Without it every SN201202x register select
   hits register 0 (305 run 7). Reviewed strictly against m1n1
   `raw_command` and the R1 trace: PASS with notes,
   `evidence/2026-10-25-t6040-zero-write-encoding-patch-review.md`.
2. **`patches/t6040-tipd-connector-state-diag.patch`** (new, sha256
   `4bb22141cb9a96d0f90e3750c221f3fe9cc85977da3c405230de7de6ad287566`),
   applied by the new `T6040_TYPEC_PD_DIAG=1` kbuild switch (nested under
   `T6040_TYPEC_PD_WAKEUP=1`, hard-errors otherwise). It is the §5.3/§6
   diagnostic from `evidence/2026-10-24-t6040-hpm2-source-vbus-re.md`.

The post-WAKEUP settle stays at the m1n1-proven 10 ms (CJ's run-7 note:
raise to Apple's 100 ms only if the first read is flaky).

### The diagnostic patch, exactly

`drivers/usb/typec/tipd/core.c`, +65 lines, no other file:

- New `tps6598x_diag_connector_state(tps, when)`: reads and logs, with
  `dev_info` and the `diag[<when>]:` prefix, STATUS `0x1a` (decoded: plug,
  conn state, port role, data role, VCONN, PP_5V0, PP_HV, power source, VBUS
  status, USB host present), MODE `0x03` (4 B), SYSTEM_POWER_STATE `0x20`
  (1 B), SYSTEM_CONF `0x28` (4 B, PORTINFO), POWER_STATUS `0x3f` (2 B),
  PD_STATUS `0x40` (5 B, port type), DATA_STATUS `0x5f` (4 B), the
  INT_MASK1 `0x16` **read-back** (8 B, against the value written),
  `0x5d` (6 B) and `0x2c` (1 B). Every read goes through the existing
  `tps6598x_block_read` / `read8/16/32/64` helpers; each result is logged
  with its return code so a failed read is visible rather than fatal.
- Called once in `tps6598x_probe_common` right after the mask write and
  the first STATUS read (before `register_port`, so a `-ENODEV` from an
  unexpected PORTINFO still leaves the readings in dmesg), and once in
  `cd321x_interrupt` after the STATUS read on every **non-zero** event
  (the poll handler returns early on zero events, so idle polling logs
  nothing). The raw 8-byte `INT_EVENT1` is logged before the W1C.

**Transaction classes:** reads only. No command, no new write. The only
writes in the image remain the Entry 1 set (`0x16` at probe, `0x18` W1C
per event, `SSPS` to S0 via `0x09`/`0x08`). SPMI_SAFETY class R0 for every
added access; the hpm2-only DT gate is unchanged (same DTB).

## Builds

Flags (identical to the run-7 pdwake pair plus `T6040_TYPEC_PD_DIAG=1`;
clone source is the new local mirror, which the kbuild refuses unless its
head equals `/src`, both `4f2429104009`):

```text
podman exec -e DOCKCHANNEL=1 -e DOCKCHANNEL_NBCON=1 -e HID_TYPE_FIX=1 -e T6040_INTEGRATED=1 \
  -e T6040_PPP=1 -e MACSMC=1 -e WIFI=1 -e PCIE=1 -e USB_HOST=1 -e USB_HOST_PORT=right \
  -e T6040_USB2_NATIVE=1 -e T6040_TYPEC_PD=1 -e T6040_TYPEC_PD_WAKEUP=1 -e T6040_TYPEC_PD_DIAG=1 \
  -e KBUILD_SKIP_DEPS=1 -e KBUILD_CLONE_SRC=/build/linux-mirror.git \
  -e ARTIFACT_SUFFIX=pddiag.build{1,2} -e BUILD_DIR=/build/linux-pddiag-build{1,2} \
  kbuild bash /out/t6040-kbuild-pddiag.sh image
```

`/out/t6040-kbuild-pddiag.sh` (sha256 `c741f8f1c9918e97…`) is a verbatim
copy of `scripts/t6040-kbuild.sh` at `d227605`, staged under its own name
because another agent's build was executing `/out/t6040-kbuild.sh` at the
time (overwriting a running bash script corrupts it). Two earlier attempts
failed at the clone step (container disk full, then a clone cut off during
a disk reorganisation); seven stale July/August build trees were deleted
with CJ's approval before the successful pair.

Patch application order in both logs: 0001 SPMI transport → wakeup+diag
→ zero-write encoding → connector-state diag (`kbuild-pddiag-build1.log`
`a8feef9732b523c5…`, `build2.log` `a745cbdb2a845d45…`).

```text
08de37b12a535c011d988cb935777c00d740c856f907a5ffb8b2392a201d6e17  Image-macsmc-hid-type-fix-nbcon-ppp-usb2-native-right-pddiag.build{1,2}
9166487cccd0866a20d6c95882b383fa5b340539958fb987e5737555d037fe15  System.map-…-pddiag.build{1,2}
51aa40f0df95a6938d7067f107f7b4aa0d614bea6c2c269a4e1b10a9e745b2d1  config-…-pddiag.build{1,2}
```

`cmp` reports Image, System.map and config byte-identical across the two
fresh clones. The config is byte-identical to the run-7 pdwake config and
to the pinned 305 `config-usb2pd.buildA` (`51aa40f0…`): the diagnostic
changes no configuration.

## Markers in the Image (build 1 == build 2)

| String / symbol | Count |
|---|---|
| `diag[%s]: STATUS` | 2 (probe + event sites share the helper; format string appears twice after inlining) |
| `diag[event]: INT_EVENT1` | 1 |
| `INT_MASK1 readback` | 1 |
| `reg 0x5d` | 1 |
| `zero-write to SID` (zero-write reply check) | 1 |
| `WAKEUP to SID` (wakeup reply check) | 1 |
| `after WAKEUP: power-state` (run-7 diag) | 1 |
| `usbc,sn201202x,spmi`, `tps6598x-spmi` | 1 each |
| `pcie-apple` / `macsmc` (preflight controls) | 2 / 17 |
| System.map: `apple_spmi_cmd`, `tps6598x_diag_connector_state` | present (`apple_spmi_zero_write` is inlined into `spmi_write_cmd`; its reply-check string proves the code is in) |

## Preflight

`scripts/t6040-image-preflight.sh --kernel Image-…-pddiag.build1
--initramfs initramfs-sdroot-hardened.cpio.gz --bootargs '<run-7 cmdline>'`:
**preflight: OK** — pcie-apple, macsmc, dockchannel-hid present; Norwegian
keymap present and loaded by `/init`; busybox, `fsck.exfat`, WiFi/BT
firmware present; last console `tty0`, `ttydc0` present, `maxcpus=1`.

## Run-8 fixture (unchanged from run 7 except the Image)

```text
Image        08de37b1…  Image-macsmc-hid-type-fix-nbcon-ppp-usb2-native-right-pddiag.build1
DTB          eaf8cceb…  t6040-j614s-dcuart-usb2-native-right-pd-physfix.buildA.dtb (3009 PASS; hpm2 only, a1 at 0x509198000)
initramfs    4cc65133…  initramfs-sdroot-hardened.cpio.gz
m1n1         7de07c71…  (rollback proxy, chainload)
cmdline      maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=ttydc0 console=tty0
             fbcon=font:TER16x32 ignore_loglevel rdinit=/init
fixture      S128 stick in the RIGHT port before boot; SD card OUT; DebugUSB left-back; CJ attending
             (SPMI_SAFETY: every live SPMI experiment is attended); kisd before macvdmtool.
```

Expected dmesg, in order: `after WAKEUP: power-state read ret=0 state=…`
(no longer `-5`), `diag[probe]: STATUS …` with the decoded fields, the
INT_MASK1 read-back equal to `0x0000000000000602`, `MODE "APP"`, and after
plug/poll `diag[event]: INT_EVENT1 …` lines. Decision table:
`evidence/2026-10-24-t6040-hpm2-source-vbus-re.md` §5.2. Preserve the full
dmesg before any `dmesg -c`.

What a mismatch means: a read-back of `0x16` that differs from the value
written is the first direct test of 8-byte writes through SPMI window
`0x20` (Apple stages writes at `0xa0`); a STATUS with `PLUG_PRESENT=0` and
the stick inserted points at MODE/PORTINFO, not at VBUS policy.

## Review checklist (self-review; independent cross-review requested from Opus Wallace)

- [x] both builds from fresh clones of the same head, byte-identical artifacts
- [x] config unchanged vs the signed-off 305 config
- [x] every added register access is a read; no new command or write class
- [x] hpm2-only DT gate unchanged (same `eaf8cceb` DTB)
- [x] zero-write fix present and independently reviewed
- [x] preflight OK with the pinned initramfs and the run-7 cmdline
- [ ] independent exact-artifact review (not the builder)
- [ ] CJ attendance window for run 8
