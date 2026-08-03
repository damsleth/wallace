# T6040 USB2 external-root artifact set (2026-07-14)

Ticket 032 (offline, P1, storage track). Rebuildable, hash-pinned artifact set for booting
Linux with root on an external USB2 disk (ticket 009 design; internal NVMe
SPTM-blocked, ticket 008), built on ticket 031's USB2-host DT candidate. Static
build only; stops before any rig run.

## What this delivers

| Artifact | What | Status |
|---|---|---|
| `patches/t6040-dwc3-apple-force-host.patch` | the enabler: `apple,force-host-mode` | in repo; **applies clean on `wallace/t6040-bringup`** (verified in the kbuild container) |
| `dts/t6040-j614s-dcuart-usb-host.dts` | USB2 host DT (all 3 ports forced host) | in repo (ticket 031); dtc-clean |
| `scripts/t6040-init-usb-root` | dual-mode init (smoke + root) | in repo |
| `scripts/t6040-kbuild.sh` `USB_HOST=1` block | reproducible kernel config + patch-apply + DTB | in repo |
| kernel `Image-usb-host` / `.dtb` / `initramfs-usb-root.cpio.gz` | built binaries + hashes | **gate 1 cleared — built on `wallace/t6040-bringup` (see update below)** |

**Build status (2026-07-14):** the `USB_HOST=1` kernel build was attempted in the
warm kbuild container against `BRANCH=t6040-usb-wip`. The force-host patch applied
cleanly (`t6040-dwc3-apple-force-host.patch applied OK`), but the build then
failed applying a *mainline-required* patch — `t6040-pmgr-t6041-quirks.patch`
does not apply to `t6040-usb-wip`'s `pmdomain/apple/pmgr-pwrstate.c`. So
`t6040-usb-wip` is not a clean superset of the mainline bring-up branch: the USB
driver work and the PMGR/other bring-up work sit on divergent branches, and
neither branch alone builds a bootable USB-host image. Producing the binaries is
therefore gated on integrating the dwc3-apple USB work and the mainline bring-up
series onto one branch (gate 1) — a coordination step, not attempted here. Config,
patch, DT, and init are all validated and reproducible; only the final link is
blocked.

**Gate 1 cleared (2026-07-21):** the branch divergence no longer exists. Both work
streams — the dwc3-apple `force-{device,host}-mode` driver work (`DWC3_APPLE_HOST`
enum + `apple,force-device-mode` base) and the full T6041 PMGR series — now live on
`wallace/t6040-bringup`. There is no separate `t6040-usb-wip` to rebase; the two
converged onto the one bring-up branch. Verified against that branch's tip
(`96ac043df12f`): `t6040-pmgr-t6041-bindings.patch`, `t6040-pmgr-t6041-quirks.patch`,
and `t6040-dwc3-apple-force-host.patch` all apply as a clean stack, and a full
`USB_HOST=1 DOCKCHANNEL=1 BRANCH=wallace/t6040-bringup` build in the kbuild
container applied every patch (`t6040-pmgr-t6041-quirks.patch applied OK`) — the
exact line that failed on `t6040-usb-wip`. **The build recipe below must use
`BRANCH=wallace/t6040-bringup` (the default), not the stale `BRANCH=t6040-usb-wip`.**
Built binaries + hashes recorded at the end of this file.

## The enabler: apple,force-host-mode

`dwc3-apple` is role-switch driven — on probe it stays in
`DWC3_APPLE_PROBE_PENDING` and only enters host/device mode on a Type-C cable
event. The current T6040 Linux DT has no supported SPMI-HPM/Type-C path to
deliver one, so `dr_mode="host"`
alone never brings the port up. The in-tree `apple,force-device-mode` handles
this for gadgets; `patches/t6040-dwc3-apple-force-host.patch` adds the symmetric
`apple,force-host-mode` (forces `dwc3_apple_init(HOST)` at probe) — an exact
structural mirror of the device-mode block.

## Kernel config (in `scripts/t6040-kbuild.sh`, `USB_HOST=1`)

