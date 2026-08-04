# T6040 Type-C PD: an SPMI transport for the tps6598x driver (SN201202x)

**Date:** 2026-08-04. **Author:** fable (offline driver work, no rig).
**Ticket:** 231 (SPMI PD client), 301-adjacent. **Deliverable:**
`patches/0001-usb-typec-tps6598x-add-SPMI-transport-for-T6040-SN20.patch`.

## What this is

CJ approved writing the SPMI PD-controller driver. The T6040's four Type-C PD
controllers are Apple SPMI parts (`usbc,sn201202x,spmi`), and there is no
in-tree driver for them (`grep -rl sn201202x drivers/` is empty). The
controller speaks the ordinary TPS6598x logical-register protocol, so this
adds an **SPMI transport** to `drivers/usb/typec/tipd/` and reuses the entire
existing tipd state machine and `cd321x_data` unchanged. It is the reviewed,
upstream-shaped alternative to hand-rolled HPM 4CC pokes (the point of tickets
170/231), and it stays out of the deny-by-default reverse-engineered 4CC path.

## The one substantive correction to the stated plan

The task brief said to swap `devm_regmap_init_i2c` for
`devm_regmap_init_spmi_ext`. **That does not work for this part, and I did not
do it.** `devm_regmap_init_spmi_ext` (drivers/base/regmap/regmap-spmi.c) is a
*flat* map: regmap register N is issued as `spmi_ext_register_read(N, …)`. The
SN201202x does not expose its TPS logical registers as flat SPMI registers —
it is **paged**:

1. **select**: write the logical register number to SPMI register 0 (SPMI
   "Register 0 Write"), then poll SPMI register 0 until it reads back that
   number with its busy bit (`BIT(7)`) cleared;
2. **window**: transfer the payload through a data window at SPMI register
   `0x20`, in SPMI-extended chunks of ≤16 bytes, the window address
   auto-incrementing across chunks (`0x20`, `0x30`, …) for registers wider
   than 16 bytes.

A flat `spmi_ext` regmap would read SPMI physical register `0x1a` instead of
the paged TPS `STATUS` register `0x1a` — wrong for every access.

**Evidence this paging is the hardware's actual protocol, not a choice:**

- Our own m1n1 bring-up, live-proven against this exact hardware
  (`~/Code/m1n1-hpm2/src/t6040_hpm2.c`), reaches S0 via
  `select_logical_reg()` (zero-write to reg 0, poll `BIT(7)`) then
  `spmi_ext_read/write` at register `0x20`. R2 (SSPS→S0) passed live.
- Apple's own `AppleHPMARMSPMI::readRegs` (25F84 kernelcache) does the same:
  it selects, polls register `0x1f`, then reads through the provider window at
  register `0x20`, passing the full length; the provider
  (`AppleSPMIController::extendedReadWriteCommand`) does the 16-byte chunking
  with the SPMI address auto-incrementing when its increment-mode flag is set.
  Disassembly reproduced this session from the pinned extracts (readRegs
  sha256 `90763bfc…`, matching `evidence/2026-07-24-t6040-hpm-spmi-discovery-boundary.md`).

So the driver provides a **custom `regmap_bus`** (`tipd/spmi.c`) that does
select-then-window, presenting the flat 8-bit register space
(`tps6598x_regmap_config`, reg_bits=8/val_bits=8/max_register=0x7F) that
`core.c` already expects. `max_raw_read/write` are deliberately left unset so
regmap delivers each whole logical-register access in one bus call (a split
would re-select at the wrong offset register); the ≤16-byte SPMI chunking
happens inside the bus.

