# t6040 USB gadget console — plan (started 2026-07-11, session 4)

Goal: after m1n1→Linux handoff, Linux re-enumerates on the same tether cable
as a USB gadget (ACM serial first, NCM ethernet+SSH later) so the agent can
read/drive the machine directly instead of via screen photos.

## Why this is feasible now

- Mainline 7.2-rc2 already has the whole Apple USB stack:
  `drivers/usb/dwc3/dwc3-apple.c` (compatible `apple,t8103-dwc3`),
  `drivers/phy/apple/atc.c` (atcphy incl. ADT-named tunables),
  `drivers/usb/typec/tipd` (CD321x PD). t8103.dtsi has complete template
  nodes (dwc3 + 2-SID DART iommus + atcphy phys/resets + usb-role-switch).
- m1n1's proxy runs on these very ports → PHY/wrapper proven alive on M4.
- Strong precedent: early Asahi ran the USB gadget with dwc3 alone and the
  bootloader-configured PHY, before atcphy existed.

## J614s ADT facts (from offline j614s.adt)

- `usb-drd0/1/2` compatible `usb-drd,t6040` + `usb-drd,t8132`; 6 reg blocks
  (dwc3 core at 0x382280000/0x38a…/0x392… + wrapper blocks).
  IRQs: drd0 [1619..1622], drd1 [1651..1654, 943], drd2 [1683..1686, 953].
  clock-gates present (pmgr device 299 for drd0).
- `dart-usb0/1/2` (`dart,t8110`) at 0x382f00000/… IRQs 1623/1655/1687 —
  NOTE: two DART instances per port in t8103 template (SID 0+1); our reg list
  shows two DART blocks (0x382f00000 + 0x382f80000) matching m1n1's
  "dart-usb0 at 0x382f80000" log.
- `atc-phy0..3` compatible `atc-phy,t6040` (atc.c has no t6040 compatible —
  PHY driver support would be new work).
- **No HPM/CD321x on any AP i2c bus** (only audio codecs, `uatcrt0-2`
  retimers on i2c6, `pcon0` on i2c8). M4 gen moved PD handling away from the
  AP → the mainline tipd/typec flow does not apply as-is. This is the
  strongest argument for the phy-less shortcut.

## Plan (phased)

1. **Phase 1 — dwc3 peripheral-mode, no atcphy (the shortcut):**
   - DT: three `usb@…` nodes compatible `apple,t8103-dwc3` (check the glue's
     requirements; fall back to `snps,dwc3` core-only if the wrapper wants
     phys), `dr_mode = "peripheral"`, `usb-role-switch` off, iommus → the
     port DARTs (bypass-forced like MTP, so trivial), power-domains from our
     pmgr dtsi if modelled (drd0 clock-gate = pmgr id 299) else rely on
     pd_ignore_unused.
   - Do NOT reset the PHY; dwc3 core soft-reset is expected to renegotiate
     on the m1n1-configured link.
   - Config: USB_DWC3(+APPLE glue), USB_GADGET, USB_G_SERIAL=y (ACM);
     init spawns getty on /dev/ttyGS0. Host: new /dev/cu.usbmodem* appears →
     direct two-way console for the agent.
   - Gadget on all three ports; whichever has the cable enumerates.
2. **Phase 2 — NCM ethernet + dropbear** in a fatter initramfs (file
   transfer, ssh, log streaming).
3. **Phase 3 (proper) — atcphy support for `atc-phy,t6040`**: new tunables/
   offsets from ADT, plus figuring out M4 PD/orientation without HPM.
   Only needed for hotplug/role-switch robustness, not for a fixed tether.

## Phase-1 artifacts (built 2026-07-11, untested on HW)

- DT: `usb_drd0..2` (snps,dwc3, peripheral, core reg +0..0xcd00, first ADT
  IRQ) + 2 DART nodes per port in t6040.dtsi (disabled);
  `t6040-j614s-usb.dts` = kbd variant + all USB nodes enabled.
  DTB `t6040-j614s-usb.dtb`
  SHA-256 a7678e9bbe9974d08076349b7b299b24163262baa3c5b620b0096f5b6483af20
- Kernel `Image-gadget` (kbd config + USB_DWC3/DUAL_ROLE + USB_CONFIGFS_ACM
  + U_SERIAL_CONSOLE)
  SHA-256 f1c80533f85aeb98e955341ce6f8eb69f5a9432f3f8a653088a29a5b9bec15a0
- `initramfs-gadget.cpio.gz` (init = .plans/t6040-init-gadget: keyboard init
  + configfs ACM gadget per UDC + respawning shells on /dev/ttyGS*)
  SHA-256 980d787432eaff3190100caf0204194bfb22ba52357722ef156460adec0ee8d2
- kbuild.sh: GADGET=1 env adds the config block; bootcap-fb.sh: IMAGE env
  selects the kernel.

Test: `IMAGE=Image-gadget bash .plans/t6040-bootcap-fb.sh t6040-j614s-usb.dtb
initramfs-gadget.cpio.gz`, then watch the HOST for a new /dev/cu.usbmodem*
("M4 Pro gadget console"). Screen shows UDC/gadget diagnostics from init.

## Investigation log (2026-07-12): root cause found — post-enumeration deafness

