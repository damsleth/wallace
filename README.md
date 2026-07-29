# Project Wallace

Mainline Linux on a MacBook Pro 14" M4 Pro (t6040 "Brava Chop", Mac16,8 / J614s). It boots
**untethered** into Alpine from an enrolled boot object — internal panel, Norwegian keyboard,
watchdog — reaches a **graphical desktop (Xorg + dwm)** with a working keyboard, reads
**battery, charger, and temperature** from the SMC, and as of 2026-07-29 brings up **PCIe**, with
**WiFi (BCM4388) and Bluetooth** both alive. Remote DebugUSB loop for development.

This repo is the umbrella. The code lives in four sibling repos and the knowledge kept getting smeared across them so everything that guides the work now lives here: plans, scripts, kernel patches, post-mortems.

## Status (2026-07-29) — 📶 PCIe UP: WiFi and Bluetooth working

**PCIe works, and with it WiFi and Bluetooth.** `wlan0` + `phy0` come up with running firmware and
the module's own OTP MAC; `hci0` reaches `UP RUNNING` with a real BD address and 187 commands
exchanged, zero errors. The GL9755 SD reader enumerates on the second port.

| device | PCI ID | driver | state |
|---|---|---|---|
| BCM4388 802.11ax WiFi | `14e4:4434` | `brcmfmac` | `wlan0` + `phy0`, bands 2.4/5/6 GHz |
| BCM4388 Bluetooth | `14e4:5f72` | `hci_bcm4377` | `hci0` UP RUNNING |
| GL9755 SD reader | `17a0:9755` | `sdhci-pci` | enumerated |

Four things had to be right, and each was wrong for a different reason:

1. **The PHY reset bit.** Upstream's `apcie,t6040` path clears `BIT(4)`; our fork still cleared
   t602x's `BIT(7)`. That single bit was the entire cause of the two-week "op-115" hang — the
   clkgen/PLL work we built to explain it was never a precondition at all.
2. **Endpoint power — the real link blocker.** The WiFi module's `WL_REG_ON` and the SD reader's
   power enable are **SMC key writes**, not AP GPIOs (ADT: `/amfm function-reg_on = pKW4('gP13')`,
   `pcie-sdreader function-sd_pwr_en = pKW4('gP19')`). `gpio-macsmc` maps a line to key `gP%02x` by
   hex, so they are `smc_gpio` **19** and **25** — exactly the numbers upstream's M3 Pro MacBook Pro
   DT uses. Both links came up within 8 ms of adding `pwren-gpios`.
