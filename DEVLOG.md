# t6040 (M4 Pro, Mac16,8 / J614s) Linux bring-up — DEVLOG & operational reference

State of the world, how to operate the rig, solved blockers, investigation
history, and dead ends. Forward-looking work lives in `NEXT_STEPS.md`; the
long-term plan in `roadmap.md`; per-session write-ups in `done/`.

## Current working state (2026-07-12)

| Works | Notes |
|---|---|
| Mainline Linux (7.2-rc2 + 3 small patches) to BusyBox userspace | minimal DT, maxcpus=1, reproducible |
| Two-way m1n1 proxy/console over DebugUSB (KIS) | one DP/TB cable in the DFU port; no second machine-side cable needed |
| Two-way **Linux shell** on `/dev/ttydc0` over the same cable | poll-mode dockchannel driver; full remote dev loop, no screen-reading |
| Internal keyboard (+trackpad registers) at the shell | dockchannel-HID; trackpad start currently fails |
| Framebuffer console (simpledrm + fbcon) | the early-boot console; dcuart covers post-probe |
| Linux `apple_wdt` takes over m1n1's watchdog | shell survives past the 20 s bite |
| Remote reboot via `macvdmtool` | full autonomous reboot→chainload→boot→shell cycle |

Active: full PMGR topology boots reproducibly with the exact minimal raw-boot
policy; only its upstream shape remains (see PMGR section).
Trackpad firmware loading is implemented; provisioning the paired J614s blob is
next. Parked: USB gadget console (EP0 dies post-enumeration;
`done/2026-07-11-t6040-usb-gadget-plan.md`).

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
   chainload.
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
`feature/m4-m5-minimal-device-trees` (yuka's remote; mainline 7.2-rc2 + DT
commits). Working build dir inside the container: `/build/linux-keyboard`.

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
`~/Code/linux` (partly uncommitted); the dcuart board variant is preserved at
`~/Code/wallace/dts/t6040-j614s-dcuart.dts` (self-contained: defines the
dockchannel-uart nodes under &soc itself).

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
directory. The actual blocker is retrieving this target's ESP copy at
`vendorfw/apple/tpmtfw-j614s.bin` (or its `asahi/all_firmware.tar.gz`); neither
is present on the development host. GPIO proxying remains intentionally absent
until any request and
its J614s ADT mapping are captured and reviewed. A later ADT-only capture found
`function-afe-reset = pKW4('gp1c', 0x10000)` through phandle 294,
`/arm-io/smc/iop-smc-nub/smc-pmu`. The legacy pulse would write SMC key `gp1c`
as `0x10001` then `0x10000`; do not implement or exercise it under the absolute
no-PMU-write rule. Details:
`done/2026-07-12-t6040-trackpad-firmware.md`.

### DockChannel-UART Linux console (2026-07-12)
Kernel side: `origin/dockchannel` mailbox + tty drivers + a t6040 board DT
variant. **The t6040-specific discovery: the ADT-declared AIC irq 360 for the
dockchannel-uart AP FIFO NEVER fires.** Probed live from m1n1: the FIFO irq
block (+0xc000) latches flags and takes mask writes fine, but with all 4096
AIC inputs unmasked, no HW_STATE bit tracks the FIFO mask toggle. Without an
IRQ the stock driver TX-stalls at exactly one 2 KiB FIFO fill (send_data
completes only from the IRQ handler) and RX is dead — the "banner then
silence" signature. Fix: `patches/t6040-dockchannel-poll.patch` adds an
`apple,poll-mode` DT property (5 ms delayed-work poll; TX-done on FIFO-drain,
RX via RX_COUNT). m1n1 and the KIS dock-side agent poll this FIFO too.

Open question (not blocking): where does that irq line actually go —
fused off on the chopped die, routed to AOP, or KIS-agent-only? XNU's
pe_serial dockchannel path may answer (ADT has `enable-sw-drain=1`).

MMIO caution: the dockchannel-uart block maps ONLY +0xc000 (irq, 24 B) and
+0x28000..+0x38004 (config/data). Reading other offsets (e.g. +0x20000) raises
an async SError that kills m1n1 — unlike dockchannel-mtp, which maps
+0x0/+0x14000/+0x28000../+0x30000..

Note: the tty driver registers no printk console — `console=ttydc0` does
nothing; the shell + dmesg cover post-userspace, fbcon covers early boot. A
code review confirmed that simply adding `register_console()` would be unsafe:
TTY TX only enqueues into a kfifo and schedules `system_wq`, so it cannot emit
synchronously in atomic/panic context, and its send-error path can printk while
holding the same TX lock a console callback would need. A real console requires
a separate bounded polled/atomic mailbox transmit primitive (preferably nbcon),
not reuse of `apple_dctty_write()`.

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
The next live diagnostic ran at m1n1 main `88ce1ee3`, binary SHA-256
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
The upper-guard control ran at main `a61fd099`, binary SHA-256
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
`b5ced9ba` (`v1.6.0-81-gb5ced9ba`), binary SHA-256
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
Full details are in `done/2026-07-14-t6040-wireless-pcie-map.md`.

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
