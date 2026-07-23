# T6040 USB-attached root — daily-driver storage design (2026-07-14)

Ticket 009 (offline, P1, storage track). End-to-end design for running the J614s
as a daily-drivable Linux machine with its **root filesystem on an external USB
disk**, since internal NVMe is blocked behind SPTM (ticket 008). This is the
umbrella design; ticket 031 audits the USB2-host DT/access path and ticket 032
builds the reproducible artifact set defined here. Static design only; no rig, no
storage access.

## Why external root

Ticket 008 concluded internal NVMe under raw boot is NO-GO near-term: the
T8140-class controller mediates all queue setup through Apple's signed SPTM, and
raw m1n1 boot has no guarded entry (`done/2026-07-14-t6040-nvme-sptm-route-finding.md`).
Rather than wait on upstream SPTM support, boot Linux entirely from external USB
storage. This yields the honest "my MacBook boots Linux from disk and stays up"
milestone (ROADMAP Stage D / Stage H) without touching the internal SSD.

## The two-storage-domain architecture

The design's load-bearing idea is that the machine has **two independent storage
paths**, and Linux only ever uses the second:

1. **Boot-chain path (internal SSD, Apple-signed).** iBoot runs in the Apple
   secure-boot context and *can* read the internal SSD. It loads the enrolled
   boot object — m1n1 with the kernel + DTB + initramfs appended — into RAM.
   Nothing after iBoot re-reads the internal SSD.
2. **Linux runtime path (external USB2 disk).** Once the kernel is running it has
   **no** access to the internal NVMe namespace (SPTM-gated; ticket 008 — this is
   a hard firewall, not a policy we must enforce). Its root filesystem lives on an
   external USB disk it brings up itself.

Consequence: the kernel/DTB/initramfs are *delivered* off the internal disk by
the boot chain, but all *persistent Linux state* lives on the external disk. The
SPTM gate that blocks internal NVMe also guarantees Linux cannot accidentally
write the macOS namespace — the safety property comes for free.

## End-to-end boot flow

**Enrolled / daily-driver (target):**

1. Power on → iBoot selects the enrolled Asahi boot object from the internal
   disk's preboot/APFS area (raw-boot-object enrollment; asahi-installer style,
   tickets 024/026).
2. iBoot loads `m1n1 + kernel + DTB + initramfs` into RAM and enters m1n1.
3. m1n1 (`kboot`) prepares the FDT and hands off to the Linux kernel with the
   embedded initramfs; ATC tunables fail-soft to USB2-only (expected, see below).
4. Kernel mounts the initramfs, brings up the USB2 host controller + DART, and
   enumerates the external disk.
5. initramfs finds the root partition by stable id (PARTUUID/LABEL), mounts it,
   `switch_root` into the external rootfs.
6. Full Linux runs from USB; internal SSD untouched.

**Tethered / dev variant (available today):** steps 1–2 are replaced by the
existing DebugUSB dev loop (`macvdmtool` reboot → `chainload.py` of m1n1+payload
over the DFU port). Steps 3–6 are identical. This lets 032's artifacts be
exercised before raw enrollment (ticket 024) is finished.

Note the tether/port coupling (below): the DebugUSB tether occupies the port
whose USB2 PHY m1n1 initialized, which is also the most reliable host port — so
the tethered dev variant and the external-disk-on-that-port case interact and
must be validated deliberately (ticket 031).

## USB2 host mode on M4 — the real constraint

From the ATC/USB DART audit (`done/2026-07-10-t6040-atc-usb-dart-plan.md`) and
the current DT (`arch/arm64/boot/dts/apple/t6040.dtsi`):

- `usb-drd0..2` = `usb-drd,t6040` + `usb-drd,t8132`; DARTs are `dart,t8110`
  (fully supported); power domains `ps_atcN_usb`. The kernel has an Apple dwc3
  glue (`drivers/usb/dwc3/dwc3-apple.c`, `apple,t8103-dwc3`).
- **USB3 + Thunderbolt are deferred**: no `atc-phy,t6040` driver, and the per-
  bucket PHY `reg_offset`s are unknown (must be RE'd or come from an upstream
  t6040 DTS). So external storage runs at **USB2 high-speed (480 Mbps)**.
- **No supported Linux HPM/Type-C path on M4**: the ADT has SPMI HPM nodes, but
  the current DT/driver set does not expose their cable/role/orientation flow to
  dwc3-apple. The current DT therefore pins all three ports to
  `dr_mode = "peripheral"` + `apple,force-device-mode`, "reusing the PHY
  configuration m1n1 leaves behind on the tether port."

