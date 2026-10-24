# Ticket 305 run 6 (2026-10-24): a1 SPMI works at the corrected address; hpm2 probe returns -ENODEV

Claude, CJ attending. Lease `claude`, released **healthy** at `Running proxy`.

## Fixture and payload (all re-verified before boot)

M4 at the rollback proxy; DebugUSB left↔left; **S128 in the M4 right port;
SD card removed** (so the SD-root init stopped at its ttydc0 rescue shell
and nothing mounted or repaired storage). Chainload m1n1 `7de07c71…`;
`Image-usb2pd.buildA` `5a136710…`; physfix DTB `eaf8cceb…` (a1 at
`0x509198000`); `initramfs-sdroot-hardened` `4cc65133…`; cmdline
`maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0
fbcon=font:TER16x32 ignore_loglevel rdinit=/init`.

Host prerequisite: macOS 15.8.1's `deviceinterfaced` (its
`tadfu-transport-server`) claims the M4 "Debug USB" device and blocks kisd.
`launchctl kill` is refused under SIP; CJ ran
`sudo kill -9 $(pgrep -x deviceinterfaced)` while kisd retried, and kisd won
the device. The respawned daemon did not reclaim it while kisd held it.

## Result

- Boot reached the shell with no hang, SError, DART fault or reset. **Both
  SPMI controllers bound to `apple-spmi`**, including `509198000.spmi`.
  This is the first time Linux has driven the real a1 controller; runs 1–4
  hung on the raw `0x309198000` address, which is now explained.
- hpm2 appears as SPMI device `1-0c`
  (`/soc/spmi@509198000/usb-pd@c`, compatible `usbc,sn201202x,spmi`,
  `waiting_for_supplier=0`), but **no driver is bound**. A manual re-bind
  (`echo 1-0c > …/tps6598x-spmi/bind`, the same probe transactions and so
  within SPMI_SAFETY Entry 1) returned **ENODEV** ("No such device") and logged
  nothing. There were no SPMI controller errors.
- No `/sys/class/typec`, no VBUS, no USB child: only root hubs
  `usb1`/`usb2` on `xhci-hcd.0.auto` (`392280000`). **305 PASS not met.**

## Leading hypothesis (code-reviewed, not yet hardware-proven)

`tps6598x_probe_common` reads `TPS_REG_VID` first and returns `-ENODEV` on
error or zero, before `cd321x_data.switch_power_state` (SSPS→S0) runs. The
SPMI probe only issues WAKEUP first. If the SN201202x answers zeros until it
reaches S0, that silent `-ENODEV` is what we observed. The patch comment's
"wakeup → read power state → SSPS to S0" order is not what the code does.

## Evidence files and a mistake

`linux-build-out/transcripts/305-claude-20261024-run6/`:
console `t6040-console-20261024-claude-ticket305-run6-a1-physfix.log`
`79f41cce…`; boot `361fa5cd…`; chainload `e8fc98c2…`. The full boot dmesg is
**lost**: my bind step ran `dmesg -c` before the full capture, so only the
targeted greps recorded earlier survive. They show no spmi/tps6598x/typec
kernel messages. Never clear the ring buffer before preserving it.

## Next (offline first)

A logging-only build that prints the SPMI read return code, the raw VID and
the power-state register before and after WAKEUP, with no new transaction
types, to discriminate "asleep" from "wrong select/window protocol". If it
is the power state, move SSPS→S0 before the VID check on the SPMI path. Both
need two clean builds, independent review and an attended run.