Built-in so root is reachable with no modules: `USB`, `USB_XHCI_HCD`,
`USB_XHCI_PLATFORM`, `USB_DWC3` + `USB_DWC3_HOST` + `USB_DWC3_DUAL_ROLE` +
`USB_DWC3_APPLE`, `APPLE_DART`/`IOMMU_SUPPORT`, `USB_STORAGE`, `USB_UAS`, `SCSI`,
`BLK_DEV_SD`, `EXT4_FS` — on top of the proven DockChannel-console + fbcon base
(`DOCKCHANNEL=1`). No ATC PHY / USB3 / Thunderbolt (deferred; USB2 high-speed
only).

## initramfs init (`scripts/t6040-init-usb-root`)

One init, two modes:
- **SMOKE** (no `root=` resolves): report dwc3/xhci/dart/usb-storage dmesg, USB
  device tree and two `/proc/partitions` snapshots 10 seconds apart over the
  DockChannel console, then a shell. This is the rig smoke test — proves the
  forced-host port enumerates a device and survives past enumeration.
- **ROOT**: `root=PARTUUID=<uuid>` (also `LABEL=`/`UUID=`/`/dev/*`), waits up to
  30 s for the disk, mounts `rootfstype` (default ext4), `switch_root`.
It never mounts an internal device; any failure stops at a diagnostic shell.

## Build recipe (turnkey)

```sh
cp ~/Code/wallace/scripts/t6040-kbuild.sh ~/Code/wallace/patches/*.patch ~/Code/linux-build-out/
cp ~/Code/wallace/dts/t6040-j614s-dcuart-usb-host.dts ~/Code/linux/arch/arm64/boot/dts/apple/
podman exec -e DOCKCHANNEL=1 -e USB_HOST=1 -e BRANCH=wallace/t6040-bringup \
    -e BUILD_DIR=/build/linux-usb-host4 -e NPROC=1 \
    kbuild bash /out/t6040-kbuild.sh image
# initramfs:
OUT=~/Code/linux-build-out INIT_SOURCE=~/Code/wallace/scripts/t6040-init-usb-root \
    DEST=~/Code/linux-build-out/initramfs-usb-root.cpio.gz \
    bash ~/Code/wallace/scripts/t6040-make-initramfs.sh
```

Note the **branch**: as of 2026-07-21 the dwc3-apple USB driver work
(force-{device,host}-mode) and the T6041 PMGR series both live on
`wallace/t6040-bringup` — this is the default branch and the one to build. The old
`BRANCH=t6040-usb-wip` is stale (gate 1 was the divergence between them; now
resolved). If the container's 8 GB VM flakes on `-j$(nproc)` with transient
"No such file"/`fixdep` errors (a virtiofs/memory-pressure race, not a code
failure), retry from an isolated copy of a known-good build directory with
`NPROC=1`. The successful build used `/build/linux-usb-host4`; output from the
flaky `/build/linux-usb-host3` tree was discarded.

## External rootfs recipe (populate only after the smoke gate)

Ticket 060 now supplies the reproducible, guarded implementation:
`scripts/t6040-populate-usb-rootfs.sh`, documented in
`done/2026-07-23-t6040-usb-rootfs-recipe.md`. It pins the Alpine 3.24.0 aarch64
minirootfs, creates GPT + ext4 `LABEL=t6040root`, records fresh disk/partition/
filesystem UUIDs, installs the matching modules tree and full firmware corpus,
and emits the exact `root=PARTUUID=...` bootarg plus per-file manifest.

Its safe `stage` mode is host-tested. Its destructive Linux-only `device` mode
requires a whole removable disk and literal `ERASE:<device>` confirmation.
Do not use `device` mode until a USB child and `sd*` persist for at least ten
seconds; the 2026-07-21 passive-stick smoke did not clear that gate.

## Bootargs

```
console=ttydc0 maxcpus=1 idle=nop root=PARTUUID=<uuid> rootfstype=ext4 rootwait
```

