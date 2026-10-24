# SD-root daily v3: offline rebuild with the fixed shutdown path (ticket 5000)

Claude, 2026-10-24. Offline build and host verification only. No rig lease,
card access, enrollment or boot.

## Outcome

`m1n1-alpine-sdroot-daily-v3.bin` replaces 216's pinned daily-v2 object
`bdd8cc86…`, whose shutdown path cannot complete (ticket 3006). It reuses
daily-v2's reproducible kernel and DTB unchanged, takes a fresh initramfs from
the current build script carrying the 3006-fixed `/init` and `/shutdown`, and
corrects the console order to the BUILD_RECIPE §3 rule. Two independent
initramfs builds and two object compositions are byte-identical. Both pass the
strict raw-object verifier and `t6040-image-preflight.sh`.

```text
3dae381212ce53c84b41d681edc0426a624d02afa92c841bff9fb170b2b9703a  m1n1-alpine-sdroot-daily-v3.build1.bin
3dae381212ce53c84b41d681edc0426a624d02afa92c841bff9fb170b2b9703a  m1n1-alpine-sdroot-daily-v3.build2.bin
f089ffa7f1e2982e5661dd25b2aca9fd8d12795de17e33e656e7562680a035f7  initramfs-sdroot-daily-v3.build1.cpio.gz
f089ffa7f1e2982e5661dd25b2aca9fd8d12795de17e33e656e7562680a035f7  initramfs-sdroot-daily-v3.build2.cpio.gz
```

Strict verifier: 25,870,336 bytes (1,579 × 16 KiB), entry `0x800`, exact
bootargs and members, zero terminator, runtime payload reserve 79,786,249
bytes. Preflight: 21 PASS, 0 FAIL, including the Norwegian keymap member, the
`loadkmap` call in `/init`, `fsck.exfat`, the paired WiFi/BT firmware,
`maxcpus=1`, `console=tty0` last, window-free m1n1 and 16 KiB alignment.
Outputs are in
[2026-10-24-t6040-5000-sdroot-daily-v3/](2026-10-24-t6040-5000-sdroot-daily-v3/).

## Inputs (unchanged from daily-v2 unless noted)

```text
97a304880e35e268e846273c23ed38bddf1a837ca431590a855e03e56d5e8c9f  m1n1-sdroot-hardened.bin
3e129466d612d176b0d52ddd2a004ed89a920b8e2f3a38f39504cda4059d04f2  Image-alpine-sdroot-daily-v2.build{1,2}
b5d33b3335475e36ac14158fc01514e506956fb1448c2296cf84890f5d8b7b27  compressed kernel member (identical to daily-v2)
c5c3b4c38b24748f95e06fd3cc39b348326783a58feb7029d9273a5b23dd7e72  t6040-j614s-dcuart-wifi-cpufreq-sdroot.build{1,2}.dtb
59764944c4aad38189df5ee05a190c5ce60fd44727482105e4f20df7d8c7edc1  initramfs-sdroot-wifi-base-59764944.cpio.gz
9d0a1b944e4991765625953b99b2b401a8636060025ae374708ce3c9e7619701  scripts/t6040-build-sdroot-initramfs.sh (HEAD 66451cd; changed)
c65245bccd519ae45f9c68fbcc67c725d4b17de4632222c0c03f3032b5d0f79f  wpa_supplicant.conf (CJ's host config; not sensitive per CJ)
```

The embedded scripts are byte-identical to the set that scored **23/23** in the
3006 harness: init `95f1e268…`, shutdown `c5c05855…`, inittab `f5e1628e…`,
powerctl `791c0f8a…`, OpenRC wrapper `47e7504d…` and early-console
`9fba64d6…`. `/init` installs the helpers onto the card on every boot.

Bootargs (changed: `console=tty0` moved last):

```text
maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused fbcon=font:TER16x32 ignore_loglevel console=ttydc0 console=tty0 rdinit=/init
```

216's daily-v2 bootargs ended in `console=ttydc0`, which the current preflight
rejects because the panel keyboard then has no `/dev/console`. That is a second
reason the old pin could not be used as-is.

## Deltas from daily-v2 the reviewer must check

- Initramfs: the current build script adds the Norwegian keymap, the static
  `fsck.exfat`, the J614s HIDF blob `a1f4131d…` (inert here: this kernel lacks
  `TRACKPAD_FW`, so trackpad integration remains 301), the `/opt/wallace`
  helpers, `wpa_supplicant.conf` and the Adwaita cursors. `/init` adds the
  waiting PCIe gates, real `fsck.exfat` repair before the unconditional dirty
  gate, helper self-heal, timezone and the 3006 `/run` mount.
- Kernel and DTB: unchanged. ANS/NVMe, system-PMU SPMI, `smc_rtc` and
  `smc_reboot` stay disabled, so the final hardware poweroff/reboot may still
  no-op after a clean unmount, exactly as 216 already states.

## Gates still open

1. Independent exact-artifact review by another agent: DT status gates,
   firmware manifest, init/shutdown, complete-object hash, strict verifier.
2. Ticket 215 must repair and recheck SD64 and the ext4 image first.
3. CJ re-pins 216 to these hashes. Rollback stays enrolled; this object is
   chainloaded or installed only under the maintainer's procedure.
