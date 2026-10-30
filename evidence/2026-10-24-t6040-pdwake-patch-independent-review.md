# Independent review: SPMI WAKEUP command + tipd probe diagnostics (commit f430d1f)

Reviewer: independent session (did not author the change). Offline source
reading only: no rig, no lease, no build, no boot. Date: 2026-10-24.

## Verdict: PASS-with-notes

No must-fix items. The author's root-cause claim is confirmed from source.
The patch is confined to a single new bare command (WAKEUP, opcode 0x13) and
probe-time logging, stays inside SPMI_SAFETY Entry 1, applies cleanly on top of
the reviewed 0001 transport patch at 4f24291, and the kbuild gating is correct.
The notes below are observations for the attended run and for a later
upstream-shaped cleanup, not blockers.

## Objects reviewed

```text
25a8b50de9c553ac499dd3e6e16626722ed65325afbc940a2b3cd796338e21cb  patches/t6040-spmi-wakeup-and-tipd-probe-diag.patch
0e347c41d0e5d2ff04e2cb0dda8713918ebcfdc13564344af98cebedd83a279b  scripts/t6040-kbuild.sh
9dcb4606e6385815dafa29f2690cf5cc29021d07387da78b55a09d4385b28350  patches/0001-usb-typec-tps6598x-add-SPMI-transport-for-T6040-SN20.patch (77fd00b)
```

Hashes match commit f430d1f and the copies staged in `~/code/linux-build-out/`
(`t6040-spmi-wakeup-and-tipd-probe-diag.patch`, `t6040-kbuild.sh`,
`0001-...SN20.patch`, all three identical to the repo files).

Base: Linux `wallace/t6040-bringup` @ `4f2429104009` (read from the mounted
read-only case-sensitive volume). Comparison sources: `~/code/m1n1/src/spmi.c`
(`regs_gen1`, `raw_command`, `spmi_send_wakeup`), `yuka/feature/m4-usb`
`drivers/spmi/spmi-apple-controller.c` (`spmi_raw_cmd`, `spmi_cmd`).

## A. Root cause — PASS

- `drivers/spmi/spmi-apple-controller.c` @ 4f24291 sets only
  `ctrl->read_cmd` (line 140) and `ctrl->write_cmd` (line 141). There is no
  `.cmd` anywhere in the file. The file's last change at this base is
  `6c54b0a801dd spmi: apple: Add "apple,t8103-spmi" compatible`.
- `drivers/spmi/spmi.c:94-104` (`spmi_cmd`):
  `if (!ctrl || !ctrl->cmd || ctrl->dev.type != &spmi_ctrl_type) return -EINVAL;`
  (line 98). With a NULL `ctrl->cmd` the function returns before any
  controller call, so nothing reaches MMIO. `spmi_command_wakeup()`
  (`spmi.c:307-311`) is a plain wrapper around `spmi_cmd(..., SPMI_CMD_WAKEUP, ...)`.
- The 0001 probe ignored the return: `patches/0001-...SN20.patch:542`
  (`+	spmi_command_wakeup(sdev);`, result discarded). The 2026-08-18 review
  recorded WAKEUP as "sanctioned (m1n1 R0 preamble)" without checking that
  the Apple controller could emit it. That is the gap.
- Any other way WAKEUP could have reached the bus in run 6? No:
  1. `git grep spmi_command_` at 4f24291 over `drivers/` and `include/`
     returns only the four declarations in `include/linux/spmi.h:184-187`.
     The only caller in the built tree is the one 0001 adds.
  2. The two `.cmd` implementers in the tree (`spmi-pmic-arb.c:1878`,
     `spmi-mtk-pmif.c:746`) are Qualcomm/MediaTek controllers and do not bind
     to the Apple DT nodes.
  3. The chainloaded m1n1 (`~/code/m1n1`, branch `main`) has no caller of
     `spmi_send_wakeup` outside `src/spmi.c`; the hpm2 bring-up code that
     did send it lived in the separate `~/code/m1n1-hpm2` tree (per the
     2026-08-18 review), which was not the run-6 chainload.
  4. Run 6 chainloaded from the rollback proxy with Linux's own DTB; nothing
     in that path sends SPMI traffic to SID 0x0c before `tps6598x_spmi_probe`.

