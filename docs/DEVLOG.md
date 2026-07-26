# t6040 (M4 Pro, Mac16,8 / J614s) Linux bring-up — DEVLOG & operational reference

State of the world, how to operate the rig, solved blockers, investigation
history, and dead ends. Forward-looking work lives in `NEXT_STEPS.md`; the
long-term plan in `ROADMAP.md`; per-session write-ups in `done/`.

## Current working state (2026-07-24)

| Works | Notes |
|---|---|
| Mainline Linux to Alpine 3.24/OpenRC | tethered self-contained B0 object passed; storage-disabled, `maxcpus=1 idle=nop` |
| Two-way m1n1 proxy/console over DebugUSB (KIS) | one DP/TB cable in the DFU port; no second machine-side cable needed |
| Two-way **Linux shell** on `/dev/ttydc0` over the same cable | poll-mode fallback plus live-proven interrupt mode on measured AIC input 816 |
| Internal keyboard at the local panel shell | DockChannel HID type fix; corrected trackpad-motion candidate 125 byte-reproduced/reviewed, live 126 unapproved |
| Framebuffer console (simpledrm + fbcon) | B0 panel shell and local keyboard echo live-proven |
| Linux `apple_wdt` takes over m1n1's watchdog | shell survives past the 20 s bite |
| Remote reboot via `macvdmtool` | post-095 recovery control and later cycles healthy; exact fail-closed checklist in ticket 118 result |
| Right HPM2 WAKEUP + SSPS | state `0x07` → S0 `0x00`; role/VBUS/PHY/xHCI/device access not proved |
| OpenRC external-root image | host-verified GPT/ext4 image ready; stick not flashed or enumerated on M4 |

Active: seek new primary evidence for the HPM/ATC rollback no-go,
fill the maintainer-only B0 volume/backup/action fields, and obtain fresh
approval for reviewed SMP ticket 123. Trackpad ticket 125 is complete; live
126 remains unapproved and policy/attendance-gated. USB enumeration remains
decomposed behind the rollback gate,
read-only block access, flashing, and bounded write tests. Internal NVMe
remains behind SPTM/CoastGuard. Trackpad firmware and the paired firmware
corpus are staged. Parked: USB gadget console (EP0 dies post-enumeration;
`done/2026-07-11-t6040-usb-gadget-plan.md`).

**Recovery status:** after ticket 095's successful SSPS-to-S0 run, one VDM
recovery and bounded reattach failed. Ticket 118's later control passed after a
maintainer power cycle: fresh KIS, raw PTY, `Running proxy`, and the bounded
T6040 health check all passed. Several subsequent reboot/re-entry cycles were
healthy. Keep the fail-closed checklist; do not attribute the original
transient to SSPS.

## Operating the rig

### The DebugUSB (KIS) link

`bash ~/Code/wallace/scripts/t6040-debugusb-console.sh [reboot]` — starts kisd,
sets its PTY raw, attaches a background reader to `/tmp/m1n1-console.log`,
enters DebugUSB via `sudo -n macvdmtool [reboot] debugusb`, and symlinks the
kisd pty to `/tmp/m1n1`. `M1N1DEVICE=/tmp/m1n1` for all proxyclient tools;
`screen /tmp/m1n1` for an interactive console. kisd auto-detects the t6040 KIS
base 0x548700000;
kisd uart channel 0 = dock side of AP `/arm-io/dockchannel-uart` (AP data block
0x50882c000 + 0x40004000 = 0x548830000; same offset on t8140).

**Hard-won operational rules (skip these and the link "dies"):**
1. **Put every fresh kisd pty into raw mode, then attach a reader at (almost)
   all times:** `stty -f /tmp/m1n1 raw -echo; cat /tmp/m1n1`. With
   nobody reading, ~15 KB of boot output fills the pty buffer, kisd blocks, and
   the KIS stream wedges into an apparently one-way link (writes ACK at the USB
   level, nothing ever returns). Recovery: `pkill kisd`, restart kisd, re-enter
   `sudo -n macvdmtool debugusb`, attach `cat` immediately.
   On macOS, kisd cannot set raw mode on its PTY master. A canonical reader
   drains the text log but interprets byte four of m1n1's binary startup reply
   (`ff 55 aa 04`) as VEOF. The exact signature is a ~15,044-byte log ending
   in only `ff 55 aa`, followed by proxy timeouts with zero reply bytes.
2. **Never leave a `cat` running while a proxyclient tool uses the pty** — it
   steals reply bytes. The recovery helper now owns the initial reader;
   `t6040-boot-dcuart.sh` kills it before proxyclient and reattaches after the
   handoff. For manual tools: kill reader → run tool → reattach reader.
   With `reboot`, the recovery helper does not return until it has seen
   `Running proxy` and three unchanged one-second console-size samples.
   Short-lived automation must set `T6040_KEEPALIVE=1` when invoking either
   console helper; this keeps its process group alive instead of relying on
   `nohup`, which the automation runner reaps when the parent command exits.
3. First proxy attempt after a boot often hits `UartCMDError` (desync from
   leftover console bytes) — **just retry once**.
4. Reboot → "Running proxy" takes **<20 s**. Poll every 2–3 s; never wait minutes.
5. DebugUSB replaces m1n1's dwc3 gadget on the DFU port (no `/dev/cu.usbmodem*`
   while active). A plain cable in another target port coexists for fast
   chainload. On J614s the proven DFU/KIS port is left-back (top-left when
   viewed in the working rig orientation): ADT maps it to `usb-drd0`; keep that
   controller disabled in Linux USB-host tests. Upstream reports also warn that
   direct C-to-C gadget links can lose role negotiation; a known Apple charging
   cable or a hub/A-to-C path is a useful fallback after checking the physical
   port and power-cycling.
6. `t6040-boot-dcuart.sh` passes linux.py `--no-tty`, then owns the raw reader
   transition itself. Older m1n1 trees lack that option and end handoff with a
   harmless miniterm/termios traceback after the kernel is already booting.
   Live-verified with build #15: linux.py exits normally, the helper attaches
   its reader immediately, and BusyBox arrives without traceback noise.

Host prerequisites: root-owned `/usr/local/bin/macvdmtool` (patched fork at
`~/Code/macvdmtool`: new cmds `actions`/`vdm`/`dven`/`localserial`) with a
NOPASSWD sudoers entry; `/usr/local/bin/kisd` (AsahiLinux/kisd, builds on macOS
as-is). proxyclient pty support is committed (`proxyclient: support pty devices`).

### Boot recipes

**Linux with the DockChannel shell (the standard loop):** target at m1n1
"Running proxy" with kisd attached →
`bash ~/Code/wallace/scripts/t6040-boot-dcuart.sh` (defaults:
`t6040-j614s-dcuart.dtb` + `initramfs-dcuart.cpio.gz`). Chainloads
`build/m1n1.bin`, uploads over the pty, hands off, attaches a reader. Console
tails to `~/Code/linux-build-out/dcuart-console.log`; type with
`printf 'cmd\n' > /tmp/m1n1`.

**Framebuffer-console variant (for pre-userspace debugging):**
`bash ~/Code/wallace/scripts/t6040-bootcap-fb.sh <dtb> <initramfs>` over a plain-cable
proxy (`/dev/cu.usbmodemJ22GYCN4YG1`). Output on the laptop panel. Cmdline:
`maxcpus=1 idle=nop nokaslr pd_ignore_unused clk_ignore_unused console=tty0
fbcon=font:TER16x32 ignore_loglevel`. `EXTRA_BOOTARGS=initcall_debug` to trace
init hangs. A hung kernel warm-resets in ~20 s (m1n1 arms WD1 before handoff).

**Initramfs:** `bash ~/Code/wallace/scripts/t6040-make-initramfs.sh` (defaults:
INIT_SOURCE=`scripts/t6040-init-dcuart`, DEST=`initramfs-dcuart.cpio.gz`).
The init holds an fd open on ttydc0 for the life of init (the tty driver does
not enjoy full close/reopen cycles), prints a `[dcuart] spawning shell` marker,
respawns `busybox sh -i <>/dev/ttydc0` via setsid, pets `/dev/watchdog0`, and
keeps the fbcon shell as before.

### Kernel build

Native mac builds are impossible (case-insensitive FS corrupts the tree);
everything builds arm64-natively in the podman container `kbuild`
(see memory `t6040-kernel-build-env`). Kernel tree: `~/Code/linux`, branch
`wallace/t6040-bringup` in `damsleth/linux`, based on AsahiLinux `asahi-wip`;
yuka's fork remains available as the `yuka` remote for M4/M5 topic work.
Working build dir inside the container: `/build/linux-keyboard`.

```
cp ~/Code/wallace/scripts/t6040-kbuild.sh ~/Code/wallace/patches/*.patch ~/Code/linux-build-out/
podman exec -e DOCKCHANNEL=1 -e BUILD_DIR=/build/linux-keyboard kbuild \
    bash /out/t6040-kbuild.sh image
```

kbuild.sh clones committed state, copies in the t6040 DT files from `/src`,
applies `/out/flokli-code.patch` (aic locked-sysreg skip + arm64 `idle=` param),
imports the DockChannel series (`origin/dockchannel`: mailbox `d2acb86f70a2`,
tty `b8dcbdcb`, HID transport) with `DOCKCHANNEL=1`, applies
`t6040-dockchannel-fixes.patch` (hid .stop) and `t6040-dockchannel-poll.patch`
(apple,poll-mode), forces the fbcon config, and builds Image + DTBs to `/out`.

- **BUILD GOTCHA:** the build uses COMMITTED kernel code + copies only DT
  files. Uncommitted host code edits are silently dropped — put code changes
  in a patch applied by kbuild.sh.
- `PMGR_FUNCTIONAL=1` additionally applies `t6040-pmgr-functional.patch` for
  the full-pmgr experiments.
- Fast DTB-only rebuild: `podman exec kbuild bash -c 'cd /build/linux-keyboard
  && make ARCH=arm64 apple/<name>.dtb && cp arch/arm64/boot/dts/apple/<name>.dtb /out/'`
  (explicit dtb targets build without a Makefile `dtb-y` entry).
- **zsh gotcha:** unquoted `$var` does not word-split.

DT sources: `t6040.dtsi` / `t6040-j614s*.dts` / `t6040-pmgr.dtsi` in
`~/Code/linux`.  The remaining board state was committed on 2026-07-23,
including measured DCUART IRQ 816 and the corrected 14-inch identity.  The
upstream-shaped draft is `patches/linux-t6040-j614s-dt-v1/`; validation and
known schema prerequisites are recorded in
`done/2026-07-23-t6040-linux-dt-series.md`.

Known-good artifacts (in `~/Code/linux-build-out/`), kernel build #15:
- `Image` `14da8640398fc64b89d9241a75be0ffc8d4260b681068a3c27251cc79c3abaf4`
- `t6040-j614s-dcuart.dtb` `a99ad7c3f304198280814de1e4a31d83c268751af608afad7003aa982a69f65a`
- `initramfs-dcuart.cpio.gz` `512c69da94884f3ea83f9a6a4ea0731dcad6b5aaa87eb875ca5a6d7b24c317ca`

m1n1: `export PATH="$(brew --prefix llvm)/bin:$PATH"; make -j8` →
`build/m1n1.bin`. All t6040 changes are committed on `main`; the curated
code-only series lives on branch `t6040-bringup` (worktree `~/Code/m1n1-clean`).

## Solved blockers

### The 5 original M4 raw-boot blockers (common root: SPTM/firmware-locked resources trap)
1. **m1n1 async L2C SError at kboot handoff** — the dapf init; on t6040 ALL
   dapf entries trap. Fixed in `src/dapf.c` (`dapf_skip_entry()`), refined to
   still allow dart-mtp programming (keyboard needs it).
2. **AIC locked-sysreg trap** — `aic_init_cpu` writes
   `SYS_IMP_APL_VM_TMR_FIQ_ENA_EL2` + `SYS_ICH_HCR_EL2` in hyp mode → traps →
   hang before console. flokli patch comments out both (in `flokli-code.patch`).
   Upstream testing on 2026-07-21 still classified T6040/T6041 as locked even
   on macOS 26.6 RC / 27 beta 4; do not remove this patch. Cluster-power-off
   sysregs remain unresolved as well.
3. **WFI state-loss** — M4 loses CPU state on WFI/WFE; flokli patch adds arm64
   `idle=[wfi|nop]`; boot with `idle=nop` (plain mainline ignores `idle=`).
4. **No fbcon in defconfig** — DRM_SIMPLEDRM + DRM_FBDEV_EMULATION +
   FRAMEBUFFER_CONSOLE + ARM64_SME=off, forced by kbuild.sh.
5. **Fuller-DT hang = pmgr** — see PMGR section below; isolated and worked
   around with a proven minimal policy.

### Internal keyboard (2026-07-11, session 4) — three independent bugs
(a) m1n1 skipped dart-mtp DAPF programming on t6040 (src/dapf.c);
(b) t6040.dtsi ASC mailbox IRQs were pairwise swapped — Apple's ADT lists
not-empty first per pair, the binding wants ascending;
(c) dockchannel-hid lacked hid_ll_driver `.stop` → NULL-deref oops
(`patches/t6040-dockchannel-fixes.patch`). Full story:
`done/2026-07-11-t6040-mtp-wake-findings.md`.

### Trackpad firmware path (2026-07-12, session 5)

The upstream-oriented DockChannel transport is deliberately keyboard-only: it
omitted the older Asahi driver's external firmware upload, while M2-and-newer
multi-touch requires a board-paired blob produced by `asahi-fwextract`.
`patches/t6040-dockchannel-trackpad-fw.patch` restores the bounded HIDF loader,
runtime interface-number patch, coherent-DMA upload, post-upload reset, and
retry-safe error cleanup. J614s DT names `apple/tpmtfw-j614s.bin` (Linux commit
`6399cdc1bb94`).

