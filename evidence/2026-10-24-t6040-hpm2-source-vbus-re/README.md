# Tooling output for evidence/2026-10-24-t6040-hpm2-source-vbus-re.md

Host-local inputs (not in the repo, per project practice):

- `~/Code/linux-build-out/t6040-usb-kexts-25F84/com.apple.driver.AppleHPM`
  (sha256 `b6eab85a4478fe354c29d4a274fa1ea23ced1c051e3b320fdfad54d65dce381d`)
  and its `.a2s` symbol cache.
- `com.apple.driver.AppleSPMI` and `com.apple.driver.AppleARMPlatform`
  extracted from `~/Code/linux-build-out/t6040-kernelcache-25F84.raw` with
  `ipsw kernel extract` (sha256 in the evidence file).

Files here are derived tables and the scripts that produced them; no Apple
code or disassembly text is committed.

- `vtable-slots.txt` — PAC-checked vtable slot → method tables for the classes
  cited in the evidence (AppleTCControllerType10, AppleHPMDeviceHALType3/5,
  AppleHPMARMSPMI, AppleHPMDevice, AppleARMSPMIDevice).
- `register-inventory.txt` — every `mov w1, #reg` feeding a vtable call, per
  function, across the AppleHPM `__text` (register number, w3 length when an
  immediate, call target when resolvable).
- `fn.py` / `sum.py` / `rng.py` — extract, summarise, or range-dump functions
  from an `ipsw macho disass` listing (`hpm.asm`, regenerate with
  `ipsw macho disass --section __TEXT_EXEC.__text --cache <kext>.a2s --no-color <kext>`).
- `vtab.py` — the vtable decoder (`vtab.py KEXT CLASS [slot ...]`).
