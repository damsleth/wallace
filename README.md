# Project Wallace

Mainline Linux on a MacBook Pro 14" M4 Pro (t6040 "Brava Chop",
Mac16,8 / J614s). It boots **untethered** into Alpine/OpenRC — enrolled boot object, internal
panel, keyboard (Norwegian), watchdog — with a remote DebugUSB loop for development.

This repo is the umbrella. The code lives in four sibling repos and the knowledge kept getting smeared across them so everything that guides the work now lives here: plans, scripts, kernel patches, post-mortems.

## Status (2026-07-26, later) — 16 KiB-page kernel cleared, PCIe PHY-init decoded

**Ticket 147 passed: the 16 KiB-page DIET_CAPABLE kernel boots on T6040.** Alpine 3.24 came up with
the health report begin→end, `simpledrmdrmfb`, the internal keyboard on `event0`, `watchdog0=present`,
an empty network runlevel, the Norwegian `no-mac` keymap loaded, and a shell prompt — no panic, no
NVMe/xHCI/usb-storage, nothing mounted. `PAGE_SIZE_16KB` (forced by `PCIE_APPLE`) is therefore **not**
a boot blocker, which unblocks the `root=/dev/ram0` ext4 rehearsal (149). Both 148 (dwm) and 149 are
now built, hash-verified and staged.

One acceptance criterion needed interpreting rather than a literal reading: `/proc/partitions` is not
empty on this kernel. That criterion came from the 4 KiB diet kernel, which has no block layer at
all, whereas DIET_CAPABLE exists precisely to re-add `BLK_DEV_RAM`/`MTD`. `ram0` matches the config
exactly, and `mtdblock0/1` turned out to be **m1n1's own debug nodes** — `m1n1_stage2.log` (16 KiB)
and `adt` (`0x94000`, exactly the ADT size the proxy reports), RAM-backed and read-only, patched into
the live devicetree by m1n1 and thus absent from the on-disk DTB. Not storage; the storage-free
premise holds (ticket 150, closed). It also hands us a new capability: m1n1's stage2 log and the full
ADT are readable from Linux userspace with no tether (ticket 152).

**Two independent 16 KiB facts, easy to conflate and worth keeping apart.** An *enrolled* object's
**total size** must still be a whole multiple of 16 KiB or iBoot never enters m1n1 (yesterday's root
cause, unchanged). That is separate from the kernel's **page size**, which is what 147 cleared. Both
are 16 KiB only because that is the Apple Silicon native page size. 147 could not have tested
alignment at all: a tethered chainload hands the object to `chainload.py` and bypasses iBoot.

Three attempts were needed, and the first two booted the wrong object — a positional argument the
script ignored, then `VAR=…; VAR=…; cmd` semicolons that kept the assignments shell-local. Both times
it silently fell back to a hardcoded default and its SHA guard *passed*, because it validated the
default it had chosen for itself. `scripts/t6040-boot-raw-object.sh` now has **no default object**:
the object and its sha256 must be named on every run, with a positional two-argument form that
survives semicolon-pasting. Filed 151 for the related hazard that the harness prints
`chainload failed` on a *successful* boot (`chainload.py`'s closing `iface.nop()` must time out once
Linux takes the UART), plus 153 (capture kernel dmesg so smokes self-verify) and 154 (assert kernel
page size at build time).

## Status (2026-07-26) — daily-driver object + graphical/ramroot targets, PCIe PHY-init decoded

Built on the B0 milestone. The **dual-mode daily-driver object** is the standing boot
target: a cold boot waits 10 s for a USB-serial host to take control, then falls through to
the Alpine shell on the internal panel — maintainer-confirmed both ways (host attaches; or
times out into Alpine). Two further untethered targets are built and strict-verified, awaiting
KIS observation: an **Xorg + dwm graphical** object (`m1n1-b0-alpine-dwm.bin`, trimmed
290→65 MiB by dropping the llvmpipe/gallium JIT stack) and a **`root=/dev/ram0` ext4** object
(`m1n1-b0-ramroot-ext4.bin`) rehearsing a RAM-backed root. A **DIET_CAPABLE kernel**
(`Image-b0-dietcap`, 33.7 MiB) re-adds NET/WLAN/BRCMFMAC/PCIE_APPLE/BLK_DEV_RAM/EXT4/PHRAM and
is built with `ARM64_16K_PAGES` (PCIE_APPLE requires 16 KiB pages — an ABI change from the
proven 4 KiB B0 kernel, so it needs its own live smoke).

PCIe RE advanced: ticket 124 decoded `ApplePCIEBaseT8132::_initializePhy()`. The first PHY-init
hardware op is a read-modify-write of **PhyCommon register `0x0`, setting bit 0**, in a shared
PHY aperture where PhyCommon lives at `+0x4000` and PhyPhy at `+0x8000`; PHY-IP reads dereference
a cached per-port base at `this+0x240` (so 068's hang is a non-responding aperture, not a null
pointer). The reg indices are ADT `reg-names`-derived per-instance ivars, not constants — so any
m1n1 change must resolve these from the ADT. The grounded candidate for the missing precondition:
m1n1 skips the shared-PHY-aperture init entirely before reading PHY-IP. 068 stays un-retried until
the remaining PhyPhy pairs and ADT reg-names are pinned. See
`done/2026-07-26-t6040-pcie-initializephy-trace.md`.

Also settled: **096** — `AppleHPMInterface::roleSwap()` issues SWDF/SWUF 4CCs with no VBUS-off
and no flash/OTP command in the vocabulary (no persistent-brick vector); **128** — U-Boot's
atcphy answer is NO for this path. Rig smokes (146–149) are queued against the proxy tether now
that the rollback loader is enrolled.

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
2. [NEXT_STEPS.md](docs/NEXT_STEPS.md), the work queue
3. [DEVLOG.md](docs/DEVLOG.md), recipes, solved blockers, dead ends
4. [ROADMAP.md](docs/ROADMAP.md), stages A through H, from first light to daily driver

`done/` holds the finished per-topic plans and session write-ups. They're kept because the dead ends are half the value: SBU serial, RAM-dump post-mortems, and per-domain pmgr bisection are all documented graves, so nobody digs them up twice.