Kernel build #12 (`Image` SHA-256 `93c33ea10dddcc69b50c39a7c0b64a7a8d9c5485bfcc94119839ed4501fdadfb`)
booted to BusyBox. Two event0 opens independently returned `-ENOENT` for the
missing blob; neither sent command `0x40`, timed out, nor left `starting` stuck.
Use `TRACKPAD_FIRMWARE=... scripts/t6040-make-initramfs.sh` after extracting the
paired file; the script now validates its HIDF header and bounds before copying
it. Current upstream `asahi-installer` needs no J614s mapping: its generic
multitouch collector scans every `j*` directory and names the result from that
directory. Ticket 016 reproduced the board-paired file directly from the
canonical 25F84 restore identity: `Firmware/J614s_Multitouch.im4p` converts
through the unmodified Asahi collector to `apple/tpmtfw-j614s.bin`, SHA-256
`a1f4131d0cb7caf6fa15b19f47725458a6d7b0e3a34f15169339d5541663d9e2`.
The proprietary file is staged under
`/private/tmp/t6040-paired-fw-25F84/vendorfw/apple/`; the pinned ranged
extractor and evidence are in
`done/2026-07-23-t6040-trackpad-firmware-provision.md`. GPIO proxying remains
intentionally absent until any request and
its J614s ADT mapping are captured and reviewed. A later ADT-only capture found
`function-afe-reset = pKW4('gp1c', 0x10000)` through phandle 294,
`/arm-io/smc/iop-smc-nub/smc-pmu`. The legacy pulse would write SMC key `gp1c`
as `0x10001` then `0x10000`; do not implement or exercise it under the absolute
no-PMU-write rule. Details:
`done/2026-07-12-t6040-trackpad-firmware.md`.

The first 2026-07-24 ticket-004 rebuild pinned a byte-reproducible candidate:
Image `86e031db...`, storage-disabled DTB `2782b922...`, and paired-firmware
initramfs `3a47c95d...`. The dedicated init automatically emits registration,
dmesg, and a bounded 12-second event read over ttydc0 TX, avoiding the current
RX regression. The initramfs builder now uses
`scripts/reproducible-newc.py` plus `gzip -n`; this removes BSD cpio's temporary
host-inode nondeterminism. The base archive contains no hardlinked regular
files or special nodes, and two fresh archives byte-match.

Independent review retired those exact bytes unrun: they omitted the proven
DockChannel `hid->type` fix and left `HID_MULTITOUCH=m` while the RAM image
contains no modules, so no multi-touch event node could bind or trigger the
runtime HIDF path. Offline replacement 125 added the type fix and built-in
multitouch; two independent builds byte-match at Image `446eeb2e...`, and
independent exact-artifact review passed. Proposed live ticket 126 remains
unapproved. It also requires an explicit narrow exception to the unqualified
firmware-write rule for the exact paired, volatile, non-persistent runtime
upload. It never authorizes flash/NVM or GPIO/PMU reset. Full manifests and
reviews:
`done/2026-07-24-t6040-trackpad-motion-preflight.md` and
`done/2026-07-24-t6040-trackpad-motion-crossreview.md`, plus
`done/2026-07-24-t6040-trackpad-motion-revised-preflight.md`.

### First-secondary visibility (2026-07-24, tickets 005/122/123)

Ticket 005 ran its exact reviewed `maxcpus=2` set once. m1n1 prepared the
kernel and vectored to Linux, but the polling DockChannel owner emitted no
Linux line in the bounded window. Recovery returned a healthy proxy. This
correlates the loss of visibility with enabling a secondary; it does not prove
that the secondary itself caused the failure. Do not retry 005 unchanged.

Ticket 122 corrected the topology model: the physical boot CPU is P-core
`smp_id=4`, which arm64 numbers logical CPU0; the first secondary expected as
logical CPU1 is E-core `smp_id=0`. Source audit also confirmed that repeated
`maxcpus=` options are processed left-to-right, m1n1 releases all secondaries
to WFE park addresses, and the T6040 AIC locked-sysreg skips remain required.

The replacement adds a diagnostic earlycon confined to the already-proven
DockChannel data window. Per byte it reads `TX_FREE` once at `+0x14`, drops
immediately if full, and otherwise writes TX8 at `+0x04`; there is no wait,
RX, configuration, IRQ, or new offset. The exact bootarg suffix is:

```text
maxcpus=2 earlycon=dockchannel,mmio32,0x50882c000 keep_bootcon initcall_blacklist=apple_dctty_init
```

The blacklist prevents the normal UART client from becoming a second TX
owner, while a reproducible kmsg-only init reports CPU masks and pinned
liveness without requiring tty RX. Independent exact-artifact review passed.
Offline 122 is done; live ticket 123 remains proposed and needs fresh
maintainer approval because it was created after the last approve-all. Full
hashes, ownership proof, and stop contract:
`done/2026-07-24-t6040-maxcpus2-earlycon-analysis.md`.

### BCM4388 wireless firmware corpus (2026-07-14, ticket 014)

The `apple,mriya` WiFi/BT firmware (chip 4388 **C2** per the 25F84 Bluetooth
tree) was initially staged at `/private/tmp/t6040-vendorfw/` with a SHA-256
inventory, derived from the canonical Mac16,8 macOS 26.5.2 (25F84) IPSW:
ranged fetch of
only the BaseSystem member, AEA-decrypt, then the unmodified asahi-installer
collectors. Key 26.x finding (feeds ticket 026): the installer flow breaks on
26.x images — BaseSystem is `.dmg.aea`, WiFi payloads moved from
`usr/share/firmware/wifi` (now dangling symlink stubs) into the AppleBCMWLAN
dext's `Firmware/` tree, new `AMKOR` BT vendor and new filename forms
(`F-` dim, `*_gen*.clmb`, `.pcfb`) are unhandled. `t6040-make-initramfs.sh`
gained a tested `VENDORFW_DIR` hook installing the 14-file mriya set. Usability
is gated on PCIe port-0 (op-115) + a `brcmfmac`/`hci_bcm4377` kernel build.
Full provenance, hashes, layout notes, and the regeneration recipe:
`done/2026-07-14-t6040-bcm4388-fw-extract.md`.

Ticket 030 consolidated that slice with the exact non-iBoot FUD set, all six
ISP setfiles, the kernel-embedded ASMedia blob, and trackpad output. The
deterministic raw archive is
`/private/tmp/t6040-paired-fw-25F84/j614s-25F84-raw-firmware.tar.gz`
(`cb7a4ee2...`, mode `0444`); the directly consumable 22-file tree is
`/private/tmp/t6040-paired-fw-25F84/vendorfw/`. The builder pins and hashes
the restore, BaseSystem, kernelcache, and asahi-installer commit, asserts the
five-member FUD selection and every Linux output hash, and refuses overwrite.
Machine-private ALS data cannot come from an IPSW and is split to ticket 087
for a read-only capture from the M4's macOS installation. Its exact
upstream-derived capture procedure and fail-closed extractor are now prepared;
the corrected private-file procedure passed independent review, and only an
attended main-macOS boot remains. Exact results:
`done/2026-07-24-t6040-als-calibration-preflight.md` and
`done/2026-07-24-t6040-paired-fw-corpus.md`.

Ticket 026 audited current asahi-installer at `c53d66dc7193`. Its second-stage
raw `kmutil` invocation already matches M4; the missing pieces are
`j614sap`/`0x6040` admission, atomic handling of a complete raw m1n1 Linux
payload (the legacy `STACKBOT` variable upgrader cannot preserve one), and
macOS 26 AEA plus changed Wi-Fi/Bluetooth layouts. The J614s multitouch
collector already works generically. Exact requirements and upstream patch
split: `done/2026-07-23-t6040-asahi-installer-requirements.md`.

### DockChannel-UART Linux console (2026-07-12)
Kernel side: `origin/dockchannel` mailbox + tty drivers + a t6040 board DT
variant. **Correction 2026-07-21:** the ADT declares AIC IRQ 360, but a bounded
m1n1 experiment on an M4 Pro measured the real DockChannel-UART interrupt at
**AIC input 816**. UART RX is BIT(1); MTP RX is BIT(3). The base J614s DT now
carries 816, while the working fallback remains
`apple,poll-mode` (5 ms delayed work; TX-done on FIFO drain, RX via RX_COUNT).
`patches/t6040-dockchannel-poll.patch` now accepts explicit per-instance masks;
a full record of the old IRQ-360 runs is in
`done/2026-07-14-t6040-dockchannel-irq-retest.md`,
`done/2026-07-14-t6040-dockchannel-irq-tx-report.md`, and
`done/2026-07-14-t6040-dockchannel-rxirq-txpoll-result.md`.

Those runs are historical only. Their direct observations remain valid—the
last probe never entered the AP FIFO—but none exercised the real AIC route, so
they say nothing about input 816. Do not retry ticket 059 or publish the old
scan as a hardware erratum.

ACK-order audit: safe m1n1 `eed11760` never touches the UART IRQ mask/flag
block, so it cannot leave BIT(3) set before handoff. The older working
DockChannel/HID driver uses RX BIT(1), W1C-acks and masks the child before its
thread reads and consumes the packet, then re-arms RX. The current mailbox
driver W1C-acks but leaves RX locally unmasked while waking its drain thread.
Any new interrupt-path test must use input 816 and be separately reviewed.

MMIO caution: the dockchannel-uart block maps ONLY +0xc000 (irq, 24 B) and
+0x28000..+0x38004 (config/data). Reading other offsets (e.g. +0x20000) raises
an async SError that kills m1n1 — unlike dockchannel-mtp, which maps
+0x0/+0x14000/+0x28000../+0x30000..

The current mailbox tty driver registers no printk console — `console=ttydc0` does
nothing; the shell + dmesg cover post-userspace, fbcon covers early boot. A
code review confirmed that simply adding `register_console()` would be unsafe:
TTY TX only enqueues into a kfifo and schedules `system_wq`, so it cannot emit
synchronously in atomic/panic context, and its send-error path can printk while
holding the same TX lock a console callback would need. A real console requires
a separate bounded polled/atomic mailbox transmit primitive (preferably nbcon),
not reuse of `apple_dctty_write()`.

Upstream WIP now supplies that separate shape: Yuka's `more-t6041` branch uses
`compatible = "apple,dockchannel-uart"`, orders registers data/config/irq so
earlycon can map the FIFO, uses IRQ 816, and reached a shell on M4 Pro with
`earlycon=dockchannel,mmio32,0x50882c000`. Its console is `ttyDC0`. Treat the
driver as an offline input, not a board DT to copy: the branch's inherited CPU
and memory-channel topology does not match 14-core J614s. Full evidence and
commit identities: `done/2026-07-21-asahi-dev-log-review.md`.

### Right-port USB2 host smoke (2026-07-21)

The reviewed one-port/no-root image booted once under ticket 063. Linux
initialized the right-port DART pair (`0x392f00000`, `0x392f80000`) and xHCI
at `0x392280000`/IRQ 42, created its USB2/USB3 root hubs, and registered UAS and
usb-storage. The initial and ten-second reports both showed root hubs only:
no external child and no `sd*`. DockChannel stayed interactive and no SError,
DART fault, reset, or internal-NVMe probe occurred. Recovery returned a stable
proxy.

This proves the DWC3/xHCI and DART description reaches working Linux root hubs,
but not the physical Type-C link. The saved ADT maps the right port through
`hpm2` (SPMI), `atc-phy2` (`atc-phy,t6040`), and `acio2`; the Linux DT exposes
none of those nodes or their connector graph. Its DWC3 generic PHY handles are
therefore absent, so force-host starts xHCI without establishing cable
orientation, eUSB2-repeater state, or USB2 host mode. m1n1 leaves some inherited
PHY state, but does not consume the T6040 named host/device tunables, so that
state is not a reproducible Linux contract.

Do not mount or populate a rootfs. The failed device is confirmed to have been
a directly attached, bus-powered USB-C memory stick. At this point ticket 065
proposed one powered-fixture discriminator; it was later cancelled unrun, as
recorded immediately below. The active plan now keeps the same passive stick
and stages reviewed T6040 HPM/SPMI + ATC PHY support. Full historical result,
analysis, and cancelled powered preflight:
`done/2026-07-21-t6040-usb-host-right-smoke-result.md` and
`done/2026-07-21-t6040-usb-right-no-connect-analysis.md`, then
`done/2026-07-21-t6040-usb-right-powered-smoke-preflight.md`.

### Alpine RAM-root fallback (2026-07-23)

The powered-hub smoke (ticket 065) was cancelled without approval or a run
because the hub's supply could not be found. The immediate distro path now
avoids storage entirely: `scripts/t6040-build-alpine-ramroot.sh` turns the
official Alpine 3.24.0 aarch64 minirootfs into a reproducible 3.9 MB
root-as-initramfs. Its `/init` mounts only pseudo/RAM filesystems, keeps the
watchdog alive, and exposes a respawning Alpine root shell over `/dev/ttydc0`.

Two builds reproduced SHA-256
`fc473c67672cd1596fac133759ed1b3ba18c716f42a400e3cfab9d4ad59cbb9b`.
An arm64-container chroot verified Alpine 3.24.0, `apk --print-arch = aarch64`,
the init syntax, and required applets. Ticket 067 proposes a single live boot
with the proven m1n1/kernel and standard USB/ANS/SART/NVMe-disabled DT. This is
a real distro-shell milestone, but it is volatile: all changes disappear on
reboot and it does not solve persistent root storage. Full artifact and live
preflight:
`done/2026-07-23-t6040-alpine-ramroot-artifact.md` and
`done/2026-07-23-t6040-alpine-ramroot-preflight.md`.

Ticket 067 booted that archive successfully, but the current 7.1.3 kernel lost
DockChannel HID after MTP reported `Keyboard ready`: no `05ac:0359` identity or
input device registered, while the IRQ thread and HID workers were idle.
Ticket 070's old 7.2-rc2 control never reached the Alpine framebuffer shell and
was inconclusive.