(`maxcpus=1 idle=nop` per the proven M4 bring-up; `console=ttydc0` for remote
console; `rootwait` plus the init's own 30 s wait covers USB enumeration.)

## Read-only first-boot procedure (stops before rig run)

1. Boot the SMOKE artifact set first (no `root=`): confirm on the DockChannel
   console that a USB device enumerates on a forced-host port and that
   `/proc/partitions` shows a `sd*` disk that stays present for >10 s (rules out
   the gadget-style post-enumeration deafness). Record which physical port worked.
2. Only if smoke passes: populate the external rootfs, then boot the ROOT
   artifact set with `root=PARTUUID=…`. Verify `switch_root` reaches the external
   userland's shell.
3. The internal SSD is never read or written by Linux at any step.

## Gates (why this stops here)

1. **Build/branch integration.** ✅ **Resolved 2026-07-21.** The dwc3-apple USB
   work and the T6041 PMGR series both live on `wallace/t6040-bringup`; all three
   USB-path patches apply as a clean stack and the `USB_HOST=1` image builds on
   that branch. No further integration/rebase is needed.
2. **Rig smoke test before the rootfs.** The parked gadget effort enumerated once
   then went deaf (suspected missing `atc-phy,t6040` USB2 PHY driver / wrong
   dwc3-apple wrapper offsets; `done/2026-07-11-t6040-usb-gadget-plan.md`). Host
   mode may share that failure. So the SMOKE test must pass on the rig before an
   external rootfs is populated — do not invest in the rootfs on the assumption
   host works. This is the next rig experiment to propose (needs the lease + CJ).

## Built artifacts (2026-07-21, gate 1 cleared)

Kernel source commit: `96ac043df12fd3b8648505c51933b1552d033c4c`
(`wallace/t6040-bringup`). The applied build-tree binary diff hashes to
`e2e6e5b3e0f700a6497446da2b4679290a78a98351ed4ea0dde3a380b738b5ed`.
The successful build used `DOCKCHANNEL=1 USB_HOST=1 NPROC=1` in isolated build
directory `/build/linux-usb-host4`; output from a separate tree that exhibited
transient missing dependency/object files was discarded.

| Artifact | SHA-256 |
|---|---|
| `Image-usb-host` | `6f0daf57baf942d6e1f43d8efa2ebd4160e976c02ccfaad232dd42e918eb7482` |
| `t6040-j614s-dcuart-usb-host.dtb` | `47b01f9e8922410365e26e21bfb2e92814ac8158585d5a6c16dd97e956731fb4` |
| `t6040-j614s-dcuart-usb-host-left-front.dtb` | `6e6f6bfa4eee896211516ac04e242f96fc650410900b8641fc5bcee443a2d430` |
| `t6040-j614s-dcuart-usb-host-right.dtb` | `9bee944b8bb0d6d7ab541962ea2edc9a57c4069fedcd6c32db21e3b824a43759` |
| `initramfs-usb-root.cpio.gz` | `8b9b80c4eaad07aa0efa578a827f9d0766be81e9a4aed2650e748b1fc65993c8` |
| `System.map-usb-host` | `019d7504716788f6bda8b22a6bdbef94b89a940128be4083ae3d2f1d491d9d47` |
| `config-usb-host` | `8e11399b172035f7d88c0915ccfbf1bb277eb16097462336c4158b54d8d6bc80` |

The Image's extracted embedded config is byte-identical to `config-usb-host`.
The initramfs contains `/newroot`, its `/init` is byte-identical to
`scripts/t6040-init-usb-root`, and all required BusyBox applets are present.
The original decompiled DTB contains three fixed high-speed host ports and is
now retired from live eligibility. The two 2026-07-21 one-port DTBs separately
enable only left-front (`usb-drd1`) or right (`usb-drd2`), leaving the
left-back DebugUSB controller, all unused USB/DART nodes, the ANS mailbox,
SART, and internal NVMe disabled. They were rebuilt and independently
re-reviewed after correcting the inherited DockChannel interrupt from ADT 360
to measured 816; poll mode means that line is not requested in this test.
Static verification only; the first live test remains review- and
approval-gated.

No rig, MMIO, or storage access was performed.