This deviation is loud on purpose. It is the same class of correction as
ticket 231 itself (which refuted 170's "CD321x is on I2C" premise): the
literal instruction was derived from the M1/M2 I2C parts, and the M4 SPMI part
behaves differently. **A reviewer and CJ should see and sign off on this
before any rig run.**

## Shape of the change

- **core.c**: factor `tps6598x_probe_common(dev, regmap, irq, data)` and
  `tps6598x_remove_common(dev)` out of the I2C probe/remove. The I2C driver
  becomes a thin wrapper (`tps6598x_i2c_probe`/`_remove`). The three
  I2C-specific spots collapse cleanly:
  - `i2c_get_match_data` → stays in the i2c wrapper; SPMI uses
    `device_get_match_data`.
  - `devm_regmap_init_i2c` → each transport builds its own regmap and passes
    it in.
  - `i2c_check_functionality` (which sets `tps->i2c_protocol`) → detected in
    common via `i2c_verify_client(dev)`; NULL for SPMI, so `i2c_protocol`
    stays false and `tps6598x_block_read/write` take the plain-regmap path
    (core.c:243), exactly as the brief specified.
  - `client->irq` → `tps->irq` (new field), stored by common; PM/remove use
    it transport-agnostically.
  - `module_i2c_driver` → an explicit `module_init/exit` that registers the
    i2c driver and, when built, the spmi driver.
- **spmi.c** (new): the paged `regmap_bus`, the `spmi_driver`
  (`tps6598x_spmi_probe/_remove`), an of_match on `usbc,sn201202x,spmi` (and
  `apple,cd321x` for completeness) both binding **`cd321x_data`**, and
  `tps6598x_spmi_{register,unregister}()` called from core's module init.
  Compiled into the *same* `tps6598x` module (Makefile
  `tps6598x-$(CONFIG_TYPEC_TPS6598X_SPMI) += spmi.o`), so it reuses
  `cd321x_data` / `tps6598x_probe_common` with no cross-module exports.
- **Kconfig**: new `TYPEC_TPS6598X_SPMI` bool, `depends on TYPEC_TPS6598X &&
  SPMI`, `select REGMAP`. `TYPEC_TPS6598X` itself is unchanged (still
  `depends on I2C` — the I2C path is the module's baseline; SPMI is additive).
- **tps6598x.h**: internal shared declarations (`tps6598x_probe_common`,
  `tps6598x_remove_common`, `cd321x_data`, `tps6598x_regmap_config`,
  `tps6598x_pm_ops`, and the spmi register/unregister stubs).

## Safety envelope

At probe the SPMI path does only: `spmi_command_wakeup` (mirrors the proven
m1n1 wake order; harmless if already awake), builds the regmap, resolves the
IRQ from DT (`of_irq_get`, falls back to polling), then `tps6598x_probe_common`
— which for `cd321x_data` runs `cd321x_switch_power_state` (SSPS→S0, the
live-proven R2 write) and register reads, and registers the typec port. **It
issues no role-swap 4CC.** The `SWDF`/`SWUF` (data role) and `SWSr`/`SWSk`
(power role) commands live in `tps6598x_dr_set`/`_pr_set`, invoked only by
typec sysfs / the role switch, never at probe. So probe stays inside the
sanctioned "read/enumerate the HPM via a driver" envelope (WAKEUP + SSPS-S0 +
reads); the deny-by-default RE 4CC path is not touched.

No SID is hardcoded: the SPMI `usid` comes from the DT `reg`. Building the DT
connector node (with the right-port HPM's ADT-derived SID/interrupts) is
separate follow-on work — this deliverable is the driver.

## Build / config

New kbuild switch `T6040_TYPEC_PD=1` (scripts/t6040-kbuild.sh): applies the
patch, builds `TYPEC=y TYPEC_TPS6598X=y TYPEC_TPS6598X_SPMI=y
USB_ROLE_SWITCH=y SPMI=y SPMI_APPLE=y` (=y because our images can't load
modules), re-applies + asserts them after olddefconfig. Compile-critical
symbols are fatal; `SPMI_APPLE` (the bus controller, a *runtime* dep) is
warn-only so a non-SPMI-bus config can still validate the compile.

**Guard:** `T6040_TYPEC_PD=1` hard-errors with `SD_GL9755=1`. The GL9755
SD-diagnostic profile deliberately strips SPMI and asserts `SPMI_APPLE` is
OFF, so the two are contradictory. Consequence worth flagging for the eventual
USB-host integration image: it will need an initramfs root (or a reconciled
config), not the SPMI-stripping SD-diagnostic profile.

## What remains before this can source VBUS on the rig

1. Independent exact-source review of this patch (COORDINATION.md).
2. A DT connector node for the right-port HPM (ADT-derived SID/interrupts/
   connector power-role/data-role), which ticket 170/231 tracks.
3. CJ sign-off + an attended rig run (rig is serialized for 230 right now).
4. The open question a rig run answers: whether bringing the HPM to S0 under
   Linux management, with the port configured as a source/DRP, autonomously
   sources VBUS to an attached bus-powered sink — which is the entire premise
   of the DT-driver route over hand-rolled 4CCs.

Pairs with the ticket-108 fix (`2026-08-04-t6040-dwc3-einval-phy-mode-ordering.md`):
that restores the USB2 *data* path to xHCI root hubs; this driver is the
*VBUS/CC* path. Both are needed for a bus-powered stick to enumerate.