Claim 2 (un-woken part reads zero, so VID read 0 → -ENODEV) is **consistent
with all evidence but not yet hardware-proven**; the author says the same in
the run-6 write-up. The chain that makes it the only explanation fitting run 6:
VID is logical register `0x00`, so `tps6598x_spmi_select(0x00)` writes
Register-0 = 0, reads the select register back, sees `0x00 == reg` and returns
success (the `-EIO` branch for `sel != (reg | BUSY)` cannot fire for reg 0);
the window read returns zeros; `vid == 0`; `tps6598x_probe_common` returns
`-ENODEV` with no log line. Every alternative leaves a trace: a select
mismatch gives `-EIO` (not `-ENODEV`), a controller timeout logs
`failed to wait for RX FIFO not empty` (`spmi-apple-controller.c:53`),
and `tps6598x_check_mode` logs `controller in unsupported mode` before its
`-ENODEV` (`core.c:1082-1088`). Run 6 had none of these. Ticket 093
(`evidence/2026-07-24-t6040-hpm2-r0-attempt3.md:25-38`) showed the un-woken
selector reading `0x00`; tickets 094/095 showed WAKEUP + 10 ms yields
power-state `0x07` and SSPS→S0 PASS. The new `VID read failed: ret=%d
vid=0x%08x` and `after WAKEUP: power-state read ret=%d state=0x%02x` lines
are what will prove or refute the claim on the rig.

## B. Wire format — PASS (two notes)

Patch `apple_spmi_cmd` (patch lines 13-45):

- Command word: `opc | sid << 8 | BIT(15)` (patch line 26). m1n1
  `regs_gen1` (`src/spmi.c:43-62`): `cmd_opcode_mask GENMASK(7,0)`,
  `cmd_addr_mask GENMASK(14,8)`, `cmd_active_mask BIT(15)`,
  `cmd_extra_mask GENMASK(31,16)`. `raw_command` (`src/spmi.c:166-169`)
  writes `FIELD_PREP(extra) | active | FIELD_PREP(addr, sid) | FIELD_PREP(opc)`
  with `extra = 0` for `spmi_send_wakeup` (`src/spmi.c:221-224`). For
  opc 0x13, SID 0x0c that is `0x00008c13` — identical bit-for-bit to the
  patch's word. The R1 log (`evidence/2026-07-24-t6040-hpm2-r1-wake-read-result.md:29-30`)
  shows `TX sid=0x0c opc=0x13 extra=0x0000` and `RX header=0x00008c13`.
  Register offsets: Linux uses `SPMI_CMD_REG 0x4` / `SPMI_RSP_REG 0x8` /
  status `0x0`, RX-empty `BIT(24)`, equal to m1n1 `regs_gen1` (the ADT
  generation is 3, and m1n1 selects `regs_gen1` for `gen < 4`,
  `src/spmi.c:119-122`). Run 6 proved these offsets live on a1.
- Opcode and SID: `SPMI_CMD_WAKEUP` is `0x13` in `include/linux/spmi.h:19`
  and `SPMI_OPC_WAKEUP 0x13` in m1n1 `src/spmi.c:10`; the patch's private
  `APPLE_SPMI_OPC_WAKEUP 0x13` (patch line 10) matches both. SID comes
  from `sdev->usid` = `0xc` in the DT (`dts/t6040-j614s-dcuart-usb2-native-right-pd.dts:93`).
  Exact.
- Reply validation (patch line 34): opcode `7:0`, SID `14:8`, ACK `bit 15`.
  m1n1 checks opcode and address (`src/spmi.c:183-187`) and, for a bare
  command, ACK (`src/spmi.c:200-201`). yuka's `spmi_raw_cmd` checks ACK
  (`:149-152`). The reply `0x00008c13` passes all three. Equivalent or
  stricter than both references on bits 15:0.
- Timeouts: one path, `apple_spmi_wait_rx_not_empty` (`spmi-apple-controller.c:45-58`,
  `readl_poll_timeout` 10 ms interval × 5 = 50 ms, logs `dev_err` and returns
  `-ETIMEDOUT`). The patch propagates it (patch lines 28-30) and the tipd
  probe now fails on it via `dev_err_probe` (patch line 92). Same timeout
  the already-reviewed read/write paths use; no new timeout behaviour.