3. **`apple,antenna-sku = "X3"`** (from the ADT's `wifi-antenna-sku-info = 0x3358`). Without it
   brcmfmac never takes its Apple firmware path and never looks for the per-module NVRAM our
   corpus ships.
4. **BCM4388 rev 6 wants the c2 firmware blobs** even though brcmfmac maps rev ≥ 4 to the **c0
   filename** — so the c2 content is published under the c0 names. Preserve that when regenerating
   the firmware corpus.

**Scanning needs one more kernel change.** The radio receives beacons, but Apple's firmware reports
scan results as `wl_bss_info` **version 116** while brcmfmac accepts only 109–112, so every BSS is
discarded (`brcmf_inform_bss: BSS info version 116 unsupported`) and `iw scan` returns nothing.
`patches/t6040-brcmfmac-bss-info-v116.patch` raises the bound.

Details: `done/2026-07-29-t6040-WIFI-AND-BLUETOOTH-WORKING.md`,
`done/2026-07-29-t6040-pcie-endpoint-power-root-cause.md`,
`done/2026-07-29-t6040-pcie-op115-SOLVED-links-dont-train.md`.

⚠ `pwren-gpios` means the kernel's `gpio-macsmc` performs two SMC key writes (`gP13`/`gP19`). They
are PMU **GPIO outputs** — not charger or voltage-rail writes — and the maintainer has approved
them; note they are the generic upstream API rather than a byte-exact replay of what macOS sends.

## Status (2026-07-28) — 🔋 battery + thermals working; USB device mode proven

The enrolled daily driver (`m1n1-b0-macsmc-dualmode.bin` `5931f9c3`) is dwm + Norwegian keyboard +
**live SMC telemetry**: `macsmc-battery` (capacity, cycle count, charge/voltage/energy, `bq40z651`
pack), `macsmc-ac` (charger, 15 W), and hwmon temperature (30.3 °C). Ticket 165 done. The root cause
of the first failed probe was the SMC SRAM address — the coprocessor's own RTKit error named the real
region (`0x50de70000`), and the fix from it worked first try.

**USB device mode works on the M4** — a big result for networking. Linux `dwc3-apple` runs the DFU
port as a gadget: `udc state = configured`, and every CDC flavor (RNDIS/ECM/NCM/ACM) fully enumerates
on the host. But **macOS binds no Linux CDC gadget** (it does bind m1n1's own ACM), so tether-ethernet
to *this* Mac is a macOS host-side wall — it would work into a Linux host. The M4 side is proven
healthy; the networking paths that remain are the **USB host + real dongle** route (ticket 167 kernel
side is built-in, gated on VBUS) and **WiFi** (gated on PCIe).

The two frontier blockers are now precisely characterised and both decoded, awaiting attended rig work:

- **USB host / VBUS (096/097):** `AppleHPMInterface::roleSwap()` issues the `SWDF` 4CC (Swap to DFP =
  host/source) to CMD1 `0x08` — fully decoded and confirmed. An R3 candidate is the proven R2 `SSPS`
  path with the 4CC changed to `SWDF`. Needs byte-level review + an attended run.
- **WiFi / PCIe (124/168):** m1n1 runs T6040 PCIe in *trace* mode (no writes); op-115 is a PLL-lock
  poll at `0x417040090`, and the missing precondition is *applying* the PHY tunables
  (`0x417004000`/`0x417008000`). That is a hardware write, so it needs a supervised session.

## Status (2026-07-26) — 🐧🖥️ GRAPHICAL TARGET REACHED: dwm on the M4 Pro panel

**dwm runs on the internal display with a working keyboard.** Tags 1–9, `[]=` tiled layout, `st`,
`dwm-6.8`, blue selected-window border; `Alt+Shift+Return` spawns a terminal, `Alt+p` opens dmenu, and
æ ø å are correct. The trackpad is still dead, as designed (tickets 004/126).

The whole chain works: **enrolled-format raw object → m1n1 → full kernel → Alpine RAM root → Xorg on
`modesetting`/simpledrm → dwm → `st` → keystrokes.**

| Object | Hash | State |
|---|---|---|
| `m1n1-b0-dwm-udev.bin` | `3ec81ef3` | live-proven tethered: dwm + keyboard |
| `m1n1-b0-dwm-hidpi.bin` | `59622e78` | same, with the HiDPI font fix — **next to enroll** (ticket 162) |
| `m1n1-b0-diet-aligned.bin` | `f290833c` | the B0 milestone object (Alpine, untethered) |
| `rollback-m1n1-1394c345.bin` | `1394c345` | payload-free proxy loader; restores tethered development |

Two blockers had to fall, and **neither was the one predicted.** Ticket 148 expected the simpledrm probe
to fail or Xorg to refuse without a pointer. Instead: the diet kernel's `# CONFIG_NET is not set` left no
`CONFIG_UNIX`, so Xorg could not create its AF_UNIX listening socket; then the image carried
`libudev.so.1` as a dependency but no `udevd`, so `xf86-input-libinput` enumerated zero devices and
nothing responded. `simpledrm` probed cleanly the first time the full kernel ran.

Text rendered at about a quarter size, because the panel is ~254 DPI while X assumes 96. The fix needs
**three** mechanisms that share no source of truth: the server's `-dpi`, `Xft.dpi` via `xrdb` (the only
lever for dwm's bar and dmenu, whose fonts are compile-time in the suckless config), and an explicit
`pixelsize` for `st`, whose Alpine build ignores DPI entirely.

### Also settled today

- **16 KiB pages are not a boot blocker** (147). The DIET_CAPABLE kernel boots the proven Alpine root,
  which unblocks the `root=/dev/ram0` ext4 rehearsal (149). Keep this distinct from the *other* 16 KiB
  rule: an **enrolled object's total size** must still be a whole multiple of 16 KiB, and a tethered
  chainload bypasses iBoot so it cannot test that at all.
- **The kernel is reproducible again** (159). `drivers/tty/apple_dockchannel_tty.c` — 464 lines providing
  `/dev/ttydc0` — existed only as an *untracked* file inside the build containers, so a clean checkout
  silently built a kernel with no DockChannel shell and no transport for the health report. Recovered as
  a patch, verified by byte-identical reconstruction; a sweep found 9 of 11 other container-only edits
  already covered.
- **`console=ttydc0` is inert** (153): the shipping driver is a TTY only and registers no console, so
  kernel dmesg never leaves the machine. The panel is still the only source of dmesg, which is why
  screenshots remain necessary evidence. The patch that adds a real console applies cleanly — one rebuild.
- **Three harness defects fixed**: uploads into a dead proxy (157 — and note **every successful chainload
  destroys the proxy**, so a `debugusb-console.sh reboot` is required before *each* run); an orphaned
  uploader that corrupted two later runs (158); and a `chainload failed` verdict printed on *successful*
  boots (151).
- **An initramfs decode limit exists** (160). 13.1/50.8/60.5/97.3 MiB expanded all decode; **278.9 MiB
  fails** — m1n1 prints `XZ decode failed`, passes no initrd, and the kernel dies with
  `rdinit=/sbin/init failed: -2`. The verifier had caught this and the guard was wrongly raised; it is
  restored at 128 MiB. Capability-first still holds as a policy — but capability is what mattered
  (the *kernel*), not size.

### What the machine still lacks

No persistence (RAM root only, gated on USB/NVMe), no networking, **one core** (`maxcpus=1`), no
backlight control, no battery or temperature reading. Measured from the config rather than assumed:
`BRCMFMAC`/`CFG80211` are **already present**, so WiFi needs no kernel work and is gated purely on PCIe
op-115 (124); `APPLE_DWI_BL`, `MACSMC_POWER`, `HWMON` and `USB_USBNET` are **all absent** and are
therefore cheap, concrete wins (tickets 164–169).

## Status (2026-07-25) — 🐧 MILESTONE B0 REACHED: untethered boot (Alpine **and** Ubuntu)

**A cold boot from the Apple boot picker — no cable, no host — reaches an
interactive Alpine/OpenRC shell on the internal display.** Ticket 101 passed;
maintainer-confirmed on the panel with OpenRC at default runlevel, the Norwegian
`no-mac` keymap loaded, `watchdog0=present`, the internal keyboard on `event0`
(æ ø å correct), `simpledrmdrmfb`, empty `/proc/partitions`, empty network
runlevel, and `wallace-b0:~#`.

Enrolled object `m1n1-b0-diet-aligned.bin`
`f290833c8a9dd7ea4086571b925e6b775c113dd3b4626a7ef2644ebc76fd03fd`
(9,469,952 B = 578 × 16 KiB), enrolled from 1TR with
`kmutil configure-boot --raw --entry-point 2048 --lowest-virtual-address 0`.

**The root cause of every earlier enrolled failure: an enrolled raw boot object's
total size must be a multiple of the 16 KiB page size.** Any other length is never
executed — m1n1 is not entered at all and iBoot resets ~5 s × 5 before showing the
"needs to be reinstalled" screen. `scripts/t6040-build-raw-object.py` now pads and
asserts this. See `done/2026-07-25-t6040-B0-MILESTONE.md` and
`done/2026-07-25-t6040-enrolled-payload-rootcause.md`.

Also landed 2026-07-25: a **diet kernel** (16.8 MiB raw, −67% vs defconfig, with a
31-symbol boot-essentials assertion), **XZ payload members** (object 22.2 MB → 9.02
MiB before padding), the **Norwegian console keymap** (BusyBox provides `loadkmap`
reading a binary keymap on stdin — there is no `loadkeys` and no applet symlink),
and a read-only probe showing **m1n1's own NVMe path SErrors on T6040**
(`nvme_init()` → async L2C SError), so the NVMe boundary is enforced below the OS.

**Both distro targets boot untethered:** Alpine 3.24/OpenRC (musl, 9.03 MiB object, with
a 10-second USB-serial debug window — proven both ways: host attaches and takes control,
or times out into Alpine) and **Ubuntu 24.04 (glibc, 22.59 MiB object)**, the latter
proving large-payload decompression works (16.8 MiB XZ member, 97.3 MiB cpio unpacked
into RAM). No enrolled-object size ceiling was found up to 256 MiB; 16 KiB page alignment
is the only constraint.

Persistent USB root still depends on the HPM/ATC host link (tickets 096/097, or
U-Boot via 128) — **B0 no longer depends on any of it.**

## Status (2026-07-24)

The tethered B0 release object now boots a self-contained Alpine 3.24/OpenRC
system from one raw m1n1 object. The internal panel reaches a local shell, the
internal keyboard echoes, the watchdog stays serviced, and the storage-disabled
health report passes. A dual-mode enrollment candidate has also been built; it
passed a conditional independent review and preserves every post-m1n1 byte of
the live-proven object. Its version tag and exact Rust nightly must be pinned
before claiming full rebuild reproducibility. Volume identity/backup and the
maintainer's execution split still block ticket 101; its display/DebugUSB
trigger behavior is deliberately a separate live validation.

Core bring-up is solid: m1n1 sees all 14 active cores, PMGR's 214-domain
topology is understood, Linux boots reliably at `maxcpus=1`, fbcon and
DockChannel polling console work, and the internal keyboard is usable.
The first exact `maxcpus=2` proof (005) reached kernel vectoring but produced
no Linux output, so 122/123 now own the diagnosis/replacement before all-core
120/121 or cpufreq 006. Offline diagnosis 122 is complete: its reproducible,
storage-disabled early-DockChannel candidate passed independent exact-artifact
review and can reveal the previously blind boot interval. Live ticket 123
remains proposed because it was created after the last manual approve-all; it
requires fresh explicit approval. Interrupt-driven DockChannel on measured AIC
input 816 has passed with stable bidirectional shell traffic. Trackpad motion
candidate 004 was retired unrun after review found a missing HID type fix and
modular multitouch without modules. Offline replacement 125 was corrected,
byte-reproduced, and independently passed; live 126
still requires fresh approval, a narrow volatile-runtime-firmware policy
exception, and attended finger motion.

The right-side USB-C path has crossed its first hardware-management boundary.
The exact right HPM2 endpoint accepted WAKEUP, reported state `0x07`, accepted
the public-driver `SSPS` sequence, and reported S0 (`0x00`). That does not yet
establish connector role, VBUS, repeater/ATC PHY, xHCI enumeration, or block
access. Final static rollback review found semantic USB/PHY teardown but no
complete VBUS, event/cache/mask/detect, or pre-SSPS-state inverse, so R3 and
the USB link experiments are blocked pending new primary evidence. The
attached memory stick has therefore **not** enumerated on the M4 and has not
been written. A host-verified OpenRC GPT/ext4 root image is ready.

Internal NVMe remains blocked by Apple's SPTM/CoastGuard guarded state. We have
decoded the protected operation contracts, but raw boot has no supported path
to acquire the required execution/domain context. Work here stays static and
host-only unless a documented, non-mutating guarded-entry route appears.

PCIe, which carries WiFi/BT and the SD reader, still stalls at operation 115,
the first PHY-IP PLL read. Ticket 068 proved the newly decoded clkgen sequence
locks its PLL, but the read still hangs; offline ticket 124 owns the next
paired-driver precondition trace.

DebugUSB/KIS remains the practical remote console. The post-SSPS recovery
control passed after a power cycle and several later reboot/reattach cycles
returned healthy proxies. Ticket 118 records the exact fail-closed checklist;
the earlier VDM failure is not attributed to SSPS.

Polling remains the conservative DockChannel fallback, while the corrected
IRQ-816 path is now independently reviewed and live-proven.

The blow-by-blow lives in [DEVLOG.md](docs/DEVLOG.md), and the current plan of attack is [NEXT_STEPS.md](docs/NEXT_STEPS.md).

## The repos

| Path | What |
|---|---|
| `~/Code/wallace` | this repo: docs, `scripts/`, `patches/`, `dts/`, `done/` |
| `~/Code/m1n1` | m1n1 fork (bootloader + proxyclient); safety rules live in its `AGENTS.md` |
| `~/Code/m1n1-clean` | worktree of branch `t6040-bringup`, the curated upstream-shaped commit series |
| `~/Code/linux` | `damsleth/linux` fork, branch `wallace/t6040-bringup`, based on AsahiLinux `asahi-wip`; t6040 DTs live here |
| `~/Code/linux-build-out` | build artifacts, mounted as `/out` in the build container |
| `~/Code/macvdmtool` | patched fork: DebugUSB entry + remote reboot |
| `~/Code/kisd` | AsahiLinux kisd, bridges DebugUSB to a pty on the host |

## The loop

```sh
bash scripts/t6040-debugusb-console.sh reboot   # reboot into m1n1, drain console, attach kisd -> /tmp/m1n1
bash scripts/t6040-boot-dcuart.sh               # chainload m1n1 + boot Linux to a shell on /dev/ttydc0
printf 'uname -a\n' > /tmp/m1n1                 # type into the running machine
tail -f ~/Code/linux-build-out/dcuart-console.log
```

Kernel rebuild (arm64-native in a podman container, because macOS's case-insensitive filesystem corrupts a kernel tree in about four files):

```sh
cp scripts/t6040-kbuild.sh patches/*.patch ~/Code/linux-build-out/
podman exec -e DOCKCHANNEL=1 -e BUILD_DIR=/build/linux-keyboard kbuild \
    bash /out/t6040-kbuild.sh image
```

Before touching any of this, read the pty-discipline rules in [DEVLOG.md](docs/DEVLOG.md). The link looks completely dead if you handle the pty wrong, and we burned an hour learning that.

## Reading order

1. [AGENTS.md](AGENTS.md), the map (repos, roles, hard rules)
2. [RUNBOOK.md](docs/RUNBOOK.md), every operational command in one place
3. [NEXT_STEPS.md](docs/NEXT_STEPS.md), the work queue
4. [DEVLOG.md](docs/DEVLOG.md), recipes, solved blockers, dead ends
5. [ROADMAP.md](docs/ROADMAP.md), stages A through H, from first light to daily driver

`done/` holds the finished per-topic plans and session write-ups. They're kept because the dead ends are half the value: SBU serial, RAM-dump post-mortems, and per-domain pmgr bisection are all documented graves, so nobody digs them up twice.