Offline ticket 069 found that the two kernel lines have matching HID configs
and content-identical DockChannel HID transport code. The current mailbox
driver nevertheless W1C-acknowledged RX with its local source still enabled,
then drained later in a oneshot thread; unlike the older receive discipline,
it did not mask around the drain or explicitly re-arm. The minimal correction
in `patches/t6040-dockchannel-rx-rearm.patch` masks before acknowledgement,
drains, clears/re-enables RX, and rechecks the FIFO for a raced packet. A fresh
storage-disabled kernel retains ttydc0 and embeds ticket 067's config
byte-for-byte:

```text
Image-hid-rx-rearm
  a6c2f09354bf1d61559b450f9430eb06d42f94d027d539c2deade708d708c4ff
t6040-j614s-dcuart-hid-rx-rearm.dtb
  2782b92237c35c8950212207391c3ae28c44b6b9c635b2e864c5748a77bb3cce
```

All external USB and ANS/SART/NVMe nodes remained disabled. Full audit:
`done/2026-07-23-t6040-alpine-hid-regression-analysis.md`.
`usb_smoke_cross_review` independently verified ticket 071's exact hashes,
embedded config, DT, patch, and procedure before its one approved run.

Ticket 071 reached Alpine and ttydc0, with no block devices, but
`/proc/bus/input/devices` was empty and `/dev/input` did not exist. Thus the
RX re-arm patch is not the sufficient HID fix and stays experimental. Do not
retry it. Result:
`done/2026-07-23-t6040-alpine-hid-rx-rearm-result.md`.

Ticket 072 is complete offline. `HID_STATE_TRACE=1` adds atomic counters and
read-only `dc_trace`/`hid_trace` sysfs summaries plus sparse `HIDTRACE`
lifecycle messages; it does not add an MMIO access, receive kick, retry,
polling path, or IRQ-control operation. The clean build exported:

```text
Image-hid-state-trace
  e7138c03c5dcea63048adcc5b800781a73a544699e6b575cb7343bc3f4cf4576
t6040-j614s-dcuart-hid-state-trace.dtb
  2782b92237c35c8950212207391c3ae28c44b6b9c635b2e864c5748a77bb3cce
config-hid-state-trace
  8e11399b172035f7d88c0915ccfbf1bb277eb16097462336c4158b54d8d6bc80
```

The config and embedded config byte-match tickets 067/071; the DTB byte-matches
071 and still disables every USB/DART/ANS/SART/NVMe node. Independent review
passed the exact packet.

Ticket 074 booted it once. ttydc0 TX delivered the full Alpine banner and
prompt, but RX produced no echo or result for LF, CR, or the cursor-position
response. `kisd`, the raw PTY, and a persistent foreground reader were all
healthy. The run stopped without executing any trace or extra diagnostic
command and recovered a stable proxy. Therefore the trace did not locate the
HID boundary. Do not retry 074 unchanged. Offline ticket 075 built a
bootarg-gated automatic TX reporter into a new reproducible initramfs; its
host gate/output tests and independent exact-artifact review pass. Proposed
one-shot TX-only capture ticket 076 then emitted its complete report.
Automatic reporter build audit:
`done/2026-07-23-t6040-alpine-hid-trace-auto-reporter.md`. Trace build audit,
procedure, and result:
`done/2026-07-23-t6040-alpine-hid-state-trace-preflight.md` and
`done/2026-07-23-t6040-alpine-hid-state-trace-result.md`.
Replacement preflight:
`done/2026-07-23-t6040-alpine-hid-trace-auto-preflight.md`.

Ticket 076 proves the HID mailbox receives 1,396 bytes in 13 batches, DCHID
matches all eight ACKs, obtains identity `05ac:0359:0510`, and returns zero
from all six `hid_add_device()` calls. `/proc/bus/input/devices` is nevertheless
empty. Ticket 077 narrows the honest boundary: the known-good and failing
configs match, as do the imported DockChannel HID sources, while the failing
Asahi `hid-apple` wildcard-matches Apple BUS_HOST and rejects the unset
`hid->type`; `hid-generic` therefore declines too. Ticket 078's six-line type
assignment live-registers the keyboard as `input0/event0`. Result and decode:
`done/2026-07-24-t6040-076-hid-trace-result.md` and
`done/2026-07-24-t6040-077-hid-boundary-decode.md`, plus
`done/2026-07-24-t6040-hid-type-fix-result.md`.

The resulting bootable-build plan separates cold boot from persistent storage.
The B0 target is boot picker → raw-enrolled m1n1 object → self-contained Alpine
RAM distro, with the tether observational only. Tickets 077–079 restore HID
and produce the release-like distro. Ticket 080 completed the embedded-payload
contract: raw m1n1 can directly autoboot a concatenated compressed kernel, raw
DTB, and compressed initramfs at entry `0x800`; the new strict host verifier
checks exact members, bounds, expansion, order, and truncation. The current
local m1n1 carries unapproved PCIe work and is not a B0 input; retain the
reviewed PCIe-write-free artifact until a new exact candidate is reviewed.
Tickets 081 and 100 completed the independently reviewed tethered
single-object autoboot. The release object reached OpenRC's default runlevel,
kept the watchdog alive, reported `input0/event0`, kept partitions empty, and
accepted a line from the internal keyboard at the panel shell. Ticket 082 now
contains the reversible enrollment/cold-boot procedure; its remaining fields
are the exact volume UUID, enrolled-object backup/hash, and the maintainer's
execution split. Ticket 119 conditionally passed dual-mode candidate
`46237ade...`: every byte after the m1n1 prefix matches live-proven
`2371ee5d...`, while the exact Rust nightly and version tag need pinning before
claiming a fully reproducible rebuild. Plan-approved ticket 101 performs the
enrollment/cold boot and the separate trigger validation only after 082
closes. The exact experiment and safety ladder is
`docs/BOOTABLE_BUILD_EXPERIMENTS.md`; exact layout:
`done/2026-07-23-t6040-raw-boot-object-layout.md`. U-Boot/EFI and external USB
root are B1 and B2 respectively, not prerequisites for B0.

The first concrete HID-restored safe-prefix object is now built. It embeds
ticket 078's exact live-proven Alpine kernel/DT/initramfs, entry `0x800`, and command
line behind m1n1 `1394c345...`. Strict verification and two builds produce
21,729,039-byte object `b50f52ab1fac...`; runtime reserve is 63,051,211 bytes.
`scripts/t6040-boot-raw-object.sh` performs one hash-gated `chainload.py -r`
upload and contains no `linux.py` call. Ticket 089 passed embedded payload
discovery, Alpine auto-report, and preservation of the registered keyboard; it
was a delivery control, not enrollment.
Preflight:
`done/2026-07-24-t6040-b0-alpine-single-object-preflight.md`.

Ticket 079 now replaces the custom diagnostic `/init` with a release-like,
normal OpenRC boot. `scripts/t6040-build-alpine-b0.sh` pins the Alpine
minirootfs and every added APK by version and SHA, installs only local verified
packages, then creates explicit `sysinit`, `boot`, and `default` runlevels.
Framebuffer tty0 and delayed ttydc0 gettys invoke a physically local
RAM-only shell; root's password remains locked. Watchdog and bounded
health-report services are enabled, while resolver/interface configuration and
all network services are absent. Two clean builds byte-match as
`initramfs-alpine-b0.cpio.gz` `ddd981711e91...`; the strict archive verifier
sees 699 aarch64 entries and zero block nodes. The corresponding safe-prefix,
HID-restored raw object is 22,183,563 bytes,
`m1n1-b0-alpine-openrc.bin` `2371ee5dfbfa...`, and also reproduces exactly.
Ticket 100 live-proved this exact release object through one tethered upload;
081 and 100 are done. A dual-mode prefix candidate
`46237ade7e314cd752e1482930e21b62319e1b0b707a0f23e86392701555f0c9`
has since been built so normal boot may autoboot while DebugUSB retains a
five-second proxy window. Ticket 119's independent review conditionally
passed it for ticket 101: exact repacking reproduced `46237ade...`, all
post-prefix bytes match live-proven `2371ee5d...`, and source review bounded
the no-connection path. The fresh rebuild also proved the original version tag
and Rust nightly were not pinned, so do not claim full byte reproducibility
until they are. The display/DebugUSB trigger distinction remains a hardware
validation, not an offline fact.
Exact results:
`done/2026-07-24-t6040-alpine-b0-release-bundle.md`,
`done/2026-07-24-t6040-b0-alpine-openrc-single-object-result.md`, and
`done/2026-07-24-t6040-b0-dualmode-earlyproxy-object.md`, and
`done/2026-07-24-t6040-b0-dualmode-crossreview.md`.

Ticket 086 established the external-root GPT/ext4 construction and validation
mechanics without opening any block device, but a later PID-1 audit found its
Alpine minirootfs lacks `/sbin/openrc`; it is structurally valid but not
bootable and must not be flashed. Ticket 098 supersedes it with the verified
OpenRC B0 root image
`linux-build-out/t6040-alpine-openrc-usb-root.build4.img`, SHA-256
`1c493fad1d1b...`, PARTUUID `e4731abe-3566-4c3a-8019-c8828ca27a5a`.
Two fixed-identity builds have byte-identical normalized trees
(`04ddd68e63a7...`); their only raw differences are imported-inode ctimes and
associated metadata checksums stamped by `mkfs.ext4 -d`, fully isolated to
3,625 inode-table bytes. Primary/backup GPT CRCs, `e2fsck -fn`, OpenRC
runlevels, consoles, watchdog/health services, exact PARTUUID, and 22-file
firmware manifest all pass independent regular-file inspection. Exact result:
`done/2026-07-24-t6040-openrc-usb-root-image.md`.

The historical ticket-086 image is
`linux-build-out/t6040-alpine-usb-root.img`, SHA-256 `32a897cb48ba...`, with
root selector `PARTUUID=1b841e9b-65a5-4687-83f2-6c728961ad14`. The
stick is currently connected to the M4, so the M1 has no external disk to
flash. The M4 link gate also remains: the unchanged right-port stack has
already shown root hubs only, and neither Linux nor m1n1 controls the T6040
SPMI SN201202x/HPM role-orientation path. Follow 096 and decomposed tickets
102–113 under `docs/SPMI_SAFETY.md`; do not repeat the unchanged topology or
guess transactions. Exact historical image and paired boot hashes:
`done/2026-07-24-t6040-usb-root-image.md`.

Ticket 025 prepared B1 without weakening that ordering. Upstream U-Boot
`8aa706b2` builds, but its normal Apple target has no T6040 memory map, panics
on the compatible, then would scan PCIe/NVMe/USB and autostart watchdog-backed
reset support. The draft `APPLE_NOIO` target instead maps only runtime
DT-derived RAM/framebuffer, stops at the prompt, and embeds EFI hello. Two
clean builds match. Raw U-Boot must be padded from its stored file length to
the ARM64 Image header's runtime size because m1n1 copies that full span for a
last raw payload. Full hashes and draft:
`done/2026-07-23-t6040-uboot-noio-prep.md`.

### ANS/NVMe map (2026-07-13, session 5)

Read-only live ADT inspection established the T6040 storage layout. The ADT
raw addresses are ASC control `0x209600000`, mailbox `0x209608000`, SART v3
`0x20dc50000`, and NVMe/NVMMU `0x20dcc0000`; `/arm-io` translation makes the
CPU physical addresses `0x409600000`, `0x409608000`, `0x40dc50000`, and
`0x40dcc0000` respectively (IRQs 1530–1533 and 2583).
Storage uses SART plus the embedded NVMMU, not DART. Disabled nodes are
committed in Linux `9cf4a92fa16f`; the standard DT performs no new accesses.

`scripts/t6040-build-nvme-candidate.sh` builds a separate, conspicuously named
first-probe DTB and supports both built-in and staged-module images. Exact map,
artifact hashes, write classes, and probe transcript:
`done/2026-07-13-t6040-nvme-map.md`.

The maintainer approved the initial full built-in probe. It handed off, then
reset before userspace. A staged image with `nvme-apple` still unloaded failed
identically, proving that the failure preceded NVMe. Cumulative DTs made the
boundary exact: ASC mailbox alone boots to BusyBox; adding SART while keeping
NVMe disabled resets before userspace. No disk command ran, no namespace was
mounted or written, and the machine was returned to the standard build #15
BusyBox image.

A second proxy-only ADT dump exposed the missing contract on `/arm-io/sart-ans`:
`compatible = "sart", "coastguard"`, `sart-power-managed`, reg 2 at
`0x20dcc0000`, and `sart-power-reg-offset = 0x13e8`. The exact power register is
therefore `0x20dcc13e8`. Static analysis of the paired macOS 26.5.2 AppleSART
driver confirmed its locked/refcounted protocol: repeatedly write `0`, delay
100 us, and wait for readback `0` to activate; on the last release repeatedly
write `1`, delay 100 us, and wait for readback `1`. This explains the reset:
the old T6000 fallback read v3 entries while CoastGuard was inactive.

The maintainer then approved the exact writes. A handshake-only image still
reset, but a diagnostic that touched no SART MMIO booted. The real fix is
`patches/t8140-sart-defer-scan.patch`: old SART variants scan at probe as
before, while power-managed CoastGuard waits until its first client holds the
complete ANS power context. The SART-only and full-module-unloaded gates both
then reached BusyBox. `nvme-core.ko` loaded; `nvme-apple.ko` reset the target.