Notes (not must-fix):

1. The patch does not check reply bits `31:16`. m1n1 additionally requires
   that frame-parity field to equal `MASK(len_out) = 0` for a bare command
   (`src/spmi.c:198-199`). `0x00008c13` satisfies it; the Linux check is
   marginally looser than m1n1 on the top half-word.
2. No TX-FIFO-empty check and no leftover-RX drain before the command write.
   m1n1 does both (`src/spmi.c:156-163`). The existing `spmi_read_cmd` /
   `spmi_write_cmd` at 4f24291 do neither and *discard* the reply header
   unchecked (`:77-78`, `:116-117`), so this is consistent with the driver as
   reviewed in August, not a regression; the new `.cmd` is in fact the first
   path in this driver that validates the reply at all. A stale RX word would
   surface as the `unexpected reply 0x%08x` `-EIO` (m1n1's "leftover RX
   data?" case) and fail the probe closed. No controller-level lock exists in
   spmi-apple at this base (yuka's branch adds `fifo_lock`); not introduced
   here, and WAKEUP runs in single-threaded probe before the regmap exists.

## C. Safety envelope — PASS

- `.cmd` refuses everything but WAKEUP before any MMIO:
  `if (opc != APPLE_SPMI_OPC_WAKEUP) return -EOPNOTSUPP;` (patch lines 22-23)
  precedes the single `writel` (line 26). RESET (0x10), SLEEP (0x11),
  SHUTDOWN (0x12) therefore return `-EOPNOTSUPP` on every bus this driver
  serves, including the PMU bus `spmi@509014000` / abbey `pmic@e`
  (`dts/t6040.dtsi:591-600`). Compare yuka's `spmi_cmd`, which allows all
  four (`yuka/feature/m4-usb spmi-apple-controller.c:206-214`); the Wallace
  patch is deliberately narrower.
- No new endpoint, no new write class. The patch touches no DT, no 4CC, no
  register write. The tipd side adds one R0 read (logical `0x20`, 1 byte,
  through the reviewed select/window path) and two log lines. Entry 1's
  envelope (probe WAKEUP + logical reads + SSPS→S0, INT_MASK1 `0x16`, W1C
  INT_CLEAR1 `0x18`) is unchanged; the WAKEUP it already lists is now
  actually emitted.
- Who else can call `spmi_command_*` on these buses: nobody. At 4f24291
  `git grep spmi_command_` over `drivers/` hits only the header. The only
  SPMI child drivers in this config are `apple-spmi-nvmem`
  (`CONFIG_NVMEM_APPLE_SPMI=y`, reads/writes via `spmi_ext_register_*`,
  never a bare command) and `tps6598x-spmi` (`CONFIG_TYPEC_TPS6598X_SPMI=y`).
  The Qualcomm/MediaTek SPMI consumers in the config (`MFD_SPMI_PMIC`,
  `REGULATOR_QCOM_SPMI`, ...) match their own compatibles and have no DT node
  here. DT nodes on the two Apple buses in the physfix DTB: `pmic@e`
  (abbey, SID 0x0e) under `spmi@509014000`; `usb-pd@c` (SID 0x0c) under
  `spmi@509198000`. `nub-spmi-a0` is still not described
  (`dts/t6040.dtsi:588-590`).

## D. tipd changes — PASS (one style note)

- 10 ms settle: `usleep_range(10000, 11000)` (patch line 97) sits
  immediately after a *successful* WAKEUP and before `devm_regmap_init`
  (which generates no bus traffic), so the first select/window transaction
  is ≥10 ms after WAKEUP. Matches the 093/094 recipe.
- WAKEUP failure: `ret = spmi_command_wakeup(sdev); if (ret) return
  dev_err_probe(...)` (patch lines 90-92). Fail-closed; -EINVAL from a
  controller without `.cmd` would now be visible rather than silent.
- Power-state read: `regmap_raw_read(regmap, 0x20, &power_state, 1)`
  (patch line 105). With `tps6598x_regmap_config` (`reg_bits 8, val_bits 8,
  max_register 0x7F`, no cache, `core.c:1091-1095`) this goes straight to
  `tps6598x_spmi_regmap_bus.read` → select(0x20) + one 16-byte-max window
  read: an R0 read on the allowlisted endpoint, the same register 094 read.
  `power_state` is initialised to 0 (patch line 76) so the log cannot print
  garbage on error, and the read's return is logged, not acted on.
  Style note: `0x20` is `TPS_REG_SYSTEM_POWER_STATE` (`tps6598x.h:42`) and
  `spmi.c` already includes that header; a magic number, not a bug.
- VID log: `ret < 0 ? 0 : vid` (patch line 65). `tps6598x_read32` →
  `tps6598x_block_read` → `regmap_raw_read` (`core.c:243-244`, non-I2C
  path) may leave `vid` untouched on error; the guard prevents printing it.
- I2C (M1/M2 cd321x) path: `core.c` change is the log line only; the
  `-ENODEV` return is unchanged. `spmi.c` is SPMI-only. No behaviour change
  for I2C beyond the new error message.

## E. Build plumbing — PASS

`scripts/t6040-kbuild.sh:487-520`:

- Outer `if [ "${T6040_TYPEC_PD:-0}" = "1" ]` applies 0001 first
  (lines 489-499, with the same apply / `-R --check` already-applied /
  hard-error triad).
- The WAKEUP block (lines 503-516) is nested inside it and runs only after
  the 0001 branch has either applied or confirmed-already-applied. It is
  idempotent via `git apply -R --check` (line 509) and hard-errors with the
  diagnostic `--check` output if neither direction applies (lines 511-514).
- `elif [ "${T6040_TYPEC_PD_WAKEUP:-0}" = "1" ]` on the outer `if`
  (lines 517-519) exits 1 with `T6040_TYPEC_PD_WAKEUP=1 requires
  T6040_TYPEC_PD=1`. Correct.
- The patch is read from `/out/` and the staged copy's sha256 equals the
  repo file (see Objects reviewed).

## F. Clean apply on top of 0001 at 4f24291 — PASS

Scratch git tree built from `git show 4f24291:<file>` for
`drivers/spmi/spmi-apple-controller.c`, `drivers/usb/typec/tipd/{core.c,
Kconfig, Makefile, tps6598x.h}`:

```text
wake patch alone on base:        fails (tipd/spmi.c does not exist) — expected
git apply --index 0001:          OK
git apply --check wake:          OK
git apply wake:                  OK   (3 files, +54/-3)
git apply -R --check wake:       OK   (idempotency branch works)
resulting blob ids: spmi-apple-controller.c e00967c, core.c 14f0157, spmi.c 579ae4a
```

The resulting blob ids equal the patch's `index` lines (`87e3ee9..e00967c`,
`4ea378a..14f0157`, `cf91024..579ae4a`), i.e. the patch was generated against
exactly this base + 0001.

## Artifacts — NOT VERIFIED (not present yet)

At review time `~/code/linux-build-out/` holds only
`kbuild-pdwake-build1.log` (176 bytes, still in the `clone` step) and no
`Image-pdwake.build1`; `kbuild-pdwake-build2.log` does not exist. The
podman kbuild for build1 is running. When both finish, the reviewer of the
build (not this document) should confirm:

1. `Image-`, `System.map-`, `config-pdwake.build{1,2}` byte-identical
   (sha256 pairs).
2. `config-pdwake.build1` sha256 == `config-usb2pd.buildA` (`51aa40f0…`);
   no Kconfig is touched by this patch, so any difference is a build-env
   drift, not the patch.
3. `strings Image-pdwake.build1 | grep -e 'SPMI WAKEUP failed' -e 'after WAKEUP: power-state' -e 'VID read failed' -e 'WAKEUP to SID'`
   all hit, and `grep -c apple_spmi_cmd System.map-pdwake.build1` ≥ 1.

## Must-fix items

None.

## Notes for the attended run (non-blocking)

- Expect, in order: no `SPMI WAKEUP failed`; `after WAKEUP: power-state read
  ret=0 state=0x07` (or `0x00` if already in S0); then the normal
  `tps6598x` VID/mode path. `state=0x00` with VID still 0 would refute
  claim 2 and point at the select/window protocol instead.
- A `WAKEUP to SID 12: unexpected reply` line means stale RX data or a wrong
  controller generation, not a sleeping part; stop and capture the raw word.
- Preserve the full dmesg before any `dmesg -c` (run-6 lesson).