For host mode we invert that on the chosen port: `dr_mode = "host"`, drop
`apple,force-device-mode`, keep the DART/power/USB2 (`maximum-speed =
"high-speed"`) wiring. Whether a port comes up in host mode **without** an
atcphy/PD driver depends on the USB2 PHY state m1n1/iBoot leaves behind and on
downstream VBUS — this is exactly what ticket 031 must establish, not assume.

## DT delta (host variant, for ticket 031/032)

A `t6040-j614s-usb-host.dts` sibling of the gadget variant, enabling one audited
port, e.g.:

```dts
&usbN_dart0 { status = "okay"; };
&usbN_dart1 { status = "okay"; };
&usb_drdN {
    /delete-property/ apple,force-device-mode;
    dr_mode = "host";
    /* keep: apple,t8103-dwc3, t8110 DARTs, ps_atcN_usb, high-speed */
    status = "okay";
};
```

Port index N and whether more than one port should be enabled are ticket-031
outputs. Do not enable ATC PHY / USB3 / Thunderbolt nodes.

## initramfs responsibilities

The appended initramfs (ticket 032 builds it) must, with no dependency on the
internal SSD:

- Contain (built-in or as modules loaded in order): `dwc3` + `dwc3-apple`,
  `xhci-hcd`, `apple-dart` (iommu), `usb-storage` and `uas`, and the rootfs
  filesystem driver (`ext4` proposed).
- Bring up the host controller, wait for the external disk to enumerate (bounded
  timeout with ret/log), and resolve root by **stable id** (`root=PARTUUID=…` or
  `LABEL=`), never by unstable `/dev/sdX`.
- `switch_root` (or `pivot_root`) into the external rootfs; on failure, drop to a
  diagnostic shell on `ttydc0` rather than touching any internal device.
- Carry the firmware needed for the boot-critical path only; the full Asahi
  firmware corpus (WiFi/BT/etc, tickets 014/016/030) lives on the external rootfs,
  not the initramfs.

## Artifact set (defines ticket 032)

Reproducible, hash-pinned, built on ticket 031's audited USB2-host candidate:

1. `Image` (kernel) — config with USB host stack + apple-dart + usb-storage/uas +
   ext4 built-in enough to reach root; record the config delta from the known-good
   BusyBox build.
2. `t6040-j614s-usb-host.dtb` — the host DT variant above.
3. `initramfs-usb-root.cpio.gz` — modules + root-discovery/switch_root init +
   boot-critical firmware.
4. Bootargs: `root=PARTUUID=<uuid> rootfstype=ext4 rootwait` (+ the proven
   `console=ttydc0`, `maxcpus=1`, `idle=nop` bring-up args).
5. The external rootfs image/layout (partition scheme, LABEL/PARTUUID, base
   userland) and how it is populated.
6. Module/firmware manifest and per-file SHA-256.
7. A **read-only first-boot procedure**: how to verify enumeration and the pivot
   without writing the internal SSD, stopping before any rig-run proposal.

## Open questions for ticket 031 (DT audit)

1. Which physical Type-C port maps to which `usb-drd` index, and which has a
   usable USB2 PHY state at Linux handoff (the one m1n1 left initialized)?
2. Does `dr_mode = "host"` bring the port up **without** an atcphy/HPM driver,
   and is downstream **VBUS** actually supplied (the HPM is behind SPMI and not
   described to Linux; is port power on by default or forbidden to touch)?
3. Can host and the DebugUSB tether coexist (different ports), or does using the
   only PHY-initialized port for storage cost the tether?
4. Confirm the per-port IRQ (the DT flags the first-ADT-entry IRQ as an untested
   assumption) and the DART stream mappings for host-mode DMA.

## Risks & mitigations

- **VBUS/port-power gated behind SMC/PMU** → external device never powers. If so,
  a **self-powered** enclosure or a powered hub sidesteps it; note that PMU writes
  are forbidden, so we rely on default port power, not programming it.
- **USB2-only throughput** (~40 MB/s) → acceptable for a daily driver; a real fix
  is the deferred ATC PHY tunables (USB3), tracked upstream (ticket 023).
- **Only the tether port has a live PHY** → dev use may need to choose between
  tether and storage until an atcphy driver exists; document the chosen port.
- **Disk enumeration races boot** → `rootwait` + bounded retry + diagnostic-shell
  fallback; never fall back to an internal device.

## Milestone & scope

Success = the machine boots mainline Linux to a shell **with its root on an
external USB disk**, reproducibly, with the internal SSD never read or written by
Linux. This is the Stage D storage exit and a Stage H interim-boot building block
(with ticket 024's raw enrollment for the untethered case).

Design only. No rig, no MMIO, no storage access. Ticket 031 next (USB2-host DT
audit + access manifest), then ticket 032 (build the artifact set above).