Yielding phase checkpoints isolated that second reset to the first ANS ASC
control read at `0x209600044`. The last line was `before ANS CPU control read`;
no CoastGuard transition, SART entry access, or namespace command occurred.
Read-only PMGR inspection after recovery showed firmware's ANS domain at
`0x0f0000ff` (target/actual `0xf`, AUTO_ENABLE clear). The T6041 PMGR probe
otherwise enables auto-PM before the module runs. The independent ANS-hold DT
booted, and a corrected current-boot trace showed the exact same fatal boundary
at the first CPU_CONTROL read. The auto-gating hypothesis is therefore
disproven.

A later boot with both NVMe modules unloaded showed `ans`,
`apcie_sys_st0`, `apcie_sys_st1`, `apcie_phy_sw`, `fab3_soc`, `apcie_st0`,
`apcie_st1`, and `apcie_gp` all `on` in debugfs genpd state. The next bounded
question is whether raw PMGR agrees immediately before the ANS read.

`patches/t6040-nvme-pmgr-snapshot-debug.patch` and
`dts/t6040-j614s-dcuart-nvme-pmgr-snapshot.dts` implement that single
diagnostic. They follow only existing DT power-domain phandles, read each
provider's declared PMGR register via its parent syscon, and return before
`nvme_add_ctrl()`. No reset work or ANS access occurs. The special exit retains
genpd attachments until reboot so cleanup requests no power transition. Build
and verification details plus exact hashes are in `NEXT_STEPS.md` and the map.
Never unload this diagnostic module or mount the SSD.

The Linux #25 snapshot completed and the target remained alive. ANS was actual
`f`, but `apcie_phy_sw` was actual `4` (clock-gated) and both
`apcie_sys_st0/1` were actual `0` (power-gated); all had target `f`, and the
three parents had AUTO_ENABLE set. This explains why debugfs could truthfully
say `on`: the PMGR driver defines target-active plus auto-enable as logically
active. The next diagnostic must force the parent chain to actual `f` through
the existing domain callbacks and verify it while still stopping before ANS.
Exact output: `logs/t6040-console-20260713-nvme-pmgr-snapshot.log`.

That diagnostic is prepared as
`patches/t6040-pmgr-force-active-debug.patch` plus the opt-in
`dts/t6040-j614s-dcuart-nvme-pmgr-force-active.dts`. It recursively follows
only the declared PMGR parents, skips ACTUAL `f`, and uses the PMGR driver's
existing locked active-state callback for the three gated providers. It
snapshots before/after and still returns before `nvme_add_ctrl()`. Exact hashes
and safety review are in `NEXT_STEPS.md` and the NVMe map.

Linux #26 completed that verification. Only `apcie_sys_st0`,
`apcie_sys_st1`, and `apcie_phy_sw` transitioned; all reached actual `f` with
AUTO_ENABLE clear, and the target remained responsive. It was rebooted without
module unload and left at m1n1. The next bounded diagnostic may repeat that
transition and perform exactly one read of ANS CPU_CONTROL, then stop. Exact
transcript: `logs/t6040-console-20260713-nvme-pmgr-force-active.log`.

That isolated-read diagnostic is prepared as
`patches/t6040-nvme-ans-read-debug.patch` and
`dts/t6040-j614s-dcuart-nvme-ans-read.dts`. It repeats and verifies the proven
force-active sequence, performs one CPU_CONTROL read, prints the result, and
stops before any ANS write or reset work. Reproducible hashes are in
`NEXT_STEPS.md` and the NVMe map.

The remaining T8103 ANS2 fallback agrees with m1n1 on ASC v4, 64-entry linear
queues, and functional ANS/NVMMU offsets. m1n1's historical TCB-status
diagnostic read remains `0x29120` versus Linux's `0x28120`; resolve that from a
reviewed source, never by probing either offset live.

### Protected T8140 NVMe queue boundary (2026-07-14)

After the parent-power fix, Linux now completes CoastGuard activation and SART
entry setup, boots ANS RTKit, and reads the ready boot status. The next layer
is firmware-protected. A same-value linear-SQ write faults; even reading
`MAX_PEND` faults. Skipping that static block moves the boundary to the normal
AQA write at CPU PA `0x40dcc0024`.

The translated secure NVMe BAR is `0x44dcc0000 / 0x10000`. Read-only recovery
showed iBoot state: AQA `0x000f000f`, ASQ `0x101005db000`, ACQ
`0x101005dc000`, CC `0x00474000`, CSTS `0`. Paired macOS static analysis then
showed that AppleANS2CGv2 does not write those queues directly. It uses
`_pmap_iommu_ioctl` and an NVMe PPL backend whose GENTER veneers select SPTM
service 6: op 0 initializes, op 1 authorizes TCB data, ops 4/5 register
admin/I/O queues, and ops 6/7 activate SQ/CQ state.

Raw proxy reads returned `SPRR_CONFIG_EL1=0` and `GXF_CONFIG_EL1=0`; reads of
the guarded entry/abort registers trap. The exact macOS op-0/op-4 sequence was
then attempted once from Linux. It reached `before protected admin queue
setup`, hung at GENTER, and watchdog-reset to a healthy m1n1 proxy. Therefore
the decoded ABI is not directly callable in the current raw-boot environment.
No NVMe command or user-storage access occurred. Continue with static,
read-only analysis of whether raw boot can acquire the protected execution
state. Queue preservation alone is insufficient: iBoot's ASQ/ACQ are ordinary,
unreserved RAM and macOS authorizes TCB data per command. Do not repeat GENTER
or direct secure-BAR writes unchanged.

### T6040 PCIe static completion and gated image (2026-07-14)

The complete J614s internal topology is now mapped offline: BCM4388 WiFi/BT on
port 0 and GL9755 SD on port 1, with both DARTs, GPIOs, IRQs, ECAM, and outbound
windows. Paired-kernelcache disassembly proves that T6040's new CIO3 PLL and
PCIe clock-generator tunables target ADT reg[5] (`0x415046200`) and reg[6]
(`0x415044000`). m1n1 main `eb23c423` and curated `da1791a0` apply them.

The dedicated PCIe kernel/DT image builds cleanly.
`scripts/t6040-pcie-write-plan.py` expands the committed J614s ADT and the
complete m1n1 path into
`done/2026-07-14-t6040-pcie-write-manifest.tsv`: 1,571 ordered operations at
1,459 distinct addresses, with exact size/op/mask/value for every row. The
first explicitly approved attempt used the base DT without a Linux PCIe node.
It completed PMGR and all AXI tunables, printed `No common tunables`, then hung
before the next status. The uploader timed out; HPM DebugUSB warm-reboot restored
`Running proxy`. No Linux handoff or storage access occurred. Transcript:
`logs/t6040-console-20260714-pcie-stage1.log`.

The traced retry delivered an asynchronous SError after AXI tunable `[70]`
printed `done` and before `[71]` was announced. It was delivered in the proxy
`P_CALL` trampoline, so this is a timing boundary, not exact causal-write
attribution. DebugUSB recovery again restored a healthy proxy; there was no
Linux handoff, PHY/port write, or storage access. Transcript:
`logs/t6040-console-20260714-pcie-axi-trace.log`.

Paired-kernelcache disassembly found the sequencing delta: Apple enables PCIe
clock gates 0–6 before AXI/CIO3/clkgen programming and gate 7
(`APCIE_PHY_SW`) afterward; m1n1 had enabled all eight up front. Main
`6efe2d45` / curated `954fd4cf` now reproduce Apple's order and still return
before manifest operation 106, the first PHY register write. Main binary hash
`c2a5b7e27bb8d56479f46d6b485a195d2eb1cd64a3b86fbe3c90db1f00424735`;
the exact newly gated subset is
`done/2026-07-14-t6040-pcie-clock-diagnostic.tsv`, hash
`ce86e51aa3d278da1d9ef9eb35fca3208859f4993480de5b6af3268dc03ef4e6`.

The approved staged run disproved that sequencing delta as the cause of this
fault. It again printed `done` for AXI `[70]` at `0x4160013fc`, then delivered
the same asynchronous `L2C_ERR_STS=0x82` before `[71]`. It did not reach CIO3,
clkgen, the late gate, PHY, ports, Linux, or storage. Recovery restored a fresh
quiescent proxy. Transcript:
`logs/t6040-console-20260714-pcie-staged-gate.log`, SHA-256
`c31275546280b9df2dbf9b014d2e6411cfb708f87f1c803e10b11e2cdb95ec2f`.
The next live diagnostic ran at m1n1 main `00760c79`, binary SHA-256
`2997b07647007f99df6ad094a2da55d66a9f7accd6758bb134d3fa92b76d0c72`.
It added `dsb sy` and read-only L2C status sampling around the same 105-operation
set. AXI `[70]` again printed `done`, proving that its barrier completed and the
immediate status sample was zero, before the same SError arrived. The status is
not latched early enough to attribute a write. Recovery restored a quiescent
proxy. Transcript: `logs/t6040-console-20260714-pcie-barrier.log`, SHA-256
`cebc058921b62b2f594855bb65db28b312570b6c707f5a29a29480c31c04667b`.
The zero-PCIe-write trace-volume control ran at main `3e772779`, binary SHA-256
`c9296b8d1ca146a32c7a1ba1bf17b7091281588ab90d16a69f0718c5a8fa04ea`,
and returned before PCIe PMGR or controller access. It still faulted after
`[70] done`, proving the trace path itself is responsible. The log buffer spans
`0x105ce7a4000..0x105ce7a8000`, exactly to the top of normal RAM and the address
reported by every `L2C_ERR_ADR`. Its initial 8 KiB console-backlog import plus
the new trace crosses the 16 KiB ring during `[61] done`; the asynchronous SError
arrives 1,082 output bytes later. Recovery restored a quiescent proxy. Exact
transcript: `logs/t6040-console-20260714-pcie-trace-dry-run.log`, SHA-256
`52431e2a9a7d87642fde917419f3e8e666672434953cad23466c13b61968742d`.
The upper-guard control ran at main `eed11760`, binary SHA-256
`1394c34504345fff1403340070029a5feedf744b032af02cd22c936026a7e61b`.
It left an unused 16 KiB page above the active log ring and retained the same
zero-PCIe-write trace. All 77 entries and its completion marker printed, then
the base Linux kernel reached BusyBox. This proves the guard fixes the trace
SError. m1n1 transcript SHA-256
`2e8624d795bc6bddab24b932a530bf7f992f35732402ed041bfc308857260d63`;
Linux transcript SHA-256
`6c6c0073bacbec235a9e54c6535a646f34ad372792c02ee30a5cb1fc5983d8e9`.
See `done/2026-07-14-t6040-logbuf-upper-guard-control.md`.

The write-bearing stop-before-PHY path was restored at main `f46d6e35`, binary
SHA-256
`8fd7319047187f9ca05a6924462a4f24360fcc1d9e4279b089dc83a5acb05744`.
It retains the proven upper guard and the exact 105-operation manifest, SHA-256
`ce86e51aa3d278da1d9ef9eb35fca3208859f4993480de5b6af3268dc03ef4e6`.
The maintainer approved one run. It completed AXI `[0..76]`, the RC write,
all seven CIO3 PLL RMWs, the PCIe clkgen RMW, and the late `APCIE_PHY_SW` gate,
then printed the intentional stop-before-PHY marker. No L2 error or SError was
observed. The PCIe-free base kernel reached BusyBox; PHY, ports, PERST#,
RID2SID/MSIMAP, Linux PCIe, NVMe, and storage were not accessed. Exact m1n1
transcript: `logs/t6040-console-20260714-pcie-guarded-clock.log`, SHA-256
`8dac965aadfb8f5bd92cf2c0e17ceefaea3f74de11790d8089121d527f54b175`
(402 lines, 26,188 bytes). Linux transcript:
`logs/t6040-linux-20260714-pcie-guarded-clock.log`, SHA-256
`b1caef2f4b6612675f329402bc0d9f87813494a98c28a84bb09033471d792063`
(36 lines, 2,255 bytes). Full result:
`done/2026-07-14-t6040-pcie-guarded-clock-diagnostic.md`.

The shared-PHY-only image ran once with approval. Main code
`85b01036` (`v1.6.0-81-gb5ced9ba`), binary SHA-256
`add3cef43947dab1605bd95ad602b6dcbf8e89de0a3f1b43f278005cd52dd9da`,
was bounded to 351 writes and five existing polls, with a return before ports.
Operations 1–114 completed, including reference clock, CLK0/CLK1 acknowledgements,
reset release, and the T8122 pre-tunable control. Output then stopped on the
pre-line for operation 115, the first PHY-IP PLL RMW at `0x417040090`; no
`done` or exception followed, and proxyclient timed out. Linux did not hand off
and no port or storage access ran. The subset manifest SHA-256 is
`d4496968ee8fc1202bd4d47247fc6bbaa36f0a3f7cc872a81efabe72327c50fc`.
The sanctioned DebugUSB reboot restored a quiescent proxy. Transcript SHA-256
`b567ab1353682787549a1e666b489dd46228a960a23cb5248e14c0a5221668bb`.
Exact addresses, phases, and result:
`done/2026-07-14-t6040-pcie-phy-diagnostic.md`.

The operation-115 read/write discriminator then ran once at main `dc7124fb`,
binary SHA-256
`5616b05fdd21a35990102ce8b711920ec8c442f75c89ce6cfe27da2f24adef67`.
Its first 114 operations were identical to the proven prefix. The final line
was the pre-read marker for the ADT-derived 32-bit access at `0x417040090`; no
read value/completion, L2C status, exception, or later marker appeared. The read
itself therefore stalls, before any operation-115 write. Linux did not hand
off and no later PHY, port, PCIe, NVMe, or storage access ran. DebugUSB recovery
restored a quiescent proxy. Transcript SHA-256
`bdf7c2f8be0947c5da91c2c7f44f9e41a967a048ca35d0362782d8509bafafc8`.
Do not try a write-only variant; find the missing PHY-IP aperture precondition
offline. Full review and result:
`done/2026-07-14-t6040-pcie-op115-cross-review.md` and
`done/2026-07-14-t6040-pcie-op115-read-result.md`.

