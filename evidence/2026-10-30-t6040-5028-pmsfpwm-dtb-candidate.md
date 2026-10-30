# 5028: DTB candidate with the PMS FPWM domains disabled, built on the M4 (claude, 2026-10-30)

**Result:** `/mnt/sd/wallace-5028/wallace-5028.build1.bin`, sha256
`c0e5d515395ad5c099d573b99b1e0ab91e16f9cca081893a4d3a67fc8eadcc71`, 33,177,600 B. It is the enrolled
5019 object with **only the DTB changed** (bootargs, kernel, initramfs and m1n1 are 5019's bytes).
Built twice byte-identical; `t6040-raw-object-verify.py --strict` PASS; `t6040-image-preflight.sh`
OK. Not enrolled or booted: that is the proposed boot ticket.

| piece | sha256 |
|---|---|
| DTB `t6040-j614s-dcuart-wifi-cpufreq-nvmeroot-ramoops-pmsfpwm` | `5e7984f8e3a714c18cfca99b1de6de54049cbaa9e90bef4aa5177dffe7e861c0` |
| object | `c0e5d515395ad5c099d573b99b1e0ab91e16f9cca081893a4d3a67fc8eadcc71` |
| m1n1, kernel gzip, initramfs | unchanged from 5019 (`bf4b2462…`, `2fcc01e1…`, `82a86064…`) |

## The change

`dts/t6040-j614s-dcuart-wifi-cpufreq-nvmeroot-ramoops-pmsfpwm.dts` includes the 5019 ramoops DTS
and sets `status = "disabled"` on `ps_pms_fpwm0..4` (PMGR `502800000`, power-controller
`@140/148/150/158/160`). Decompiled against 5019's DTB, the only differences are the model
string and five `status = "disabled"` lines, each inside the matching `pms_fpwm` node. The reasoning
is in the 5028 ticket: ADT-critical, off at probe, TARGET 0xf and ACTUAL 0 every boot, M5 crashes on
fpwm1, and nothing references them.

## On-device DT builds now reproduce the Mac's

The DTB was built on the M4 in the bookworm chroot. The tree was the pushed `e9d2237` plus
`2026-10-30-t6040-5019-reconstructed-base.patch` (the four reconstruction files), with kbuild run
using the 5019 flags and the new `STOP_AFTER_DTB=1` (tree configured and patched, `t6040-j614s.dtb`
built, no Image; 52 s). wallace `dts/` supplied the files that are not in the pushed tree
(`t6040-j614s-dcuart.dts`, the sdroot/nvmeroot/ramoops chain). Checks:

| DTB | built here | reference |
|---|---|---|
| nvmeroot-ramoops | `1a49d19dd3778799…` | 5019, byte-identical |
| nvmeroot | `6d2d3da60352c93a…` | 5014/2234baad, byte-identical |

So DT-only variants no longer need the Mac. The same DT-only run also confirmed that the onboard
debug config set, now with `MTD_PHRAM` and `PROC_KCORE` (5027), survives olddefconfig: the
"assert onboard debug support is BUILTIN" step passed.

`scripts/t6040-rebootargs-object.py` gained `--replace-dtb` for DT-only object variants.

## Boot PASS criteria (for the boot ticket)

- No `pms_fpwm` lines in dmesg. `pm_genpd_summary` shows no `pms_fpwm*`, and `pms` is still on.
- Keyboard backlight still works (`/sys/class/leds/kbd_backlight`, sio `fpwm0`).
- Panel brightness is unchanged from iBoot's level, with no dimming or blanking over a few minutes.
- Everything 5020 checked still passes.
- STOP: a dark or dimmed panel, SError, or panic. Roll back by re-enrolling 5019 (`28127903`).