Phase-1 (raw snps,dwc3) enumerated on the host every time but NO host driver
could go further. Eliminated one by one: descriptors (final gadget was
byte-equivalent to m1n1's proven CDC layout: vid/pid/class/power/bcdUSB 2.00
via maximum-speed=high-speed + snps,usb2-gadget-lpm-disable; f_acm IAD
removed by patch), macOS accessory policy, the ChatGPT desktop app squatting
AppleUSBHostDeviceUserClient on every new device (real, but not the cause —
kill it anyway during bring-up), legacy AppleUSBCDCCompositeDevice kext
(!registered even on WORKING m1n1 devices — red herring), runtime PM.

Ground truth via ftrace lap (Image-gadget-trace + auto-enabled dwc3/irq
events in init): **all dwc3 events stop at t≈7.5s (enumeration + gadget-side
prompt writes); host control transfers afterwards genuinely time out on the
wire (libusb ETIMEDOUT) with ZERO new dwc3 events/interrupts** (IRQ count
frozen at ~43). The controller goes deaf right after enumeration.

Explanation that fits everything: with no host driver attached, macOS
suspends the port ~ms after enumeration; surviving bus suspend/resume on
this platform requires the Apple-specific SUSPHY/PHY dance that
drivers/usb/dwc3/dwc3-apple.c performs ("This platform requires SUSPHY to be
enabled here already..."). m1n1's device gets claimed instantly (never
suspended) → never trips it. Raw snps,dwc3 has nobody to do that dance.

Device-side rebinding is also unsafe without the glue: `echo "" > UDC`
wedges the controller (ep0 end-transfer timeouts, "failed to enable ep0out"
loop after host-side port reset). One clean enumeration per boot.

## Phase 1b (current): dwc3-apple glue without atcphy/tipd

dwc3-apple is in mainline and handles SUSPHY/wrapper/suspend, but waits for
a Type-C cable event that the current Linux DT has no supported SPMI-HPM path to deliver, and
requires a reset control (normally atcphy). Local patch:
- devm_reset_control_get_exclusive → _optional_ variant.
- New DT bool `apple,force-device-mode`: at probe end, immediately run
  dwc3_apple_init(DWC3_APPLE_DEVICE) (no cable event needed;
  phy_set_mode(NULL) no-ops without phys).
DT: compatible apple,t8103-dwc3; reg split per t8103 precedent
(core +0..0xcd00, apple wrapper +0xcd00..0x10000 of the ADT block);
reg-names dwc3-core/dwc3-apple; CONFIG_USB_DWC3_APPLE=y.

## PARKED (2026-07-12) — status and handoff

Phase 1b (dwc3-apple glue, reset-optional + apple,force-device-mode patch,
t8103 reg split) probed, forced device-mode init worked, gadget enumerated —
but **EP0 still goes deaf right after enumeration** (host string reads
ETIMEDOUT, same as raw snps,dwc3). The glue's SUSPHY dance alone does not fix
the post-enumeration deafness on t6040.

Remaining hypotheses for whoever picks this up (in likelihood order):
1. The Apple wrapper ("dwc3-apple" reg block) offsets/values differ on the
   M4 generation — setup_cio()/set_ptrcap() were written for t8103-t602x;
   t6040 may need different offsets (get a t8122/t8132 reference or trace
   macOS). A wrong CIO setup could leave event forwarding half-broken.
2. Real suspend/resume handling needs the USB2 PHY driver (atcphy port for
   atc-phy,t6040) — phy_set_mode(NULL) no-ops mean the PHY never gets told
   about device mode/suspend; iBoot's leftover PHY state may only carry the
   first enumeration.
3. Something AIC-side: dwc3 events stop reaching the CPU (irq count frozen)
   — could be dwc3-internal (event buffer) or interrupt-line related.

Evidence preserved: ftrace lap shows all dwc3 activity ends at enumeration
+ gadget writes; host transfers afterwards never generate device events.

What still works / keepers from this effort:
- The keyboard+trackpad boot is unaffected (Image / Image-keyboard).
- Image-gadget-trace (83b7ccdd…) = kbd config + gadget + ftrace + TER16x32
  big console font; boots fine, useful for any future tracing.
- fbcon=font:TER16x32 now in bootcap-fb.sh; CONFIG_FONT_TER16x32 in kbuild.
- Working artifacts for the eventual real fix: DT nodes (3 ports), dwc3-apple
  force-device-mode patch (container tree), configfs init, acm_bridge.py.

**Recommended next comms channel: TB4 cable + macvdmtool + dockchannel
serial** (apple_dockchannel_tty driver already in origin/dockchannel; m1n1
already initializes the J614s dockchannel UART at 0x508828000; needs m1n1
PR #594-style SPMI serial-mode entry). Solves early-boot visibility too.

## Risks

- dwc3-apple glue may hard-require phys/resets → use core `snps,dwc3`
  binding directly on reg block 0 as fallback.
- dwc3 core reset might drop something only the PD/PHY can restore → if
  enumeration fails, compare wrapper regs (reg blocks 1/3-5) before/after
  via a status initramfs devmem dump.
- Which reg block is which (core vs apple wrapper vs atc wrap) needs one
  careful mapping pass against t8103.dtsi reg-names + m1n1's usb.c.