Full details are in `done/2026-07-14-t6040-wireless-pcie-map.md`.

### m1n1 fork synced with AsahiLinux upstream (2026-07-14)

`~/Code/m1n1` main merged `origin/main` (which had merged AsahiLinux main on
GitHub) → merge commit `16b1f61f`, pushed to the fork. Eight upstream commits
came in; none overlap the local T6040 work (no local commit touches `src/hv.c`
or `proxyclient/m1n1/hv/`):

- `src/chickens_*.c` moved to `src/chickens/*.c` (**`src/chickens.c` stays at
  top level**, so the curated `t6040-bringup` chickens.c patch is unaffected);
  Makefile updated to match.
- hv + proxyclient/hv now gate SPRR/GXF/AMX writes on
  `apple_sysregs_unlocked` and handle RVBAR when locked (yuka) — upstream is
  making the hypervisor tolerate locked-sysreg raw-boot machines like this
  one. Whether a degraded hv is actually usable on the T6040 is untested here.
- `proxyclient/hv: add CPUSTART for T8132,T8140,T6034,T6040` (yuka
  `0ec216de`): T6040 CPUSTART = `0x88000`, independently matching the constant
  this project validated in Stage A (`CPU_START_OFF_T6031`).

`make -j8` verified on the M1 host post-merge (all four artifacts). **The
merged main is NOT rig-tested** — hash-pinned experiment images (e.g. ticket
002's `dc7124fb` bin `5616b05f`) predate the merge; treat `16b1f61f` builds as
a new image lineage for pinning purposes. The `t6040-bringup` branch
(`m1n1-clean` worktree) was rebased the same day onto `upstream/main`
`fd20d7f7` (the upstream content inside merged main): 22/22 commits clean,
range-diff content-identical, new tip `f0738eee`, build verified.

**Series refresh 2026-07-23 (ticket 046):** upstream advanced again to
`7c7716b6`, including initial T6041 identity (`d3699d53`), T6040 PCIe/reset-bit
support (`0f221fc7`), and four-level paging. The curated history was audited and
reduced to a nine-patch RFC on `codex/t6040-upstream-series` at `37fafb86`.
Host helpers and all diagnostic PCIe history are excluded; the last patch adds
only J614s's proven clock prefix and stops before unresolved operation 115.
`git am` tree identity and two clean builds pass. Draft, hashes, and audit:
`patches/m1n1-t6040-upstream-v1/` and
`done/2026-07-23-t6040-m1n1-upstream-series.md`. Nothing was posted or run.

**Host-tool series (2026-07-24, ticket 048):** proxyclient's generic kisd-PTY
transport is isolated on m1n1 branch `codex/proxyclient-pty` (`13c52b61`) and
macvdmtool's ACE3 `actions`/`vdm`/`dven`/`localserial` commands are isolated on
`codex/ace3-host-tools` (`3e2038ee`). Both signed mail drafts pass exact
`git am` tree checks; the PTY patch also passes a byte-preservation test, and
macvdmtool builds cleanly apart from existing IOKit deprecations. kisd needs no
patch: upstream already recognizes M4 Pro/KIS 4.00, auto-detects the Pro/Max
base offset, and documents verified T6040 base `0x548700000`. NOPASSWD is
operator policy, not an upstream source change. Exact hashes and disposition:
`done/2026-07-24-t6040-host-tools-upstream-prep.md`. Nothing was posted,
pushed, installed, or run on the target.

Follow-up (same day): reviewed chadmed/m1n1 `dcp/14.8.3` (remote `chadmed`
in `~/Code/m1n1`). Everything on it except chadmed's seven DCP commits is
already in our main via the fork base — including Sven Peter's `954f80c6`
(`mmu_secondary_setup`: `dsb sy` + stack-cache invalidate before MMU-on;
fixes sporadic secondary bring-up crashes, upstream #463/#480) and
`c22ca847`, which names the broken_wfi mechanism: `CYC_OVRD_DISABLE_WFI_RET`
left set makes WFI drop the register file and re-enter at RVBAR. The fix
writes `SYS_IMP_APL_CYC_OVRD` under `apple_sysregs_unlocked` — a no-op on
this raw-boot machine (False, confirmed live), so the WFE park stays
required here. Ticket 019 was finalized on 2026-07-23: the ready-to-post SMP
draft now distinguishes the retention-bit root cause from the locked-sysreg
WFE fallback and cites both commits; the companion cpufreq draft documents the
validated PSTATE-only path and the asynchronous-SError throttle boundary.
Linux `checkpatch.pl` was run and its tab-only findings were adjudicated
against m1n1's four-space style; the changed ranges pass m1n1-style
clang-format and `git diff --check`. Ticket 046 subsequently completed the
current-upstream review branch and mail draft. chadmed's DCP
commits are 14.x-era firmware ABI infra (V14_7 ABI, FW 14.8.3, trace_dcp) —
watch pointer recorded on ticket 022. Follow-up through 2026-07-21: DCP now
boots on that 14.8.3 work, HPD/brightness and much of the service stack operate,
while surface clearing and GPU-dependent delivery remain incomplete. This is
protocol/versioning groundwork only; it does not add the macOS 26.x ABI needed
by J614s. See `done/2026-07-21-asahi-dev-log-review.md`.

Ticket 022 was refreshed again on 2026-07-23. PR 630 is still open at
`7e391ffde033bf2fa0e22cc5bda575f83d2d584b`; chadmed's Linux branch is
`f4df8984b39affb6d661ac67d097c131132b8f26`. The captured J614s ADT now gives
an exact internal DCP/DART/display and `dcpext0/1` inventory, so DT preparation
no longer needs a rig read. It also shows why an enabled node would be
premature: the target has a fifth display register window, an eight-input ASC
wrapper, SID/register-bank deltas, and a display PMGR domain deliberately
isolated to preserve firmware scanout. No Linux-tree edit was made. Native DCP
remains an upstream watch; B0 stays on simpledrm. Full matrix:
`done/2026-07-23-t6040-dcp-upstream-dt-prep.md`.

Ticket 039's G16 upstream-mule preparation completed on 2026-07-24. Pinned
source inspection found no live candidate: asahi-wip has hardware/firmware
definitions only through T6022/G14; Mesa has AGX2 compiler groundwork but no
explicit G16 chip/command-stream selection and currently classifies every GPU
generation ≥14 as G14G/G14X; m1n1 has no T6040 `dt_set_gpu()` handoff case.
The official T604x GPU feature remains TBA. The captured `gpu,t6040`/gfx-asc
register, IRQ, perf-state and UAT-region inventory plus exact 25F84
`AGXFirmwareKextG16RTBuddy`/`AGXG16X` kernelcache hashes are recorded without
machine identifiers. A reusable admission gate, G0–G3 staged smoke, stop policy,
and report template are ready. Do not create or run a G14 alias; B0 remains
simpledrm/fbcon. See `done/2026-07-24-t6040-gpu-upstream-test-prep.md` and
`docs/t6040-gpu-upstream-smoke.md`.

### ATC/HPM upstream pointer corrected (2026-07-23)

Ticket 023 rechecked every published Asahi ATC branch against the captured
J614s ADT. `m1n1`'s `atcphy-new-tunables` is stale at `9657a52e` from
2025-01-16 and 353 commits behind main; neither it, current main, nor the
published Linux ATC branches contains T6040 support. The right connector's
contract is now exact offline: `aapl,spmi`/SN201202x `hpm2` → `acio2` →
`atc-phy2`, whose T6040-only node has 44 register entries and new
USB2/CIO4/AUS40 tunables. Addresses alone do not name the required buckets or
authorize state-changing SPMI access. No rig or Linux-tree edit was made.
Continue the RAM-root B0 path. The powered-fixture alternative was later
retired; only the staged, upstream-derived and independently reviewed T6040
HPM/PHY sequence reopens external-root testing. Full checkpoint:
`done/2026-07-23-t6040-atcphy-upstream-checkpoint.md`.

The 2026-07-24 paired-kext pass removes the bank-map unknown without touching
the rig. The exact 25F84 `AppleT6040TypeCPhy::_sRegisters[44][8]` table matches
ADT `atc-phy0..3` profiles 0..3, all 44 ranges and in the same order. Its
`applyTunables` disassembly proves bits 31:27 select that bank and bits 26:0
carry the signed byte offset. The right-port USB2 HOST record is
`reg[4]+0x8`, mask `0x7003`, value `0x3`, exactly the DFLT value; replaying it
alone cannot supply HPM/VBUS/repeater state and is not a useful live test.
`scripts/t6040-atcphy-kext-map.py` reproduces the mapping while refusing any
other kext hash or ambiguous ADT. Direct eUSB2 sequencing and the
SPMI/SN201202x path remained offline work at that checkpoint. The later
`docs/SPMI_SAFETY.md` permits only tickets 092–095's staged direct-HPM2
R0/R1/R2 work; live PHY/role/VBUS remains R3-gated on 096/097. Full static
result:
`done/2026-07-24-t6040-atcphy-kext-bank-map.md`.

The follow-on static decode bounded the direct eUSB2 half further. The
8,580-byte `eusb2phy_init(bool,bool)` routine touches only ATC banks 0 and 1:
six offsets total, with two setup branches followed by reset release, one
event write/status read, and final USB mode selection. For right-port
`atc-phy2`, the two bases are `0x392a90000` and `0x392800000`. This is still
not a live candidate. Paired `AppleT8150USBXHCI::start` proves the host call as
power level 2/options `0x40000`/timeout 500 ms, selecting the false/false
branch and final mode 2, but the routine does not own
attach/orientation/source-role/VBUS/repeater state. Those remain in the
SPMI/SN201202x HPM path. They are now eligible only through the staged,
endpoint-scoped policy in `docs/SPMI_SAFETY.md`; no R3 role/VBUS/PHY sequence
is approved yet. Exact sequence and function hashes:
`done/2026-07-24-t6040-eusb2-init-sequence.md`.

The HPM follow-up corrects the target generation and bounds the next static
layer. J614s explicitly selects Apple SPMI **Gen3** and a right-port
SN201202x class-10 HPM. Paired `publishHPMDevices()` reads six exact windows:
`0x0f/4`, `0x00/4`, `0x01/4`, `0x05/0x11`, `0x2c/1`, and `0x2d/0x34`.
This does not authorize a live census: the path first invokes a provider state
transition and 100 ms sleep when not ready, while `readRegs()` changes HPM
timer/transaction state and can poll for up to one second. Exact function
boundaries, hashes, target ADT facts, and the remaining class-10 decode:
`done/2026-07-24-t6040-hpm-spmi-discovery-boundary.md`.

The next paired pass proves the right-port object chain:
SN201202x selects `AppleHPMDeviceHALType5`, while
`AppleTCControllerType10::probe()` requires the target's
`hpm-class-type = 10`. Type10 `turnOnVbus()` clears its wait flag, stops its
USB timer, then dispatches `forcePortEvaluation()`. That method reads nine
bytes at HPM address `0x14`, ORs `0x0d` into byte 1 and `0x08` into byte 7,
then writes all nine bytes. Its cached path performs the same masks and merges
with a fresh read. HALType5 separately proves USB config/status/data-control
addresses `0x23`, `0x24`, and `0x55`. There is no local inverse for the
address-`0x14` mutation, so it remains outside the current R0/R1/R2 allowlist
and requires ticket 096's complete detach/rollback proof before R3. Exact
class proof, packing, function hashes, and remaining rollback work:
`done/2026-07-24-t6040-hpm-class10-host-transition.md`.

Ticket 096's next PAC-aware slice resolved the Type10 virtuals without raw
signed-pointer guesses. `forceUSB23On()` creates/configures a USB3 port object,
sends detect changes, starts the 10 s timer, and prints transports; it does not
directly touch `0x23`/`0x24`/`0x55`, clear IRQs, reset the repeater, or mark
USB2 inactive. `turnOnVbus()` does dispatch `forcePortEvaluation()`. The
`0x14` event/cache mutation still has no race-safe inverse; `0x23` destroys
unmapped bits on write, `0x24` lacks complete status semantics, and `0x55`
lacks readback or a proved neutral value. The final PAC-aware pass found the
actual mode-flag detach branches, software-only USB2/USB3 object removal,
HPM inactive/active mask reconstruction, and paired semantic eUSB2/ACIO
shutdown. It still found no VBUS-off operation, exact cache/mask/detect or
pre-SSPS-state restoration, or safe cross-layer teardown order. Ticket 096
remains open with an R3 no-go; do not build or run 102–108 without new primary
evidence. Evidence:
`done/2026-07-24-t6040-hpm2-detach-static-slice.md`.

Yuka's late-2026-07-24 `tps6598x-spmi` branch (`dcc5f1bc...`) is now the first
public m1n1 WIP that matches J614s's exact `aapl,spmi` Gen3 bus and
`usbc,sn201202x,spmi` children. A detached host build succeeds. It does not yet
clear the live gate: the IRC success report is for T6000/I2C, while the new
SPMI path automatically sends WAKEUP and SHUTDOWN, uses a write to select every
logical register, may issue `SSPS`, clears/masks IRQs, and then runs PHY
bring-up. Static review also found an unbounded selection poll, a
double-shutdown path, an index bound error, and misleading success reporting.
Never substitute this branch into a safe rig artifact without resolving those
issues and reviewing exact state/rollback semantics. Full audit:
`done/2026-07-24-t6040-yuka-hpm-spmi-branch-audit.md`.

### SPMI policy refined to endpoint/opcode gating (2026-07-24)

The maintainer approved replacing the blanket "never write SPMI" rule with
`docs/SPMI_SAFETY.md`. The captured J614s ADT proves that system PMUs are on
separate `nub-spmi0/1/2` controllers, while right-port HPM2 is the sole child
of Gen3 `nub-spmi-a1` at reg0 `0x309198000`, SID `0x0c`. PMU/Abbey,
charger, NVRAM, firmware/flash, AOP-SPMI, RESET, unknown endpoints, scanning,
and blind register access remain prohibited.

The live ladder is deliberately narrower than Yuka's branch. Ticket 092
established separate, exact-endpoint candidates. Ticket 093 proved the
selector window inactive without WAKEUP. Ticket 094 sent one WAKEUP and read
logical power state `0x07`. Ticket 095 then sent only DATA1 `00` and CMD1
`SSPS`, and read final state `0x00`. No mask/W1C, role/VBUS, USB-config,
PHY/ATC/DWC3, xHCI, or storage operation was linked. Offline 096 still owns
class-10 detach/rollback. Tickets 097 and 099 are umbrellas to be decomposed
into exact link, enumeration, block-read, flash, root-write, and untethered
steps. Corrected OpenRC image 098 is complete (`1c493fad...`).

Ticket 092 established the hardened artifact pattern. m1n1 replaces
generic iteration with an exact direct-HPM2 path, validates the captured ADT
identity and endpoint before any transaction, bounds every FIFO/selector/
command wait, rejects leftover RX, logs raw response words before validating
them, and warm-reboots at the class boundary before USB/PHY/payload code.
Linked-symbol inspection proves forbidden SPMI opcodes and generic HPM/USB
paths are absent. An independent clean rebuild reproduced all hashes and
accepted the strict transport, exact ADT gate, and linked class boundaries.
The original IntMask candidate was never run and was later removed from the
095 binary. Ticket 092 is done; the historical preflight records the artifact
evolution:
`done/2026-07-24-t6040-hpm2-r0-r2-preflight.md`.

The first R0 live attempt proved the original gate failed closed: the candidate
reported ADT size `606208`, runtime CRC `a9876072`, then
`ADT verification FAIL; zero SPMI transactions` and warm-rebooted. The
captured-tree CRC is not stable because `chainload.py` necessarily rewrites
volatile `/chosen/memory-map` handoff addresses before pushing the ADT. Normal
proxy recovery passed. Replacement m1n1 `ef707f51f181` makes the whole-tree CRC
diagnostic-only while retaining size plus every exact root/chip/board/
controller/sole-child/SID/rid/class/port/right property as fatal gates. An
independent clean rebuild and review passed replacement hashes R0
`3a686c71...`, R1 `ae136a14...`, and R2 `169c081a...`. Attempt record:
`done/2026-07-24-t6040-hpm2-r0-attempt1.md`.

That replacement's live attempt also failed closed before SPMI. It exposed
that `adt_get_reg()` translates the raw `0x309...` bus tuple through
`/arm-io` to CPU physical `0x509...`; the gate compared the two
representations directly. A subsequent leased proxy query read only the ADT
and confirmed both complete tuples. Commit `471700035efd` validates both
independently. Attempt record:
`done/2026-07-24-t6040-hpm2-r0-attempt2.md`.

The corrected R0 then reached the endpoint. Its selector command ACKed, but
the selector window read returned `0x00`; the candidate stopped before the
data-window read and recovered healthy. This matches the public driver's
requirement to send WAKEUP and wait 10 ms before selecting a logical register.
Ticket 093 closed as that bounded inactive-endpoint result:
`done/2026-07-24-t6040-hpm2-r0-attempt3.md`.

Ticket 094 was narrowed to WAKEUP plus the same read, with SSPS and all
extended writes removed from the binary. Independent source/disassembly and
two-build review passed exact R1 `bf369434...` at m1n1 `3e4ea5b880d1`.
The live run passed: WAKEUP ACKed, selector read `0x20`, and logical
power-state `0x20` returned `0x07`. Automatic warm reboot and proxy recovery
passed. Ticket 094 is done:
`done/2026-07-24-t6040-hpm2-r1-wake-read-result.md`.

Ticket 095's exact independently rebuilt/reviewed artifact was m1n1
`276f4059d8c4`, binary `23737cd3...`. It repeated WAKEUP, observed state
`0x07`, wrote exactly one `00` byte to logical DATA1 `0x09` and `SSPS` to
logical CMD1 `0x08`, observed command completion, and read final state `0x00`
(`HPM is in S0`). Transcript SHA-256 is `630fe61a...`. Ticket 095 is done.
The IRQ-mask roundtrip was removed and remains untested.

The intentional class-boundary warm reboot was followed by a failed VDM
recovery. One bounded reattach entered DebugUSB but did not attach `kisd` or
produce console bytes. Ticket 118 later passed the controlled recovery after a
maintainer power cycle and subsequent reboot cycles remained healthy; do not
infer that SSPS caused the original transient. Exact
result:
`done/2026-07-24-t6040-hpm2-r2-ssps-s0-result.md`.

### MCC carveout/cache residual closed as a boot blocker (2026-07-23)

Offline ticket 020 audited the captured J614s ADT, current m1n1 memory handoff,
saved boot boundaries, and the exact 25F84 AppleT6041MCC/iBoot binaries. The
normal-RAM interval ends at `0x105ce7a8000`, exactly where carveout region-id-4
begins; region-id-2 lies higher. kboot exposes only the normal interval to
Linux, so the all-zero reused T603x TZ registers do not expose either protected
range to the kernel. The gap is limited to m1n1's broad EL2 identity map.

`mcc_enable_cache()` is also proven rather than pending: iBoot already left
plane 0 enabled (`+0x1c00 = 1`), the T6041 status is `0x00010101`, and the
idempotent write/poll has preceded the project's repeated BusyBox and Alpine
boots. Keep that exact path; it does not authorize other MCC/DCS writes.
Future series work should use a bounds-checked ADT region-id-2/4 unmap fallback
or finish static iBoot reconstruction. No blind AMCC probing. Evidence:
`done/2026-07-23-t6040-mcc-carveout-analysis.md`.

### Cpufreq throttle residual bounded statically (2026-07-23)

Offline ticket 021 audited the paired 25F84 `ApplePMGR`,
`AppleT6041PMGR`, `AppleT6041CLPC`, and captured J614s ADT. The ADT exposes
`ppt-thrtl`, `llc-thrtl`, and `amx-thrtl` only as booleans. It supplies no
per-cluster offsets. The target PMGR overrides both generic throttler entry
points and returns early for enum slots 1, 11, and 12 (`0x1802` mask); remaining
generic paths use resolved RegMap metadata. The old `0x40250`, `0x40270`,
`0x48400`, `0x48408`, and `0x440f8` constants are absent as 32-bit literals
from all three executables.

This does not map the enum slots one-to-one to m1n1 feature names and is not a
replacement register contract. It does close the bring-up decision: retain
the validated `+0x20020` PSTATE/APSC-only T6040 path and do not probe adjacent
P-cluster offsets. Throttle parity is non-blocking. Evidence:
`done/2026-07-23-t6040-cpufreq-throttle-analysis.md`.

**Identity rewrite (2026-07-14, force-pushed).** All CJ-authored commits on
the fork were rewritten with git-filter-repo: four author spellings collapsed
to `CJ Damsleth <kim@damsleth.no>`, `Co-Authored-By: Claude` trailers
stripped, `Signed-off-by` added. Trees are byte-identical and AsahiLinux
upstream hashes are untouched, but every local commit was rehashed. Living
docs and open tickets now use the new hashes; `done/` write-ups and closed
tickets keep the hashes that actually ran (artifact SHA-256s are the real
provenance there). Map for the pinned ones (old → new):
`d1494f5a → dc7124fb` (op-115 read), `a61fd099 → eed11760` (safe
zero-PCIe-write control), `88ce1ee3 → 00760c79` (barrier diagnostic),
`b5ced9ba → 85b01036` (gated shared-PHY stage), `2df4f278 → 16b1f61f`
(upstream merge), `0b2e7252 → f0738eee` (t6040-bringup tip). Full map:
`~/Code/m1n1/.git/filter-repo/commit-map`; pre-rewrite refs kept locally as
`backup/main-pre-identity` and `backup/t6040-bringup-pre-identity`. Other
agents with m1n1 clones must `git fetch && git reset --hard origin/main`.

### Watchdog (2026-07-11)
Linux `apple_wdt` takes over m1n1's WD1; BusyBox pings `/dev/watchdog0` every
10 s. m1n1 arms WD1 for ~20 s on M4 before handoff (`src/kboot.c`,
`src/wdt.c: wdt_arm_secs`) so hung kernels warm-reset back to "Running proxy".

## PMGR investigation (sessions 2–4, 2026-07-11/12)

**Deterministic result (2026-07-12): the full 214-domain topology boots 3/3**
with this exact minimal temporary raw-boot policy:
- preserve every domain found active at probe (`apple,preserve-active` on all
  four controllers);
- disable only `disp_cpu`;
- skip auto-enable only on `dispext0_cpu` and `dispext1_cpu`.

The legacy raw tree fails 3/3. The five ANE exclusions in the previous broad
functional policy are unnecessary, as are both banks' `sys` and `fe` skips.
Removing either CPU bank's exception fails; the two CPU skips alone boot 3/3.
PMGR1 reparent-only fails while removal-only boots, proving that
the old curated regression came from flattening, not class removal. Removing
only AMCC/DCS/fabric/`soc_dpe` does not boot. Exact DTB hashes, negative controls,
and caveats about invalid whole-controller deletion tests are in
`done/2026-07-12-t6040-pmgr-matrix.md`.

The policy is now in the kernel DT source at Linux commit `4da589ce34d6`. The
rebuilt standard `t6040-j614s-dcuart.dtb`
(`34d6e8f574dec2d1b0669e3f03fb1df7b5e3cee278ac23a4cc304e903187d9c0`)
reached the Linux banner and BusyBox, so the standard build no longer depends
on an experiment-only variant DTB.

**Upstream-shaped selection (2026-07-13):**
The upstream draft is split in the required order: bindings in
`patches/t6040-pmgr-t6041-bindings.patch`, then driver behavior in
`patches/t6040-pmgr-t6041-quirks.patch`. The latter keys preserve-active
behavior and the two `dispext*_cpu` auto-enable exclusions from the
already-present T6041 compatible. Linux commit `37339d595765` removes all six
experiment-only booleans from the standard DT; `disp_cpu` remains disabled.
Both binding schemas validate. Kernel build #14 reached BusyBox with zero
`apple,preserve-active`/`apple,skip-auto-enable` properties in its DTB.
The split series also applies to a pristine case-sensitive clone, passes
checkpatch with zero warnings, and compiles `pmgr-pwrstate.o` there; this caught
and removed an accidental dependency on the older experimental patch.
Artifacts: `Image` SHA-256
`925303d09ae6190e8b0bc59824af6d621daefcbedc162f9787d495d3ed7c965a`,
DTB `a99ad7c3f304198280814de1e4a31d83c268751af608afad7003aa982a69f65a`.

`pmgr_adt2dt.py` was fixed in m1n1 `5dc76503` (curated branch `effcc16c`):
Apple `critical` no longer silently becomes Linux always-on policy, and parents
with `no_ps` no longer produce dangling phandles.

**Active/inactive encoding audit (2026-07-24):** the exact live J614s ADT
already marks the T6041/Max-only half correctly with the existing `no_ps`
bit. AMCC/DCS 0–15 use `0x09`; 16–31 use `0x19`. The real
dispext0/1 SYS/FE/CPU records use `0x00/0x02`; every dispext2/3 record uses
`0x10/0x12`. Current adt2dt emits 214 nodes and none of the inactive records.
Thus the IRC-suspected over-count was not reproduced on Mac16,8/25F84, and no
parser change is justified. Preserve-active plus the dispext0/1 CPU exceptions
remains the independently proven raw-boot policy. Full reconciliation:
`done/2026-07-24-t6040-pmgr-active-encoding.md`.

### Earlier blind investigation (historical context)

The full generated four-controller/214-domain `t6040-pmgr.dtsi` hangs the
kernel pre-console (inside apple-pmgr-pwrstate probe, before simpledrm).
Session 3 got the full DT to userspace with a **functional policy**
(`patches/t6040-pmgr-functional.patch`, build with `PMGR_FUNCTIONAL=1`):
- `apple,preserve-active` per controller (domains found active at probe are
  marked always-on);
- `apple,skip-auto-enable` on the locked dispext0/1 sys/fe/cpu domains;
- five ANE domains disabled (delayed async SError on raw boot);
- `disp_cpu@10000` disabled (first register access traps).

**Session-2 findings, with honest confidence** (all HW results are N=1 blind
pre-console hangs; determinism was never established by re-running a DTB):

| variant | pmgr config | result (N=1) |
|---|---|---|
| `pmgr01` | autogen pmgr0+1 (hierarchical), pmgr2+3 OFF | BOOTS userspace |
| `bis-nocpu` | autogen 0+1+2, pmgr3 OFF, only CPU domains disabled | logo-only |
| `safe2` | autogen, pmgr2 core-infra disabled (orphans children) | −517 defer storm, no userspace |
| `cur-pmgr01` | curated/reparented pmgr0+1, pmgr2+3 OFF | logo-only |
| `curated`/`bis-*` | curated, various pmgr2 subsets off | logo-only |

SOLID (~90–95%): the per-domain pmgr2 bisection was logically invalid (the
intersection of all hung tests' enabled sets came out empty — no single
culprit domain exists, assuming determinism); `pmgr_adt2dt.py` derives
`apple,always-on` from the ADT `critical` flag, which disagrees with yuka's
curated t8132 (over-marks pmc/pms_c1ppt/pms_fpwm0-4, misses aic) — a real
generator bug. PLAUSIBLE-not-isolated (~50–80%): pmgr-present→hang;
"killer is pmgr2 core-infra"; "reparent-to-root is fatal" (confounded);
"safe2's stall was the defer storm". The real obstacle was BLINDNESS —
which the DockChannel console now removes for everything post-userspace
(a pre-console printk poller into the FIFO would close the rest).

Curated-pmgr tooling from session 2 (prune_pmgr.py, bisect_build.sh, variant
dtsi/dts) lived in that session's scratchpad; the method is documented in
`done/`-era NEXT_STEPS history in git if needed.

## Dead ends (do not re-investigate)

- **Do not add T6040 to `cpuidle-apple` unchanged.** Its deep state
  unconditionally touches locked CYC_OVRD and executes WFI, while this machine
  requires `idle=nop` and has proven WFI/WFIT architectural-state loss. SMC
  provides hard wake events; it does not make CPU residency safe. Prerequisite
  order and evidence: `done/2026-07-24-t6040-suspend-feasibility.md`.
- **SBU analog serial on M4/ACE3:** ACE3 advertises action 0x306 but rejects
  every enter attempt (host VDM → BUSY 0x40030004; target-side DVEn via SPMI →
  result 0x3 for pin sets 2/7; pin set 0 accepted but no HW drain to SBU; pin
  set 1 maps UART onto D+/D− and kills the USB proxy). The dockchannel FIFO's
  real consumer is the KIS debug agent → DebugUSB is the supported path.
  Details in `done/2026-07-11-t6040-console-session.md` and memory.
- **No s5l serial console on M4 raw-boot;** the `...YG3` device is m1n1's
  vuart (hv-only → dead after handoff); m1n1 hv is SPTM-blocked entirely.
- **RAM-dump post-mortem:** iBoot scrubs DRAM on watchdog reset (verified:
  bytes read back all-zero). The ramdump script was deleted with the refactor.
- **USB gadget console (PARKED, not dead):** gadget enumerates but EP0 dies
  post-enumeration (raw + glue variants). Revisit for gadget-Ethernet+SSH
  after pmgr. `done/2026-07-11-t6040-usb-gadget-plan.md`. Gotchas recorded in
  memory: the ChatGPT desktop app squats USB devices; one enumeration per boot.

## 2026-07-25 — 🐧 MILESTONE B0: untethered Linux boots on the M4 Pro

Enrolled `m1n1-b0-diet-aligned.bin` (`f290833c`, 9,469,952 B = 578 × 16 KiB) from
1TR; cold boot from the boot picker reaches `wallace-b0:~#` on the internal panel
with **no cable and no host**. Maintainer-confirmed: OpenRC default runlevel,
`loaded no-mac.bmap`, `watchdog0=present`, `Apple DockChannel Keyboard 05ac:0359`
on `event0` with æ ø å correct, `simpledrmdrmfb`, `/proc/partitions` empty,
network runlevel empty, health report begin→end.

**Root cause of every earlier enrolled failure: the object's total size must be a
multiple of the 16 KiB page size.** Non-aligned objects are never executed — no
m1n1 entry, no panel output, no USB gadget, no logbuf — and iBoot resets ~every
5 s, five times, then shows the reinstall screen. The fix on the failing 9.02 MiB
object was 14,796 zero bytes of padding; `t6040-build-raw-object.py` now pads and
asserts the invariant.

This superseded six earlier hypotheses (object size in MiB, compression format,
kernel size, m1n1 prefix, payload discovery, SEPFW adjacency/load extent, the
early-proxy window, and payload content/obfuscation). It stayed hidden because
every control probe was *accidentally* page-aligned — `truncate -s Nm`, whole
64 KiB blocks, and `m1n1-raw.ld`'s `0x4000` section alignment — so controls
differed from test cases in an untracked variable and every "content" correlation
was an artefact of the generator.

Same day: diet kernel (50.8 → 16.8 MiB raw, −67%, 31-symbol essentials assertion);
XZ members (22.2 MB → 9.02 MiB); Norwegian keymap fixed (`busybox loadkmap` reads a
binary keymap on **stdin**; BusyBox has no `loadkeys` and ships no applet symlink),
with the result mirrored into the ttydc0 health report so it is agent-verifiable;
and ticket 127 proved m1n1's **own** `nvme_init()` raises an async L2C SError on
T6040, i.e. the NVMe boundary is enforced below the OS (Linux-side work alone
cannot cross it).

### 2026-07-25 (later) — untethered Ubuntu, and the dual-mode window proven both ways

**Ubuntu 24.04 boots untethered** (`m1n1-b0-ubuntu-smoke.bin` `4784c29c`, 22.59 MiB):
glibc shell on the internal panel, no cable. This also settles large-payload
decompression — a 16.8 MiB XZ member expanding to a 97.3 MiB cpio unpacked into RAM and
handed off cleanly.

**Dual-mode daily driver proven both ways** (`b409d89e`, m1n1 v6 `c10a502f`, ticket 140):
with no host attached it waits 10 s, times out and boots Alpine; with a host polling for
the gadget it prints `Waiting for proxy connection...  Connected!` and stays in
`uartproxy` without booting the payload — full chainload/debug on an enrolled,
otherwise-untethered machine. `sip0 = 0` here, so upstream's gate could never have armed;
the `EARLY_PROXY_UNCONDITIONAL` patch is what creates the door, and this is the first time
it was observed on an *enrolled* boot (every earlier attempt was 16 KiB-misaligned and
never ran).

**No object-size ceiling** found: 64 MiB and 256 MiB graded probes both load in full, so
ticket 080's policy moves from an assumed to a measured 256 MiB. Object size is no longer
a design constraint — the binding limit is RAM for the unpacked root.

Two harness rules learned: a window-carrying object cannot be tethered-smoke-tested (its
own window catches `chainload.py`'s handshake), so smoke objects need a window-free m1n1
(`ecd264a5`); and the USB gadget cannot observe an image whose console is `tty0`+`ttydc0`,
because gadget and DebugUSB/KIS are mutually exclusive on the DFU port — smoke such
images over KIS.

### 2026-07-26 — PCIe `_initializePhy` decoded to absolute addresses (ticket 124)

Decoded `ApplePCIEBaseT8132::_initializePhy()` from the paired kernelcache, then resolved
its apertures against the live `/arm-io/apcie0` ADT read over the rollback-loader proxy
(read-only fetch, no MMIO poke).

- **First PHY-init hardware op** = read-modify-write of **PhyCommon register `0x0`, set bit 0**
  (`mov w1,#0; _readPhyCommonReg; orr w8,w8,#1; _writePhyCommonReg`). A PhyPhy read follows;
  a second PhyCommon write comes later.
- The accessors reveal a **shared PHY aperture**: `_readPhyCommonReg(N)` adds `+0x4000`,
  `_readPhyPhyReg(N)` adds `+0x8000`, both dispatching the same vtable slot `+0xb28`.
  `_readPhyIPReg` instead dereferences a cached per-port base at **`this+0x240`** and panics if
  null — so 068's op-115 hang is a *non-responding aperture*, not a null pointer.
- The `dtRegMap*Index()` accessors are **not constants**: they read consecutive per-instance
  ivars (`[this+709]` ApcieCommon, `[710/711]` Phy, `[718]` PortPhyGlue, `[719]` PortPhyIP)
  filled at probe from the ADT. Apple's ADT has **no `reg-names`** — `apcie0` is index-mapped
  (35 regs = 7 header + 4 ports × 7), which is exactly why the driver caches indices.
- Resolved absolutes: `reg[2]=0x217000000` is the shared PHY region, so **PhyCommon[0] =
  `0x217004000`**, **PhyPhy = `0x217008000`**, and the op-115 read that hangs is
  **`0x217048090`** (port0 PHY-IP `0x217048000 + 0x90`; `+port*0x8000`).
- **Grounded missing precondition:** before reading `0x217048090`, set bit 0 of `0x217004000`
  and run PhyPhy setup at `0x217008000` — m1n1 does neither today.

Not done autonomously: a live read of the PHY aperture risks an ungated-aperture SError that
would wedge the tether (same class as the NVMe `nvme_init` SError), so the exact PhyPhy
register/value pairs and the second PhyCommon write are deferred to an attended session, along
with one separately-gated m1n1 candidate. **068 stays un-retried.** Full trace in
`done/2026-07-26-t6040-pcie-initializephy-trace.md`.

### 2026-07-26 (later) — the 16 KiB-page kernel boots (147), and two wrong-object runs

**Ticket 147 PASSED.** The DIET_CAPABLE kernel — 16 KiB pages, forced by `PCIE_APPLE`'s
`PAGE_SIZE_16KB` dependency — boots cleanly on T6040 with the proven Alpine RAM root:
health report begin→end, `fb0=simpledrmdrmfb`, `Apple DockChannel Keyboard` on `event0`,
`watchdog0=present`, empty network runlevel, `loaded no-mac.bmap`, `wallace-b0:~#`, no
panic/Oops, no NVMe/xHCI/usb-storage, nothing mounted. Every proven boot before this used
4 KiB pages, so this was an ABI-level unknown; it is now cleared and **149 is unblocked**.

Object `m1n1-b0-dietcap-smoke.bin` `ac24d4bf` (14,893,056 B = 909 × 16 KiB). Confirmed as the
object that actually ran via `Loading kernel image (0xe34004 bytes)` = filesize + the 4 zero
bytes `chainload.py` appends.

#### `/proc/partitions` is not empty, and that is correct

```
1  0  524288 ram0        <- BLK_DEV_RAM_COUNT=1, BLK_DEV_RAM_SIZE=524288 (exact match)
31 0      16 mtdblock0   <- m1n1_stage2.log
31 1     592 mtdblock1   <- adt
```

The "empty `/proc/partitions`" criterion was inherited from the 4 KiB diet kernel, which has no
block layer; DIET_CAPABLE re-adds `BLK_DEV_RAM`/`MTD`/`MTD_BLOCK`/`MTD_PHRAM` by design.

`cat /proc/mtd` settled the mtd devices: `mtd0 00004000 00004000 "m1n1_stage2.log"` and
`mtd1 00094000 00004000 "adt"`. **These are m1n1's own debug nodes**, not flash — its stage2 log
buffer and a copy of the ADT (`0x94000` is exactly the size the proxy reports when fetching the
ADT). `erasesize` is `0x4000`, the native page size. m1n1 patches these into the *live* devicetree,
which is why the on-disk DTB `2782b922` has no mtd/spi-nor/nvram node at all — and why they were
invisible on the 4 KiB kernel, which simply lacks MTD to expose them. Storage-free premise intact;
ticket 150 closed benign. Bonus capability: **m1n1's stage2 log and the full ADT are readable from
Linux userspace with no tether** (ticket 152) — useful for post-mortem on an *untethered* boot,
currently a blind spot.

#### Do not conflate the two 16 KiB rules

| | Constrains | Status |
|---|---|---|
| enrolled-object alignment (2026-07-25) | an **enrolled object's total byte length** must be a multiple of `0x4000` or iBoot never enters m1n1 | **still required** |
| kernel page size (147) | `ARM64_4K_PAGES` vs `ARM64_16K_PAGES` (MMU granule) | 16 KiB proven to boot |

Both are 16 KiB only because that is the Apple Silicon native page size. **147 could not have tested
alignment**: a tethered chainload bypasses iBoot entirely, and alignment is an iBoot load-path
constraint on *enrolled* objects only.

#### Harness lesson: two runs booted the wrong object, and the guard said OK

Attempts 1 and 2 both booted `m1n1-b0-alpine-hid-restored.bin` instead of the staged object:

1. the object was passed **positionally**, but `t6040-boot-raw-object.sh` read `OBJECT` from the
   environment and ignored `$1`;
2. the retry used **semicolons** — `OBJECT=…; OBJECT_SHA=…; bash script` is four separate commands
   whose assignments are shell-local and never reach the child, so the script saw an empty
   environment.

Both times it fell back to a hardcoded default **and its SHA guard passed**, because it validated
the default it had selected for itself. Detected from `Loading kernel image (0x14b8f13)` =
21,729,039 + 4 ≠ the staged 14,893,056, and independently from the panel's `uname`
(`7.1.3-g96ac043df12f-dirty`, built Jul 24; dietcap is `7.1.3-g246843ff67a8-dirty`).

**Fix: the script now has no default object.** The object *and* its sha256 must be named on every
run; a positional two-argument form is preferred because it survives semicolon-pasting; extra,
unknown or conflicting arguments are hard errors. A bare run with an empty environment now exits 2
instead of booting something historical.

> **A guard that validates a value the script chose for itself proves nothing about the value the
> caller intended.** On a rig where every run costs a reboot, a convenience default is a
> silent-wrong-answer generator: for an operation whose whole purpose is *which bytes ran*, there
> should be no value the script can supply on the caller's behalf.

Two further hazards found and ticketed rather than papered over: the harness prints
`chainload failed` on a **successful** boot, because `chainload.py` ends with an `iface.nop()` that
must time out once Linux owns the UART (**151**, P1 — this is exactly the pass/fail misattribution
class above); and the kernel's dmesg never reaches KIS since the proven bootargs use `console=tty0`
only, which is why 147 needed an attended session and a screenshot (**153**). **154** adds a
build-time page-size assertion, checked from the arm64 Image header (`flags` @ +24, bits 1-2) —
**not** from `strings`, which reports a literal `4K pages` message inside the 16 KiB dietcap Image.

### 2026-07-26 (evening) — capability over size: the fat image, and three harness fixes

**148's failure changed the build policy.** Xorg died with
`Cannot establish any listening sockets` / `Function not implemented` — ENOSYS, because the diet
kernel carries `# CONFIG_NET is not set` and therefore has no `CONFIG_UNIX`. X11 needs an **AF_UNIX**
listening socket, so the server never touched the display. Neither failure mode the ticket predicted
(simpledrm probe, missing pointer) was involved. We stripped networking to save a few MiB of a 33 MiB
kernel and lost X entirely.

That trimming was justified by a ceiling **nobody ever measured**: ticket 137 found no object-size
limit to 256 MiB, and 256 MiB was the *probe* limit and a *policy* number, not hardware. RAM is
23.8 GiB. In one image the trimming cost software GL (llvmpipe cut to fit the assumed ceiling) *and*
X itself (`CONFIG_NET`). **Policy inverted (ticket 155): build for capability, shrink only if
something actually overflows.**

#### The fat graphical object

`m1n1-b0-dwm-fat.bin` `c5438779` (83,197,952 B = 5078 × 16 KiB), strict PASS, bootargs
byte-identical to the proven set. **No kernel rebuild was needed** — the existing full
`Image-hid-type-fix` already has `NET`, `UNIX`, `SYSVIPC`, `INPUT_EVDEV`, `DRM_SIMPLEDRM`,
`DRM_KMS_HELPER`, `DRM_GEM_SHMEM_HELPER` and the `TTM`/`SCHED`/`DISPLAY_HELPER` helpers DIET drops.
It also beats DIET_CAPABLE here: **4 KiB pages**, so a graphical change does not ride on an ABI
change; it carries the DockChannel HID keyboard fix; and it is **already live-proven**, being the
kernel inside `hid-restored`, which reached a shell with `event0` three times today via the
wrong-object incidents. `FAT=1` keeps libLLVM/libgallium/57 DRI drivers and adds
`mesa-dri-gallium`/`kbd`/`xdpyinfo`/`xev`.

**Norwegian layout was broken in the thin image and is now fixed and tested.** `kbd-bkeymaps` ships
`no-mac.bmap.gz`, while the inittab read `no-mac.bmap` — so the console keymap silently failed, and
`setxkbmap no` never ran either because X never started: *no* Norwegian layout by either path. The
inittab now tries `.bmap` then `zcat`s `.bmap.gz`; verified by running the exact inittab logic against
the real file from the built image (falls to the `.gz` branch, pipes 33,031 bytes, exit 0).

#### Three harness fixes, all from today's own failures

- **151** — the harness reported `chainload failed` on a **successful** boot. `chainload.py` ends
  `iface.nop(); print("Proxy is alive again")`, and that nop() *must* time out once Linux owns the
  UART, so a non-zero exit is the normal outcome of a good one-object smoke. The verdict now comes
  from log markers derived empirically from today's logs (`Valid payload found` + ≥2
  `Vectoring to next stage`), with FAIL reserved for rejected payloads, kernel faults and
  no-handoff. Verified against three real logs and four synthetic ones.
- **154** — `t6040-kbuild.sh` now derives the page size from the arm64 Image header (`flags` @ +24,
  bits 1-2) with `od`, prints it, and asserts DIET ⇒ 4K / DIET_CAPABLE ⇒ 16K **before** publishing
  the artifact, cross-checked against `CONFIG_ARM64_*_PAGES`. The object verifier now reports
  `pages=4K`/`pages=16K` too. **Never `strings`** — the 16 KiB dietcap Image contains a literal
  `4K pages` message string.
- **153** — `m1n1-b0-dwm-fat-diag.bin` `d14df9f3`, identical to the fat object except
  `console=ttydc0` added, so the machine reports its own dmesg over KIS. Twice today a run could not
  be judged from the host (the 148 pty went silent at handoff with a **0-byte** console log, leaving
  a screenshot as the only evidence). Checked rather than assumed: the DTB's
  `apple,dockchannel-serial` node has no `status` so it defaults enabled, there is no `stdout-path`,
  and KIS *can* observe `ttydc0` — it is the gadget that cannot.

#### Probe builder (156)

`scripts/t6040-build-graded-probe.py` is new, and **validated by byte-exact reproduction**: it
regenerates the enrolled-and-proven `probe-graded-256M.bin` with hash `c7fcfa71`, the value in the
2026-07-25 writeup. Built `probe-graded-512M.bin` (`59eb0a1a`) and `probe-graded-1024M.bin`
(`91e4d692`) on the currently-enrolled loader, so size is the only variable. **512 MiB was never
established** — 256 MiB remains the largest measured size.

> The through-line for all of today: **every guard that failed us was validating something other than
> what was intended** — a default object instead of the named one, `chainload.py`'s exit status
> instead of the boot, an assumed size ceiling instead of a measured one, a stripped config instead
> of a working one.

### 2026-07-26 (night) — the kernel was not reproducible, and three harness fixes

**The DockChannel TTY driver was never in version control (159).**
`drivers/tty/apple_dockchannel_tty.c` — 464 lines providing `/dev/ttydc0` — existed only as an
**untracked** file inside the podman build trees, with `drivers/tty/Kconfig` and `Makefile` modified
alongside it. Present in all three `/build/linux-*` trees, absent from `~/Code/linux` and from
`patches/`. So **a rebuild from a clean checkout silently produced a kernel with no `ttydc0`**, losing
the DockChannel shell and the transport every B0 acceptance run reports through — and it is why every
built kernel reported `-dirty`.

It also meant the two patches that *modify* that driver (`earlycon-debug`, `nbcon`) could never have
applied to a fresh clone, and that the DIET assertion "verified" `CONFIG_APPLE_DOCKCHANNEL_TTY=y` by
grepping `.config` text — which passed because `scripts/config -e` had written it, while the capability
existed only by virtue of untracked files. **Another guard validating a string, not a capability.**

Recovered into `patches/t6040-dockchannel-tty-driver.patch`, applied from kbuild **before
`olddefconfig`** so the symbol is real; kbuild now fails loudly if neither patch nor driver is present.
Verified by byte-identical reconstruction on a clean tree (`2880e145…`, 464 lines). A sweep of all
three trees found **9 of 11** other modified paths already covered by `patches/`; the two that were
not — the `apple,dockchannel-serial` binding and its MAINTAINERS entries — belong to the same feature
and are folded in. **The kernel is now reproducible from the repository.**

#### Why 153's diagnostic object is inert

The shipping driver is a **TTY only**: no `register_console`, no `struct console`, no `CON_*`. So
`/dev/ttydc0` exists (hence a userspace getty works, and that is how the 147 health report reached the
host) but **`console=ttydc0` matches nothing and is silently ignored** — no kernel dmesg ever leaves
the machine. `patches/t6040-dockchannel-nbcon.patch` adds the real console and, verified, **applies
cleanly** on top of the recovered driver, so 153 is one rebuild away. Not built yet, so the pending
`c5438779` test changes one variable.

**Correction:** the duplicated dmesg and ghosted glyphs on the panel were attributed to two
`CON_PRINTBUFFER` registrations. Impossible — `ttydc0` never registers. It is the **single** fbcon
handover replay plus fbcon written from replay and live-printk contexts, so it appears on the plain
object too and is cosmetic.

#### Harness (151/157/158)

Three defects, each having cost real rig time the same day:

- **Dead-proxy uploads (157).** `[ -e /tmp/m1n1 ]` proved only that a symlink existed. That passed
  three times against a pty with nothing behind it — once a stale `kisd`, twice because a previous
  chainload **had already booted Linux and thereby consumed the proxy it needed**. Each cost a silent
  5-minute timeout with a 0-byte log. `t6040-proxy-alive.py` now makes the proxy prove itself with one
  read-only `REQ_NOP`. **Operational rule this exposed: every successful chainload destroys the proxy,
  so `t6040-debugusb-console.sh reboot` is mandatory before *every* chainload.**
- **Orphaned uploaders (158).** The `timeout` wrapper was reparented to init when the script's parent
  was killed, and its python child kept running. One such orphan had pushed **~41 MiB into the pty**
  and then sat holding it, silently corrupting the next two runs — two writers on one transport, the
  target stuck at `Running proxy`. `set -m` plus an EXIT/INT/TERM trap now kills the whole process
  group; proven with a stand-in (both wrapper and child gone after SIGTERM). SIGKILL remains
  uncoverable.
- **Invisible progress and a fixed timeout (158).** Python block-buffers stdout to a file, so a healthy
  upload looked identical to a hang. `PYTHONUNBUFFERED=1` plus a `tail -f` hint fixes that; the timeout
  is now `120s + 5s/MiB`. The old fixed 300 s was marginal-but-sufficient for the 79 MiB object
  (measured ~120 s at ~0.7 MB/s) but would genuinely fail 156's 512 MiB probe (~730 s).

> **Diagnostic tell for any future upload:** CPU time must climb past ~5 s within the first 10 s
> (connect + ADT fetch + transfer start). Pinned at `0:00.09` / 0.0% means nothing is behind the pty.

### 2026-07-26 (late) — the fat object never unpacked, and the guard I removed had been right

`m1n1-b0-dwm-fat.bin` reboots without reaching a shell:

```
check access for rdinit=/sbin/init failed: -2, ignoring
VFS: Cannot open root device "" or unknown-block(0,0): error -6
```

`/sbin/init` **is** in the image (entry 426 of 4217), so the file was never the issue — **the
initramfs was never unpacked.** Host-side console log, first line: **`XZ decode failed`**, and no
`FDT: initrd at ...` line, which `kboot.c` prints whenever it passes an initrd. m1n1 decoded nothing,
set no initrd, and the kernel booted an empty rootfs. Timestamps corroborate: everything under 0.16 s,
whereas unpacking 279 MiB takes seconds.

Both fat objects share initramfs `ad1fe88b`, so **both are broken** — the earlier "reached userspace"
reading of the diag run was wrong, its screenshot having stopped at 0.131 s, just above the failure
lines. The `simpledrm` probe seen there still stands, since DRM initialises before a rootfs is needed.

**Measured boundary:** 13.1, 50.8, 60.5 and 97.3 MiB expanded all decode; **278.9 MiB fails**. True
limit in **(97.3, 278.9] MiB**, unmeasured — ticket 160. Two mechanisms were checked and *ruled out*
rather than assumed: XZ block-header size metadata (byte-13 flags `0x0000` on every member, working and
failing alike, so minilzlib's documented restriction is not it) and dictionary/filter differences
(`xz -lvv` identical across all: 1 stream, 1 block, CRC32, 65 MiB). Suspect is `payload.c` decoding
into `heapblock_alloc_aligned(0, …)` — the uncommitted heap top — with `dest_len = 1 << 30` and no
bound check in `heapblock_alloc_aligned`.

#### The self-inflicted part

The verifier **had rejected this object**: `initramfs expands to 292422732 bytes, over B0 limit
268435456`. I raised `MAX_INITRAMFS_EXPANDED` 256 MiB → 1 GiB, arguing it was "an arbitrary policy
number", "a RAM guard, not a load-path limit", against 23.8 GiB of RAM — and wrote that I was
deliberately *not* fitting the guard to my build, while raising it four-fold so my build would pass.
The binding constraint is m1n1's decoder, not RAM. Restored at **128 MiB**, above every proven-good
size and below the known-bad one.

> Today's earlier lesson was that guards often validate the wrong thing. The inverse is just as real:
> **a guard whose rationale I cannot reconstruct is not thereby arbitrary.** "I don't see why this
> limit exists" is a reason to find out, not a licence to raise it.

#### Replacement

`m1n1-b0-dwm-fullkernel.bin` `6738aad9` (28,213,248 B = 1722 × 16 KiB, strict PASS): full kernel
`cbb3e743` + the **thin** dwm rootfs `dcc5555a` (60.5 MiB expanded, proven to unpack) rebuilt with the
keymap fix + proven bootargs `3659a0da`. What fixed 148 was the kernel; the restored llvmpipe was the
nice-to-have that pushed the rootfs over the limit. **Versus the object that booted in 148, exactly one
variable changed.**

### 2026-07-26 — 🐧🖥️ dwm runs on the panel with a working keyboard

Object `3ec81ef3` is a pass: tags 1–9, `[]=`, `st`, `dwm-6.8`, blue border, `Alt+Shift+Return` spawns a
terminal, `Alt+p` opens dmenu, æ ø å correct. Trackpad dead as designed (004/126). The full chain works
end to end — raw object → m1n1 → full kernel → Alpine RAM root → Xorg/modesetting on simpledrm → dwm →
st → keyboard.

**Two blockers, neither of them the predicted one.** Ticket 148 warned that `modesetting` might fail to
probe simpledrm because DIET drops `DRM_TTM`/`DRM_SCHED`/`DRM_DISPLAY_HELPER`, and that Xorg might refuse
without a pointer. Both were wrong:

1. the diet kernel had `# CONFIG_NET is not set`, hence no `CONFIG_UNIX`, hence no **AF_UNIX** socket —
   `Cannot establish any listening sockets` / `Function not implemented` (ENOSYS);
2. after the full kernel fixed that, dwm loaded but **no input worked at all**: the image carried
   `libudev.so.1` as a dependency of Xorg/libinput but no `udevd`/`udevadm`, so the udev database was
   never populated and `xf86-input-libinput` enumerated zero devices. `eudev`, started before X, fixed it.

`simpledrm` probed cleanly the first time the full kernel ran.

#### HiDPI: one symptom, three independent mechanisms

Text rendered at roughly a quarter size — the panel is 3024×1964 on 14.2″ ≈ **254 DPI** while X assumes
96. The pre-existing `xrandr --dpi 192` **could not have fixed `st`**: Alpine builds st with a
**`pixelsize=`** font, which ignores every DPI setting. The fix needs all three, because they consult
different sources of truth:

- `startx -- -dpi 192` — what the display reports;
- `Xft.dpi` via `~/.Xresources` + `xrdb -merge` — what Xft uses for **point** sizes, and therefore the
  only lever for **dwm's bar and dmenu**, whose fonts are compile-time `monospace:size=10` in the
  suckless config and cannot be changed without rebuilding those binaries;
- `st -f 'monospace:pixelsize=28'` — explicit, because of the above.

`xrdb` was not installed at all, so `Xft.dpi` could never have been loaded. Tunable at boot by
`T6040_DPI` (default 192, the 2× convention) and `T6040_ST_PIXELSIZE` (default 28); 254 is the panel's
true DPI if physical accuracy is preferred. Object `m1n1-b0-dwm-hidpi.bin` `59622e78` — identical to the
working object except the initramfs, so it cannot regress input or graphics.
